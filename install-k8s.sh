#!/usr/bin/env bash
set -euo pipefail

K3S_CHANNEL="${K3S_CHANNEL:-stable}"
K3S_VERSION="${K3S_VERSION:-}"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This installer supports Linux hosts only." >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot identify the Linux distribution." >&2
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *)
    echo "This installer currently supports Ubuntu and Debian; found ${ID:-unknown}." >&2
    exit 1
    ;;
esac

if ! command -v sudo >/dev/null 2>&1 && (( EUID != 0 )); then
  echo "sudo is required when this script is not run as root." >&2
  exit 1
fi

if (( EUID == 0 )); then
  sudo_cmd=()
else
  sudo_cmd=(sudo)
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "nvidia-smi was not found. Install the NVIDIA host driver first." >&2
  exit 1
fi

echo "Detected NVIDIA GPU driver:"
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader

"${sudo_cmd[@]}" apt-get update
"${sudo_cmd[@]}" apt-get install -y ca-certificates curl

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

curl --proto '=https' --tlsv1.2 -fsSL \
  https://get.k3s.io -o "$tmp_dir/install-k3s.sh"

k3s_env=(
  INSTALL_K3S_CHANNEL="$K3S_CHANNEL"
  K3S_KUBECONFIG_MODE=644
)
if [[ -n "$K3S_VERSION" ]]; then
  k3s_env+=(INSTALL_K3S_VERSION="$K3S_VERSION")
fi

"${sudo_cmd[@]}" env "${k3s_env[@]}" sh "$tmp_dir/install-k3s.sh"

if [[ -z "${KUBECONFIG:-}" && -r /etc/rancher/k3s/k3s.yaml ]]; then
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
fi

echo "Waiting for the Kubernetes node to become ready..."
"${sudo_cmd[@]}" k3s kubectl wait \
  --for=condition=Ready node --all --timeout=180s

if ! command -v helm >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    -o "$tmp_dir/install-helm.sh"
  chmod 700 "$tmp_dir/install-helm.sh"
  "${sudo_cmd[@]}" env HELM_INSTALL_DIR=/usr/local/bin \
    "$tmp_dir/install-helm.sh"
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "K3s was installed, but kubectl is not available in PATH." >&2
  exit 1
fi

kubectl cluster-info >/dev/null
helm version --short

echo "Kubernetes is ready:"
kubectl get nodes -o wide
echo
echo "Next, run install-dynamo-k8s.sh as your normal user."
