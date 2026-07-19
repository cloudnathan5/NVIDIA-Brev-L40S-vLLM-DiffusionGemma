#!/usr/bin/env bash
set -euo pipefail

DYNAMO_PACKAGE_VERSION="${DYNAMO_PACKAGE_VERSION:-1.3.0.dev1}"
DYNAMO_IMAGE_TAG="${DYNAMO_IMAGE_TAG:-1.3.0-dev.1}"
DIFFGEMMA_DYNAMO_IMAGE="${DIFFGEMMA_DYNAMO_IMAGE:-diffgemma-dynamo:${DYNAMO_IMAGE_TAG}}"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This builder supports Linux hosts only." >&2
  exit 1
fi

for tool in docker k3s nvidia-smi; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required command: $tool" >&2
    exit 1
  fi
done

driver_major="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader \
  | head -n 1 | cut -d. -f1)"
if [[ ! "$driver_major" =~ ^[0-9]+$ ]] || (( driver_major < 580 )); then
  echo "DiffusionGemma's CUDA 13 runtime requires NVIDIA driver 580 or newer." >&2
  exit 1
fi

if (( EUID == 0 )); then
  sudo_cmd=()
else
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required when this script is not run as root." >&2
    exit 1
  fi
  sudo_cmd=(sudo)
fi

if docker info >/dev/null 2>&1; then
  docker_cmd=(docker)
elif "${sudo_cmd[@]}" docker info >/dev/null 2>&1; then
  docker_cmd=("${sudo_cmd[@]}" docker)
else
  echo "Cannot access the Docker daemon." >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "Building ${DIFFGEMMA_DYNAMO_IMAGE}..."
"${docker_cmd[@]}" build \
  --build-arg "DYNAMO_PACKAGE_VERSION=${DYNAMO_PACKAGE_VERSION}" \
  --tag "$DIFFGEMMA_DYNAMO_IMAGE" \
  "$script_dir/serve-diffgemma-dynamo"

echo "Validating Dynamo, vLLM, and CUDA NIXL imports..."
"${docker_cmd[@]}" run --rm --gpus all --entrypoint python3 \
  "$DIFFGEMMA_DYNAMO_IMAGE" -c \
  "import dynamo.runtime, nixl_ep, vllm; print('vLLM', vllm.__version__)"

echo "Importing ${DIFFGEMMA_DYNAMO_IMAGE} into K3s..."
"${docker_cmd[@]}" save "$DIFFGEMMA_DYNAMO_IMAGE" \
  | "${sudo_cmd[@]}" k3s ctr images import -

"${sudo_cmd[@]}" k3s ctr images list \
  | grep -F "docker.io/library/${DIFFGEMMA_DYNAMO_IMAGE}"

echo "DiffusionGemma Dynamo runtime is ready for diffgemma-disagg.yaml."
