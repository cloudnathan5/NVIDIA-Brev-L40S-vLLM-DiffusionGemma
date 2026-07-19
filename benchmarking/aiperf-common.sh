#!/usr/bin/env bash
set -euo pipefail

run_aiperf() {
  if (( $# != 4 )); then
    echo "Usage: run_aiperf MODEL TOKENIZER CONCURRENCY ARTIFACT_DIR" >&2
    return 2
  fi

  local model="$1"
  local tokenizer="$2"
  local concurrency="$3"
  local default_artifact_dir="$4"
  local aiperf_bin="${AIPERF_BIN:-$HOME/.local/bin/aiperf}"
  local artifact_dir="${AIPERF_ARTIFACT_DIR:-$default_artifact_dir}"
  local -a api_args=()

  if [[ ! -x "$aiperf_bin" ]]; then
    echo "AIPerf not found at $aiperf_bin. Run benchmarking/install-benchmark-tools.sh." >&2
    return 1
  fi

  if [[ -n "${VLLM_API_KEY:-}" ]]; then
    api_args=(--api-key "$VLLM_API_KEY")
  fi

  mkdir -p "$artifact_dir"
  "$aiperf_bin" profile \
    --model "$model" \
    --tokenizer "$tokenizer" \
    --streaming \
    --endpoint-type chat \
    --extra-inputs '{"chat_template_kwargs":{"enable_thinking":true}}' \
    --url http://localhost:8000 \
    --request-count 10 \
    --random-seed 42 \
    --concurrency "$concurrency" \
    --concurrency-min "$concurrency" \
    --artifact-dir "$artifact_dir" \
    --ui none \
    "${api_args[@]}"
}
