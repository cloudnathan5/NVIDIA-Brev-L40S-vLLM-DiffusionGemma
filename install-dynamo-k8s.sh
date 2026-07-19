#!/usr/bin/env bash
set -euo pipefail

GPU_OPERATOR_VERSION="${GPU_OPERATOR_VERSION:-v26.3.3}"
DYNAMO_PLATFORM_VERSION="${DYNAMO_PLATFORM_VERSION:-1.0.2}"
DYNAMO_NAMESPACE="${DYNAMO_NAMESPACE:-dynamo-system}"
GPU_OPERATOR_NAMESPACE="${GPU_OPERATOR_NAMESPACE:-gpu-operator}"

for tool in kubectl helm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required command: $tool" >&2
    exit 1
  fi
done

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "kubectl cannot reach a Kubernetes cluster. Check your current context." >&2
  exit 1
fi

echo "Using Kubernetes context: $(kubectl config current-context)"

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update
helm repo update nvidia

gpu_operator_args=(
  upgrade --install gpu-operator nvidia/gpu-operator
  --version "$GPU_OPERATOR_VERSION"
  --namespace "$GPU_OPERATOR_NAMESPACE"
  --create-namespace
  --wait
  --timeout 20m
)

# Brev images commonly already have the host NVIDIA driver installed.
if [[ "${GPU_DRIVER_PREINSTALLED:-true}" == "true" ]]; then
  gpu_operator_args+=(--set driver.enabled=false)
fi

# Current GPU Operator releases support K3s through CDI/NRI without rewriting
# K3s's nonstandard containerd configuration paths.
if kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' 2>/dev/null | grep -qi k3s; then
  gpu_operator_args+=(--set cdi.enabled=true --set cdi.nriPluginEnabled=true)
fi

helm "${gpu_operator_args[@]}"

helm upgrade --install dynamo-platform \
  oci://helm.ngc.nvidia.com/nvidia/ai-dynamo/charts/dynamo-platform \
  --version "$DYNAMO_PLATFORM_VERSION" \
  --namespace "$DYNAMO_NAMESPACE" \
  --create-namespace \
  --wait \
  --timeout 15m

if [[ -n "${HF_TOKEN:-}" ]]; then
  kubectl create secret generic hf-token-secret \
    --namespace "$DYNAMO_NAMESPACE" \
    --from-literal=HF_TOKEN="$HF_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo "HF_TOKEN is not set; create hf-token-secret before deploying a model." >&2
fi

if [[ -n "${VLLM_API_KEY:-}" ]]; then
  kubectl create secret generic vllm-api-key \
    --namespace "$DYNAMO_NAMESPACE" \
    --from-literal=VLLM_API_KEY="$VLLM_API_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

kubectl wait --for=condition=Established \
  crd/dynamographdeployments.nvidia.com \
  --timeout=120s

allocatable_gpus="$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' \
  | awk '/^[0-9]+$/ { total += $1 } END { print total + 0 }')"

if (( allocatable_gpus < 2 )); then
  echo "Dynamo is installed, but this cluster exposes ${allocatable_gpus} GPU(s)." >&2
  echo "The disaggregated manifests require at least 2 allocatable GPUs." >&2
  exit 2
fi

echo "Installation complete. The cluster exposes ${allocatable_gpus} GPU(s)."
echo "Deploy one model with:"
echo "  kubectl apply -n $DYNAMO_NAMESPACE -f gemma-disagg.yaml"
echo "or:"
echo "  kubectl apply -n $DYNAMO_NAMESPACE -f diffgemma-disagg.yaml"
