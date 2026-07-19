# NVIDIA-Brev-L40S-vLLM-DiffusionGemma-NVFP4
Contains docker-compose file for NVIDIA Brev L40S instance to run DiffusionGemma at NVFP4 quantization with vLLM and some benchmarking commands and results.

## Dynamo disaggregated serving

The Kubernetes manifests run one prefill worker and one decode worker, using one
GPU each. Install the local K3s cluster and Dynamo platform, then deploy one
model at a time:

```bash
bash install-k8s.sh
bash install-dynamo-k8s.sh

kubectl apply -n dynamo-system -f gemma-disagg.yaml
# Or, for DiffusionGemma:
bash build-diffgemma-dynamo-runtime.sh
kubectl apply -n dynamo-system -f diffgemma-disagg.yaml
```

Gemma uses NVIDIA's stable Dynamo 1.2.1 vLLM runtime. DiffusionGemma was added
after the vLLM 0.20.1 bundled with that runtime, so its manifest uses a local
runtime built from the official `vllm/vllm-openai:gemma` image plus NVIDIA's
Dynamo 1.3 preview packages. The build script imports the resulting image into
K3s. It requires an NVIDIA 580-series or newer driver because the specialized
vLLM image and its NIXL package use CUDA 13.

The Hugging Face token is optional for these public NVIDIA model repositories.
If `HF_TOKEN` is set, the installer creates `hf-token-secret`; otherwise the
workers download anonymously, although a token is recommended to avoid anonymous
rate limits. Init containers serialize a single low-concurrency model download
into the persistent `huggingface-cache` PVC, then both GPU workers load that same
local model directory. vLLM's compiled graphs are cached there as well. This
avoids duplicate downloads, cache-lock races, and repeated compilation after a
pod replacement.

This deployment needs both L40S GPUs. Before switching models or reapplying a
changed manifest, remove the current graph so Kubernetes can replace both GPU
workers without waiting for two additional GPUs:

```bash
kubectl delete -n dynamo-system dgd gemma-disagg
# Or: kubectl delete -n dynamo-system dgd diffgemma-disagg
```

Port-forward the Dynamo frontend:

```bash
kubectl port-forward -n dynamo-system service/gemma-disagg-frontend 8000:8000
# Or: service/diffgemma-disagg-frontend
```

Use the same explicit reasoning setting for regular vLLM and Dynamo benchmarks
so the comparison does not depend on different server defaults:

```bash
curl http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gemma-26B",
    "messages": [{"role": "user", "content": "Explain why the sky is blue."}],
    "chat_template_kwargs": {"enable_thinking": true},
    "max_tokens": 512
  }'
```

The Dynamo manifests use the native `gemma4` tool-call and reasoning parsers.
Gemma returns parsed reasoning separately when the model emits its complete
thinking delimiters. DiffusionGemma can keep block-diffusion thinking in the
normal `content` field, especially when a benchmark stops at `max_tokens`, so
compare the same response fields and token limits in both serving modes.
The Compose and Dynamo configurations both pin `max-num-seqs` to `1`,
`max-num-batched-tokens` to `8192`, and the model context length to `262144`.
DiffusionGemma also uses the same 256-token diffusion canvas in both modes.
The Dynamo workers keep hybrid KV-cache management enabled because the bundled
NIXL connector supports it; this preserves that context length on each L40S.
Role-specific persistent compile-cache directories prevent prefill and decode
from racing while saving their graphs. The worker startup probes allow the first
CUDA compilation to finish before Kubernetes begins liveness checks.
