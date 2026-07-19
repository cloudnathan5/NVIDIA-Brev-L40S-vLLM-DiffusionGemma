ARG VLLM_DIFFGEMMA_IMAGE=vllm/vllm-openai:gemma
FROM ${VLLM_DIFFGEMMA_IMAGE}

ARG DYNAMO_PACKAGE_VERSION=1.3.0.dev1
ARG NIXL_VERSION=1.1.0

# The specialized vLLM image contains DiffusionGemma support. Add the matching
# Dynamo preview runtime without replacing its model-specific vLLM build.
RUN python3 -m pip install --no-cache-dir --pre \
      --extra-index-url https://pypi.nvidia.com/ \
      "ai-dynamo==${DYNAMO_PACKAGE_VERSION}" \
      "ai-dynamo-runtime==${DYNAMO_PACKAGE_VERSION}" \
      "nixl==${NIXL_VERSION}" \
      "nixl-cu13==${NIXL_VERSION}" \
      "ray>=2.55.0" \
      "librosa>=0.10.0" \
      "soundfile>=0.13.1" \
    && python3 -m pip uninstall -y nixl-cu12 \
    && python3 -m pip install --no-cache-dir --force-reinstall --no-deps \
      "nixl-cu13==${NIXL_VERSION}" \
    && python3 -c "import dynamo.runtime, vllm; print('vLLM', vllm.__version__)"
