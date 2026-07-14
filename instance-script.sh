#!/bin/bash
set -e

# Detect GPU count
if command -v nvidia-smi > /dev/null 2>&1; then
    _world_size="$(nvidia-smi -L | wc -l)"
else
    _world_size=1
fi

echo "Detected GPUs: ${_world_size}"

# Model settings
MODEL="nvidia/diffusiongemma-26B-A4B-it-NVFP4"

# Pull DiffusionGemma-enabled vLLM image
docker pull vllm/vllm-openai:gemma

# Run vLLM server
docker run --rm \
    --gpus all \
    --privileged \
    --ipc=host \
    -p 8000:8000 \
    -v ~/.cache/huggingface:/root/.cache/huggingface \
    -e VLLM_USE_V2_MODEL_RUNNER=1 \
    -e HF_TOKEN="${HF_TOKEN}" \
    -e VLLM_API_KEY="${VLLM_API_KEY}" \
    vllm/vllm-openai:gemma \
    "${MODEL}" \
        --trust-remote-code \
        --served-model-name diffusiongemma-26B \
        --max-num-seqs 4 \
        --attention-backend TRITON_ATTN \
        --enable-auto-tool-choice \
        --tool-call-parser gemma4 \
        --reasoning-parser gemma4 \
        --generation-config vllm \
        --hf-overrides '{"diffusion_sampler": "entropy_bound", "diffusion_entropy_bound": 0.1}' \
	    --default-chat-template-kwargs '{"enable_thinking":true}' \
        --host 0.0.0.0 \
        --port 8000 \
        --api-key "${VLLM_API_KEY}" \
        --gpu-memory-utilization 0.95 
