# Benchmark summary

| Model | Concurrency | Metric | vLLM | Dynamo | Dynamo change |
| --- | ---: | --- | ---: | ---: | ---: |
| Gemma 4 | 1 | System output throughput (tokens/sec) | 103.41 | 101.11 | -2.2% |
| Gemma 4 | 1 | E2E throughput per user (tokens/sec/user) | 103.58 | 101.29 | -2.2% |
| Gemma 4 | 5 | System output throughput (tokens/sec) | 103.64 | 103.14 | -0.5% |
| Gemma 4 | 5 | E2E throughput per user (tokens/sec/user) | 34.94 | 34.22 | -2.1% |
| DiffusionGemma | 1 | System output throughput (tokens/sec) | 430.05 | 138.81 | -67.7% |
| DiffusionGemma | 1 | E2E throughput per user (tokens/sec/user) | 421.75 | 133.33 | -68.4% |
| DiffusionGemma | 5 | System output throughput (tokens/sec) | 457.65 | 153.87 | -66.4% |
| DiffusionGemma | 5 | E2E throughput per user (tokens/sec/user) | 142.55 | 47.53 | -66.7% |

AIPerf 0.11.0, 10 requests per run, streaming chat, reasoning enabled.
Every run uses synthetic-data random seed 42 for matching engine workloads.
Output throughput uses total output sequence length, including reasoning tokens.
