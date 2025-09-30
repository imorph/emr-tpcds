#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Compare two sets of CSV files with analyzed Spark Event logs, and get
comparison of TPC-DS results in those runs.

Usage:
  python tpcds_eventlog_compare.py corretto-*.csv zing-*.csv
  python tpcds_eventlog_compare.py -o first_run_only corretto-1.csv zing-1.csv
  python tpcds_eventlog_compare.py --longer-than 60 corretto-*.csv zing-*.cs
"""

import sys
import argparse
import polars as pl
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from pathlib import Path
from matplotlib.ticker import PercentFormatter

def read_spark_log_csv(config, run, path):
    # read csv from spark_eventlog_analyzer.py
    df = pl.read_csv(path)
    # find the Spark queries that correspond to TPC-DS queries
    # and add query column to identify them and extract only the columns we care about
    df = df.filter(pl.col('description').str.contains(r'benchmark q.*')).select(
        pl.col('description').str.strip_prefix("benchmark ").str.strip_suffix("-v2.4").alias('query'),
        pl.col('executionId'),
        pl.col('makespan_ms').alias('total_time'),
        pl.col('executor_run_ms').alias('executor_time'),
        pl.col('executor_cpu_ms').alias('executor_cpu_time'),
    )
    # enhance with config and run columns
    df = df.select(pl.lit(config).alias('config'), pl.lit(run).alias('run'), pl.all())
    return df

def split_filename(path):
    # we split name like "corretto-1.csv" to config="corretto", run=1
    config, run = path.stem.rsplit("-", 1)
    return config, int(run)

def plot_scurve(df, metric, baseline, target, output_dir):
    df = df.select(
        pl.col("query"),
        # calculate ratio as 100 * ((baseline - target) - 1)
        (100 * ((pl.col(f"{metric}_{baseline}") / pl.col(f"{metric}_{target}")) - 1)).alias("ratio"),
    )

    # sort by ratio
    df = df.sort("ratio")

    colors = df["ratio"].map_elements(lambda ratio: "green" if ratio >= 0 else "red")

    fig, ax = plt.subplots(figsize=(18, 9))

    ax.bar(df["query"], df["ratio"], color=colors)
    ax.axhline(0, color="black", linewidth=0.8)
    ax.set_xlabel("Query")
    ax.set_ylabel(f"Relative speedup ({baseline} / {target} - 1)")
    fig.suptitle(f"{metric} ({target} vs {baseline} baseline)")
    ax.set_title(f"mean {df["ratio"].mean():.2f} %, median {df["ratio"].median():.2f} %")
    ax.tick_params(axis='x', rotation=90)
    ax.yaxis.set_major_formatter(PercentFormatter())
    ax.grid(axis="y", alpha=0.5)
    fig.tight_layout()

    # save to file
    fig.savefig(output_dir / f"{target}-vs-{baseline}-{metric}.png")

def main():
    ap = argparse.ArgumentParser(description="Compare TPC-DS results in analyzed Spark event log CSVs ")
    ap.add_argument("csv_files", nargs="+", type=Path, help="Path(s) to analyzed Spark event log CSVs in form /path/to/{config}-{run}.csv, e.g. corretto-1.csv")
    ap.add_argument("-o", "--output-dir", type=Path, default=Path.cwd(), help="Path where to write the resulting artifacts output (current directory by default).")
    ap.add_argument("--longer-than", type=float, default=0.0, help="Consider only queries where target runs at least this number of seconds")
    args = ap.parse_args()

    paths = args.csv_files

    # select baseline based on first file name
    baseline = split_filename(paths[0])[0]

    # figure out the target to compare to (the other config)
    configs = set(split_filename(p)[0] for p in paths)
    if len(configs) != 2:
        raise ValueError(f"Expected two configurations, found {configs}")
    target = (configs - {baseline}).pop()

    data_cols = ('total_time', 'executor_time', 'executor_cpu_time')

    # load all data into one data frame (columns: config, run, executionId, query, total_time, etc.)
    df = pl.concat(read_spark_log_csv(config, run, path) for config, run, path in ((*split_filename(p), p) for p in paths))

    # aggregate over iterations intra-run by taking the last iteration (maximum executionId)
    df = df.filter(pl.col("executionId") == pl.col("executionId").max().over("config", "run", "query"))

    # aggregate over runs by taking mean
    df = df.group_by(["config", "query"]).agg([pl.col(col).mean() for col in data_cols])

    # pivot, and create config specific columns, e.g. total_time-corretto
    df = df.pivot(on="config", index="query")

    # apply user specified "target longer than" query filter
    df = df.filter(pl.col(f"total_time_{target}") > args.longer_than * 1000)

    # save dataframe as CSV
    args.output_dir.mkdir(exist_ok=True)
    df.write_csv(args.output_dir / f"{target}-vs-{baseline}.csv", quote_style='non_numeric')

    # plot S-curve and save to file
    plot_scurve(df, 'total_time', baseline, target, args.output_dir)

if __name__ == "__main__":
    sys.exit(main())
