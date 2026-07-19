#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/aiperf-common.sh"

run_aiperf \
  "diffusiongemma-26B" \
  "nvidia/diffusiongemma-26B-A4B-it-NVFP4" \
  1 \
  "$script_dir/artifacts/dynamo/diffgemma/conc1"
