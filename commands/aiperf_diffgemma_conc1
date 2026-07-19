aiperf profile \
  --model "diffusiongemma-26B" \
  --tokenizer "nvidia/diffusiongemma-26B-A4B-it-NVFP4" \
  --streaming \
  --endpoint-type chat \
  --extra-inputs '{"chat_template_kwargs":{"enable_thinking":true}}' \
  --url http://localhost:8000 \
  --request-count 10 \
  --concurrency 1 --concurrency-min 1
