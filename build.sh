#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${CONT_SYMBFUZZ:=$SCRIPT_DIR}"

cd "$CONT_SYMBFUZZ"

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install -e .

./build/symbfuzz --help >/dev/null
symfuzz --help >/dev/null
