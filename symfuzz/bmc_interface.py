"""
bmc_interface.py — Subprocess wrapper around the compiled symbfuzz BMC binary.
"""
from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from .design_parser import DesignInfo


@dataclass
class BmcResult:
    depth: int
    steps: list[dict[str, int]]     # steps[i] = {port_name: value} at BMC step i
    target: dict[str, int]          # the requested target constraints


class BmcInterface:
    def __init__(
        self,
        symbfuzz_binary: str | Path,
        design: DesignInfo,
        max_steps: int = 40,
        timeout_ms: int = 30_000,
        verbose: bool = False,
    ):
        self.binary  = str(Path(symbfuzz_binary).resolve())
        self.design  = design
        self.max_steps  = max_steps
        self.timeout_ms = timeout_ms
        self.verbose    = verbose
        self.last_status = "not_run"

    def find_sequence(
        self,
        targets: dict[str, int],
    ) -> Optional[BmcResult]:
        """
        Ask BMC to find an input sequence driving the design to *targets*
        (a dict of {arch_name: desired_value}).
        Returns ``None`` if no path is found within *max_steps*.
        """
        # Pass all source files (dependencies first) so Yosys can resolve
        # multi-module designs.  Fall back to verilog_path for single-file cases.
        src_files = self.design.verilog_files or [self.design.verilog_path]
        cmd = [
            self.binary,
            *src_files,
            "--top",    self.design.module_name,
            "--output", "json",
            "--max-steps", str(self.max_steps),
            "--timeout",   str(self.timeout_ms),
            "--clock", self.design.clock_port,
        ]
        for reg_name, value in targets.items():
            cmd += ["--target", f"{reg_name}={value}"]

        if self.verbose:
            print(f"[bmc] {' '.join(cmd)}")

        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=self.timeout_ms / 1000 + 10,
            )
        except subprocess.TimeoutExpired:
            self.last_status = "unknown"
            if self.verbose:
                print("[bmc] timed out")
            return None

        # BMC binary: exit 0 = sat, exit 2 = unsat/not found
        if proc.returncode == 2:
            self.last_status = "bounded_unsat"
            if self.verbose:
                print(f"[bmc] no path to {targets}")
            return None

        if proc.returncode == 3:
            self.last_status = "unknown"
            return None
        if proc.returncode != 0:
            self.last_status = "error"
            raise RuntimeError(f"BMC failed (rc={proc.returncode}): {proc.stderr}")

        # Parse JSON from stdout
        try:
            data = json.loads(proc.stdout)
        except json.JSONDecodeError as e:
            self.last_status = "error"
            raise RuntimeError(f"Invalid BMC witness JSON: {proc.stdout[:200]}") from e

        steps = data.get("steps", [])

        # --clock constrains low/high pairs with stable data inputs.
        # clk2fflogic samples data in the low phase preceding the rising edge.
        # Reject incomplete or mismatched pairs instead of claiming replayability.
        clk = self.design.clock_port
        if not steps or len(steps) % 2:
            raise RuntimeError("BMC witness does not contain complete clock cycles")
        clean_steps = []
        for low, high in zip(steps[::2], steps[1::2]):
            data_low = {k: v for k, v in low.items() if k != clk}
            data_high = {k: v for k, v in high.items() if k != clk}
            if low.get(clk) != 0 or high.get(clk) != 1 or data_low != data_high:
                raise RuntimeError("BMC witness violates stable low/high clock phases")
            clean_steps.append(data_low)
        self.last_status = "sat"

        return BmcResult(
            depth=data.get("depth", len(steps)),
            steps=clean_steps,
            target=targets,
        )
