#!/bin/bash
# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Authors:
# - Claude (AI)

set -e

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

# Generate file list if not present
if [ ! -f compile_vltor.f ]; then
  bash scripts/compile_vltor.sh
fi

TESTBENCHES=(
  tb_axi_stream_dw_downsizer
  tb_axi_stream_dw_upsizer
)

PASS=0
FAIL=0

for TB in "${TESTBENCHES[@]}"; do
  echo "=== Building $TB ==="
  BUILD_DIR="obj_dir_${TB}"
  rm -rf "$BUILD_DIR"

  verilator \
    --binary \
    --timing \
    --sv \
    -f compile_vltor.f \
    --top-module "$TB" \
    --Mdir "$BUILD_DIR" \
    -Wno-WIDTHEXPAND \
    -Wno-WIDTHTRUNC \
    -Wno-UNUSEDSIGNAL \
    -Wno-UNDRIVEN \
    -Wno-TIMESCALEMOD \
    -Wno-ASCRANGE \
    -Wno-INITIALDLY \
    -Wno-REDEFMACRO \
    2>&1

  echo "=== Running $TB ==="
  set +e
  "$BUILD_DIR/V${TB}" 2>&1 | tee "${TB}.log"
  EXIT_CODE=$?
  set -e

  # Verilator exits with 134 (SIGABRT) on $stop (expected end of test).
  # Detect real failures: assertion errors or %Error lines that are not from $stop.
  if grep -qE '\bAssertion failed\b' "${TB}.log" || \
     grep -E '%Error' "${TB}.log" | grep -qv 'Verilog \$stop'; then
    echo "FAIL: $TB (assertion failure or error detected)"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: $TB (exit code $EXIT_CODE)"
    PASS=$((PASS + 1))
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
