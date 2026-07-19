#!/usr/bin/env python3
import csv
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


SCRIPT_DIR = Path(__file__).resolve().parent
ARTIFACT_ROOT = SCRIPT_DIR / "artifacts"
GRAPH_DIR = ARTIFACT_ROOT / "graphs"

RUNS = [
    ("Gemma 4", "vLLM", 1, "vllm/gemma/conc1"),
    ("Gemma 4", "vLLM", 5, "vllm/gemma/conc5"),
    ("Gemma 4", "Dynamo", 1, "dynamo/gemma/conc1"),
    ("Gemma 4", "Dynamo", 5, "dynamo/gemma/conc5"),
    ("DiffusionGemma", "vLLM", 1, "vllm/diffgemma/conc1"),
    ("DiffusionGemma", "vLLM", 5, "vllm/diffgemma/conc5"),
    ("DiffusionGemma", "Dynamo", 1, "dynamo/diffgemma/conc1"),
    ("DiffusionGemma", "Dynamo", 5, "dynamo/diffgemma/conc5"),
]

METRICS = {
    "output_token_throughput": "System output throughput\n(tokens/sec)",
    "e2e_output_token_throughput": "E2E throughput per user\n(tokens/sec/user)",
}


def load_runs():
    rows = []
    for model, engine, concurrency, relative_dir in RUNS:
        result_path = ARTIFACT_ROOT / relative_dir / "profile_export_aiperf.json"
        if not result_path.exists():
            raise FileNotFoundError(f"Missing benchmark result: {result_path}")

        with result_path.open(encoding="utf-8") as result_file:
            result = json.load(result_file)

        request_count = int(result["request_count"]["avg"])
        if request_count != 10:
            raise ValueError(f"Expected 10 requests in {result_path}, found {request_count}")

        rows.append(
            {
                "model": model,
                "engine": engine,
                "concurrency": concurrency,
                "request_count": request_count,
                "output_token_throughput": result["output_token_throughput"]["avg"],
                "e2e_output_token_throughput": result[
                    "e2e_output_token_throughput"
                ]["avg"],
                "output_token_throughput_per_user": result[
                    "output_token_throughput_per_user"
                ]["avg"],
                "time_to_first_token_ms": result["time_to_first_token"]["avg"],
                "request_latency_ms": result["request_latency"]["avg"],
                "aiperf_version": result["aiperf_version"],
            }
        )
    return rows


def write_summary_csv(rows):
    output_path = ARTIFACT_ROOT / "benchmark-summary.csv"
    fieldnames = list(rows[0].keys())
    with output_path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def lookup(rows, model, engine, concurrency, metric):
    return next(
        row[metric]
        for row in rows
        if row["model"] == model
        and row["engine"] == engine
        and row["concurrency"] == concurrency
    )


def write_summary_markdown(rows):
    lines = [
        "# Benchmark summary",
        "",
        "| Model | Concurrency | Metric | vLLM | Dynamo | Dynamo change |",
        "| --- | ---: | --- | ---: | ---: | ---: |",
    ]
    for model in ("Gemma 4", "DiffusionGemma"):
        for concurrency in (1, 5):
            for metric, label in METRICS.items():
                vllm = lookup(rows, model, "vLLM", concurrency, metric)
                dynamo = lookup(rows, model, "Dynamo", concurrency, metric)
                change = ((dynamo / vllm) - 1.0) * 100.0
                short_label = label.replace("\n", " ")
                lines.append(
                    f"| {model} | {concurrency} | {short_label} | "
                    f"{vllm:.2f} | {dynamo:.2f} | {change:+.1f}% |"
                )

    lines.extend(
        [
            "",
            "AIPerf 0.11.0, 10 requests per run, streaming chat, reasoning enabled.",
            "Output throughput uses total output sequence length, including reasoning tokens.",
        ]
    )
    (ARTIFACT_ROOT / "benchmark-summary.md").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )


def add_value_labels(axis, bars):
    axis.bar_label(bars, fmt="%.1f", padding=3, fontsize=9)


def plot_comparison(rows):
    colors = {"vLLM": "#35618C", "Dynamo": "#D45745"}
    models = ("Gemma 4", "DiffusionGemma")
    concurrencies = (1, 5)
    x_positions = np.arange(len(concurrencies))
    width = 0.34

    plt.rcParams.update(
        {
            "font.family": "DejaVu Sans",
            "font.size": 11,
            "axes.titleweight": "bold",
            "axes.edgecolor": "#333333",
            "axes.grid": True,
            "grid.color": "#D9D9D9",
            "grid.linewidth": 0.8,
            "grid.alpha": 0.8,
        }
    )
    figure, axes = plt.subplots(2, 2, figsize=(14, 9), constrained_layout=True)

    for row_index, model in enumerate(models):
        for column_index, (metric, metric_label) in enumerate(METRICS.items()):
            axis = axes[row_index][column_index]
            for engine_index, engine in enumerate(("vLLM", "Dynamo")):
                values = [
                    lookup(rows, model, engine, concurrency, metric)
                    for concurrency in concurrencies
                ]
                offset = (-0.5 if engine_index == 0 else 0.5) * width
                bars = axis.bar(
                    x_positions + offset,
                    values,
                    width,
                    label=engine,
                    color=colors[engine],
                    edgecolor="white",
                )
                add_value_labels(axis, bars)

            axis.set_title(f"{model}: {metric_label}")
            axis.set_xticks(x_positions, ["Concurrency 1", "Concurrency 5"])
            axis.set_ylabel("Tokens/sec" if column_index == 0 else "Tokens/sec/user")
            axis.grid(axis="y")
            axis.grid(axis="x", visible=False)
            axis.spines["top"].set_visible(False)
            axis.spines["right"].set_visible(False)
            axis.legend(frameon=False, loc="upper left")
            axis.margins(y=0.18)

    figure.suptitle(
        "Regular vLLM vs Dynamo Disaggregated Serving",
        fontsize=18,
        fontweight="bold",
    )
    figure.savefig(GRAPH_DIR / "throughput-comparison.png", dpi=180)
    figure.savefig(GRAPH_DIR / "throughput-comparison.svg")
    plt.close(figure)


def main():
    GRAPH_DIR.mkdir(parents=True, exist_ok=True)
    rows = load_runs()
    write_summary_csv(rows)
    write_summary_markdown(rows)
    plot_comparison(rows)
    print(f"Wrote benchmark summary and graphs to {ARTIFACT_ROOT}")


if __name__ == "__main__":
    main()
