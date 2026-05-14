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

bender checkout

# Generate Verilator file list, excluding dependency test files
# Note: Verilator auto-defines VERILATOR=1; no need to add it explicitly.
bender script verilator -t test \
    | grep -v '\.bender/git/checkouts/.*/test/' \
    > compile_vltor.f

echo "Generated compile_vltor.f"
