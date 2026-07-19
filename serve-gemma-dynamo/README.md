# Gemma Dynamo runtime

`gemma-disagg.yaml` uses NVIDIA's published
`nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.2.1` image directly. No local build is
required. The Dockerfile records that runtime alongside the custom
DiffusionGemma runtime and provides a starting point for optional customization.
