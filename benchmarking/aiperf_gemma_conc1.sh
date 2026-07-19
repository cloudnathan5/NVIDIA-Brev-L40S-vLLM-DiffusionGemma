#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/aiperf-common.sh"

run_aiperf \
  "gemma-26B" \
  "nvidia/Gemma-4-26B-A4B-NVFP4" \
  1 \
  "$script_dir/artifacts/vllm/gemma/conc1"
