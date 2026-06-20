#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${CONT_SYMBFUZZ:=$SCRIPT_DIR}"
: "${EXAMPLE_VERILOG:=examples/counter.v}"
: "${EXAMPLE_TOP:=counter}"
: "${EXAMPLE_STAMP:=$(date +%Y%m%d_%H%M%S)}"
: "${EXAMPLE_OUTPUT_DIR:=fuzz_runs/${EXAMPLE_TOP}_${EXAMPLE_STAMP}}"
: "${EXAMPLE_MODE:=auto}"
: "${EXAMPLE_TIMEOUT:=30}"
: "${EXAMPLE_STALL_CYCLES:=100}"
: "${EXAMPLE_BMC_MAX_STEPS:=20}"
: "${EXAMPLE_EXTRA_ARGS:=}"

cd "$CONT_SYMBFUZZ"

if [[ ! -x build/symbfuzz ]]; then
	echo "Missing BMC binary: $PWD/build/symbfuzz"
	exit 1
fi

if [[ ! -x .venv/bin/symfuzz ]]; then
	echo "Missing Python CLI: $PWD/.venv/bin/symfuzz"
	exit 1
fi

have_xsim=0
if command -v xsim >/dev/null 2>&1 && command -v xvlog >/dev/null 2>&1 && command -v xelab >/dev/null 2>&1; then
	have_xsim=1
fi

case "$EXAMPLE_MODE" in
	auto)
		if [[ "$have_xsim" -eq 1 ]]; then
			mode=full
		else
			mode=gen
		fi
		;;
	gen|full)
		mode="$EXAMPLE_MODE"
		;;
	*)
		echo "Unsupported EXAMPLE_MODE=$EXAMPLE_MODE (use auto, gen, or full)" >&2
		exit 2
		;;
esac

if [[ "$mode" == "full" && "$have_xsim" -ne 1 ]]; then
	echo "EXAMPLE_MODE=full requires xsim, xvlog, and xelab on PATH" >&2
	exit 1
fi

if [[ "$mode" == "gen" && "$EXAMPLE_MODE" == "auto" ]]; then
	echo "[symbfuzz wrapper] xsim/xvlog/xelab not found; running generation-only smoke test"
fi

mkdir -p "$(dirname "$EXAMPLE_OUTPUT_DIR")"
rm -rf "$EXAMPLE_OUTPUT_DIR"

args=(
	"$EXAMPLE_VERILOG"
	--top "$EXAMPLE_TOP"
	--output-dir "$EXAMPLE_OUTPUT_DIR"
	--stall-cycles "$EXAMPLE_STALL_CYCLES"
	--bmc-max-steps "$EXAMPLE_BMC_MAX_STEPS"
	--timeout "$EXAMPLE_TIMEOUT"
)

if [[ "$mode" == "gen" ]]; then
	args+=(--gen-only)
fi

# shellcheck disable=SC2206
extra_args=($EXAMPLE_EXTRA_ARGS)

source .venv/bin/activate
symfuzz "${args[@]}" "${extra_args[@]}"

echo
echo "=== symbfuzz output summary ==="
echo "Mode: $mode"
echo "Output directory: $PWD/$EXAMPLE_OUTPUT_DIR"
if [[ -d "$EXAMPLE_OUTPUT_DIR" ]]; then
	find "$EXAMPLE_OUTPUT_DIR" -maxdepth 2 -type f | sort | tail -n 40 | sed 's|^|  |'
fi
