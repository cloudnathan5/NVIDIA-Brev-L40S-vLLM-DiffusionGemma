#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_root="$repo_root/benchmarking/artifacts"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
export AIPERF_BIN="${AIPERF_BIN:-$HOME/.local/bin/aiperf}"
export HF_TOKEN="${HF_TOKEN:-}"

gemma_compose="$repo_root/serve-gemma-docker/docker-compose.yml"
diffgemma_compose="$repo_root/serve-diffgemma-docker/docker-compose.yml"
port_forward_pid=""

for tool in curl docker kubectl nvidia-smi python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required command: $tool" >&2
    exit 1
  fi
done

if [[ ! -x "$AIPERF_BIN" ]]; then
  echo "AIPerf is not installed. Run benchmarking/install-benchmark-tools.sh." >&2
  exit 1
fi

if [[ -z "${VLLM_API_KEY:-}" ]]; then
  encoded_api_key="$(kubectl get secret -n dynamo-system vllm-api-key \
    -o jsonpath='{.data.VLLM_API_KEY}' 2>/dev/null || true)"
  if [[ -n "$encoded_api_key" ]]; then
    VLLM_API_KEY="$(printf '%s' "$encoded_api_key" | base64 --decode)"
    export VLLM_API_KEY
  fi
fi

mkdir -p "$artifact_root/logs"

stop_port_forward() {
  if [[ -n "$port_forward_pid" ]]; then
    kill "$port_forward_pid" >/dev/null 2>&1 || true
    wait "$port_forward_pid" >/dev/null 2>&1 || true
    port_forward_pid=""
  fi
}

stop_compose() {
  docker compose -f "$gemma_compose" down --remove-orphans >/dev/null 2>&1 || true
  docker compose -f "$diffgemma_compose" down --remove-orphans >/dev/null 2>&1 || true
}

stop_dynamo() {
  stop_port_forward
  kubectl delete -n dynamo-system dgd gemma-disagg diffgemma-disagg \
    --ignore-not-found --wait=true >/dev/null 2>&1 || true
}

cleanup() {
  status=$?
  trap - EXIT
  set +e
  stop_port_forward
  stop_compose
  stop_dynamo
  exit "$status"
}
trap cleanup EXIT

wait_for_endpoint() {
  local name="$1"
  local attempts="${2:-360}"
  local auth_header=()

  if [[ -n "${VLLM_API_KEY:-}" ]]; then
    auth_header=(-H "Authorization: Bearer $VLLM_API_KEY")
  fi

  for (( attempt=1; attempt<=attempts; attempt++ )); do
    if curl --silent --fail --max-time 5 "${auth_header[@]}" \
      http://127.0.0.1:8000/health >/dev/null; then
      echo "$name is ready."
      return 0
    fi
    sleep 5
  done

  echo "Timed out waiting for $name." >&2
  return 1
}

show_gpu_state() {
  nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu \
    --format=csv,noheader
}

run_compose_model() {
  local name="$1"
  local compose_file="$2"
  local conc1_script="$3"
  local conc5_script="$4"

  echo "Stopping Kubernetes and Compose inference workloads..."
  stop_dynamo
  stop_compose

  echo "Starting regular vLLM for $name..."
  docker compose -f "$compose_file" up -d
  if ! wait_for_endpoint "vLLM $name"; then
    docker compose -f "$compose_file" logs --tail 300 >&2
    return 1
  fi
  show_gpu_state

  bash "$repo_root/benchmarking/$conc1_script"
  bash "$repo_root/benchmarking/$conc5_script"

  echo "Stopping regular vLLM for $name..."
  docker compose -f "$compose_file" down --remove-orphans
}

run_dynamo_model() {
  local name="$1"
  local deployment="$2"
  local manifest="$3"
  local service="$4"
  local conc1_script="$5"
  local conc5_script="$6"

  echo "Stopping Compose and Kubernetes inference workloads..."
  stop_compose
  stop_dynamo

  echo "Starting Dynamo disaggregated serving for $name..."
  kubectl apply -n dynamo-system -f "$repo_root/$manifest"
  kubectl wait -n dynamo-system --for=condition=Ready \
    "dgd/$deployment" --timeout=45m

  kubectl port-forward -n dynamo-system "service/$service" 8000:8000 \
    >"$artifact_root/logs/${deployment}-port-forward.log" 2>&1 &
  port_forward_pid=$!
  wait_for_endpoint "Dynamo $name"
  show_gpu_state

  bash "$repo_root/benchmarking/$conc1_script"
  bash "$repo_root/benchmarking/$conc5_script"

  echo "Stopping Dynamo disaggregated serving for $name..."
  stop_dynamo
}

cd "$repo_root"

run_compose_model \
  "Gemma 4" \
  "$gemma_compose" \
  aiperf_gemma_conc1.sh \
  aiperf_gemma_conc5.sh

run_dynamo_model \
  "Gemma 4" \
  gemma-disagg \
  gemma-disagg.yaml \
  gemma-disagg-frontend \
  aiperf_dynamo_gemma_conc1.sh \
  aiperf_dynamo_gemma_conc5.sh

run_compose_model \
  "DiffusionGemma" \
  "$diffgemma_compose" \
  aiperf_diffgemma_conc1.sh \
  aiperf_diffgemma_conc5.sh

if ! sudo k3s ctr images list | grep -F \
  'docker.io/library/diffgemma-dynamo:1.3.0-dev.1' >/dev/null; then
  bash "$repo_root/build-diffgemma-dynamo-runtime.sh"
fi

run_dynamo_model \
  "DiffusionGemma" \
  diffgemma-disagg \
  diffgemma-disagg.yaml \
  diffgemma-disagg-frontend \
  aiperf_dynamo_diffgemma_conc1.sh \
  aiperf_dynamo_diffgemma_conc5.sh

python3 "$repo_root/benchmarking/plot-results.py"

echo "All benchmark runs and graphs are in $artifact_root."
