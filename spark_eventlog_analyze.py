#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Stream a Spark event log (JSON-lines) and compute per-SQL execution breakdown:
- makespan_ms (wall clock for the SQL: first task start -> last task end)
- task_slot_ms (sum of task wall times; "slot time")
- executor_run_ms (sum of per-task executorRunTime)
- executor_cpu_ms (sum of per-task executorCpuTime, ns -> ms)
- cpu_vs_wall_pct (executor_cpu_ms as % of wall clock makespan)
- plus a few useful sub-metrics (deserialize/result-serialize/shuffle wait/GC, bytes)

Mapping chain:
  TaskEnd(stageId) -> Stage -> JobStart(jobId) -> Properties["spark.sql.execution.id"] -> SQLExecutionStart(executionId)

Usage:
  python spark_eventlog_analyze.py -o run-1.csv /path/to/eventlog.json
  python spark_eventlog_analyze.py --output-file run-2.csv /path/to/eventlog.json.gz
  python spark_eventlog_analyze.py /path/to/eventlog.zip
"""

import argparse
import csv
import gzip
import json
import re
import statistics
import sys
import zipfile
import io
from pprint import pprint
from collections import defaultdict
from contextlib import contextmanager

# ---------- helpers ----------

def _g(d, *keys, default=None):
    """Return first present key from keys in dict d, else default."""
    for k in keys:
        if isinstance(d, dict) and k in d:
            return d[k]
    return default

def _norm_properties(props):
    """
    Normalize JobStart.Properties into a dict.
    It can be a dict already, or an array of {"key": "...", "value": "..."}.
    """
    if not props:
        return {}
    if isinstance(props, dict):
        out = {}
        for k, v in props.items():
            if isinstance(v, dict) and "value" in v and len(v) == 1:
                out[k] = v["value"]
            else:
                out[k] = v
        return out
    if isinstance(props, list):
        out = {}
        for p in props:
            if not isinstance(p, dict):
                continue
            k = p.get("key")
            v = p.get("value")
            if k is not None:
                out[k] = v
        return out
    return {}

@contextmanager
def _open_maybe_gz_or_zip(path):
    if path.endswith(".gz"):
        with gzip.open(path, "rt", encoding="utf-8", errors="replace") as f:
            yield f
    elif path.endswith(".zip"):
        with zipfile.ZipFile(path, 'r') as z:
            names = z.namelist()
            with z.open(names[0]) as fb:
                with io.TextIOWrapper(fb, encoding="utf-8") as f:
                    yield f
    else:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            yield f

def _ms_from_ns(ns_val):
    try:
        return float(ns_val) / 1e6
    except Exception:
        return 0.0

def _as_int(x, default=0):
    try:
        return int(x)
    except Exception:
        return default

def _success_from_task_end(ev):
    """
    Try to determine if the task ended successfully. We try a few shapes:
      ev["Task End Reason"] may be a string "Success" or an object with Reason=Success.
    If we can't tell, we default to True to avoid dropping data.
    """
    r = _g(ev, "Task End Reason", "taskEndReason", default=None)
    if r is None:
        return True
    if isinstance(r, str):
        return r.lower() == "success"
    if isinstance(r, dict):
        reason = _g(r, "Reason", "reason", default=None)
        if isinstance(reason, str):
            return reason.lower() == "success"
    rs = str(r)
    return ("Success" in rs) or ("org.apache.spark.Success" in rs)

def analyze_sql_breakdown(paths):
    """
    Parse one or more event log files (JSON lines) and return a list of dicts with per-execution stats.
    """

    # Maps we build while streaming
    exec_info = {}                 # executionId -> {description, details, startTime, endTime}
    exec_jobs = defaultdict(set)   # executionId -> set(jobIds)
    job_exec = {}                  # jobId -> executionId
    stage_job = {}                 # stageId -> jobId
    tasks_by_key = {}              # (stageId, taskId) -> task record (prefer success)

    # Streaming parse
    for path in paths:
        with _open_maybe_gz_or_zip(path) as f:
            for line in f:
                if not line.strip():
                    continue
                try:
                    ev = json.loads(line)
                except Exception:
                    continue

                et = _g(ev, "Event", "event")
                if not et:
                    continue

                # --- SQL start/end/info ---
                if et in ("org.apache.spark.sql.execution.ui.SparkListenerSQLExecutionStart",
                          "SparkListenerSQLExecutionStart"):
                    exid = _as_int(_g(ev, "executionId", "Execution ID", default=None), default=None)
                    if exid is None:
                        continue
                    exec_info.setdefault(exid, {})
                    exec_info[exid]["description"] = (_g(ev, "description", "Description", default="") or "").strip()
                    exec_info[exid]["details"] = _g(ev, "details", "Details", default="")
                    st = _g(ev, "time", "Time", "startTime", "Start Time", default=None)
                    if st is not None:
                        exec_info[exid]["startTime"] = _as_int(st, default=None)

                elif et in ("org.apache.spark.sql.execution.ui.SparkListenerSQLExecutionEnd",
                            "SparkListenerSQLExecutionEnd"):
                    exid = _as_int(_g(ev, "executionId", "Execution ID", default=None), default=None)
                    if exid is not None:
                        ex = exec_info.setdefault(exid, {})
                        en = _g(ev, "time", "Time", "endTime", "End Time", default=None)
                        if en is not None:
                            ex["endTime"] = _as_int(en, default=None)

                # --- JobStart: tie job -> executionId and stageIds -> jobId ---
                elif et == "SparkListenerJobStart":
                    jobId = _as_int(_g(ev, "Job ID", "jobId", default=None), default=None)
                    if jobId is None:
                        continue

                    stage_ids = _g(ev, "Stage IDs", "stageIds", default=None)
                    if stage_ids is None:
                        infos = _g(ev, "Stage Infos", "stageInfos", default=[]) or []
                        stage_ids = [_as_int(_g(si, "Stage ID", "stageId"), default=None) for si in infos]
                        stage_ids = [sid for sid in stage_ids if sid is not None]
                    else:
                        stage_ids = [_as_int(s, default=None) for s in stage_ids if s is not None]

                    props = _norm_properties(_g(ev, "Properties", "properties", default={}))
                    exid_str = props.get("spark.sql.execution.id")
                    if exid_str is not None:
                        try:
                            exid = int(exid_str)
                            job_exec[jobId] = exid
                            exec_jobs[exid].add(jobId)
                        except Exception:
                            pass

                    for sid in stage_ids:
                        if sid is not None:
                            stage_job[sid] = jobId

                # --- TaskEnd: collect per-task metrics (we'll attribute to exec later) ---
                elif et == "SparkListenerTaskEnd":
                    stageId = _as_int(_g(ev, "Stage ID", "stageId", default=None), default=None)
                    if stageId is None:
                        continue

                    taskInfo = _g(ev, "Task Info", "taskInfo", "TaskInfo", default={}) or {}
                    metrics = _g(ev, "Task Metrics", "taskMetrics", "TaskMetrics", default={}) or {}

                    task_id = _as_int(_g(taskInfo, "Task ID", "taskId", "TaskId", default=None), default=None)
                    key = (stageId, task_id)

                    launch = _g(taskInfo, "Launch Time", "launchTime")
                    finish = _g(taskInfo, "Finish Time", "finishTime")
                    launch_i = _as_int(launch, default=None) if launch is not None else None
                    finish_i = _as_int(finish, default=None) if finish is not None else None
                    if launch_i is not None and finish_i is not None:
                        duration_ms = max(0, finish_i - launch_i)
                    else:
                        duration_ms = _as_int(_g(metrics, "Executor Run Time", "executorRunTime", default=0), default=0)

                    run_ms = _as_int(_g(metrics, "Executor Run Time", "executorRunTime", default=0), default=0)
                    cpu_ns = _as_int(_g(metrics, "Executor CPU Time", "executorCpuTime", default=0), default=0)
                    cpu_ms = cpu_ns / 1e6

                    deser_ms = _as_int(_g(metrics, "Executor Deserialize Time",
                                          "executorDeserializeTime", default=0), default=0)
                    result_ser_ms = _as_int(_g(metrics, "Result Serialization Time",
                                               "resultSerializationTime", default=0), default=0)
                    gc_ms = _as_int(_g(metrics, "JVM GC Time", "JvmGcTime", "jvmGcTime", default=0), default=0)

                    shuffle_read = _g(metrics, "Shuffle Read Metrics", "shuffleReadMetrics", default={}) or {}
                    shuffle_write = _g(metrics, "Shuffle Write Metrics", "shuffleWriteMetrics", default={}) or {}
                    input_metrics = _g(metrics, "Input Metrics", "inputMetrics", default={}) or {}
                    output_metrics = _g(metrics, "Output Metrics", "outputMetrics", default={}) or {}

                    shuffle_fetch_wait_ms = _as_int(_g(shuffle_read, "Fetch Wait Time",
                                                       "fetchWaitTime", default=0), default=0)
                    shuffle_read_bytes = _as_int(_g(shuffle_read, "Remote Bytes Read",
                                                    "remoteBytesRead", default=0), default=0)
                    shuffle_read_bytes += _as_int(_g(shuffle_read, "Local Bytes Read",
                                                     "localBytesRead", default=0), default=0)

                    shuffle_write_time_ms = _ms_from_ns(_g(shuffle_write, "Write Time",
                                                           "writeTime", default=0))
                    shuffle_write_bytes = _as_int(_g(shuffle_write, "Bytes Written",
                                                     "bytesWritten", default=0), default=0)

                    input_bytes = _as_int(_g(input_metrics, "Bytes Read", "bytesRead", default=0), default=0)
                    output_bytes = _as_int(_g(output_metrics, "Bytes Written", "bytesWritten", default=0), default=0)

                    success = _success_from_task_end(ev)

                    t_rec = {
                        "stageId": stageId,
                        "taskId": task_id,
                        "launch": launch_i,
                        "finish": finish_i,
                        "duration_ms": duration_ms,
                        "run_ms": run_ms,
                        "cpu_ms": cpu_ms,
                        "deserialize_ms": deser_ms,
                        "result_serialize_ms": result_ser_ms,
                        "gc_ms": gc_ms,
                        "shuffle_fetch_wait_ms": shuffle_fetch_wait_ms,
                        "shuffle_write_time_ms": shuffle_write_time_ms,
                        "shuffle_read_bytes": shuffle_read_bytes,
                        "shuffle_write_bytes": shuffle_write_bytes,
                        "input_bytes": input_bytes,
                        "output_bytes": output_bytes,
                        "success": success,
                    }

                    prev = tasks_by_key.get(key)
                    if prev is None or (not prev.get("success") and success):
                        tasks_by_key[key] = t_rec

    # Attribute deduped tasks -> (stage -> job -> execution)
    tasks = list(tasks_by_key.values())
    tasks_by_exec = defaultdict(list)

    for t in tasks:
        jobId = stage_job.get(t["stageId"])
        if jobId is None:
            continue
        exid = job_exec.get(jobId)
        if exid is None:
            continue
        tasks_by_exec[exid].append(t)

    # Aggregate per execution
    results = []
    for exid, ts in tasks_by_exec.items():
        if not ts:
            continue

        wall_start = min((t["launch"] for t in ts if t["launch"] is not None), default=None)
        wall_end   = max((t["finish"] for t in ts if t["finish"] is not None), default=None)
        makespan_ms = (wall_end - wall_start) if (wall_start is not None and wall_end is not None) else None

        task_slot_ms = sum(t["duration_ms"] for t in ts)
        run_ms       = sum(t["run_ms"] for t in ts)
        cpu_ms       = sum(t["cpu_ms"] for t in ts)
        deser_ms     = sum(t["deserialize_ms"] for t in ts)
        result_ser   = sum(t["result_serialize_ms"] for t in ts)
        gc_ms        = sum(t["gc_ms"] for t in ts)
        fetch_wait   = sum(t["shuffle_fetch_wait_ms"] for t in ts)
        shw_time_ms  = sum(t["shuffle_write_time_ms"] for t in ts)

        in_bytes     = sum(t["input_bytes"] for t in ts)
        out_bytes    = sum(t["output_bytes"] for t in ts)
        sh_r_bytes   = sum(t["shuffle_read_bytes"] for t in ts)
        sh_w_bytes   = sum(t["shuffle_write_bytes"] for t in ts)

        # NEW: CPU vs Wall %
        if run_ms and run_ms > 0:
            cpu_vs_wall_pct = (cpu_ms / float(run_ms)) * 100.0
        else:
            cpu_vs_wall_pct = None

        info = exec_info.get(exid, {})
        desc = (info.get("description") or "").strip()
        results.append({
            "executionId": exid,
            "description": desc,
            "num_jobs": len(exec_jobs.get(exid, [])),
            "num_tasks": len(ts),
            "makespan_ms": makespan_ms,
            "task_slot_ms": task_slot_ms,
            "executor_run_ms": run_ms,
            "executor_cpu_ms": cpu_ms,
            "cpu_vs_wall_pct": cpu_vs_wall_pct,  # <-- new column
            "deserialize_ms": deser_ms,
            "result_serialize_ms": result_ser,
            "gc_ms": gc_ms,
            "shuffle_fetch_wait_ms": fetch_wait,
            "shuffle_write_time_ms": shw_time_ms,
            "input_bytes": in_bytes,
            "output_bytes": out_bytes,
            "shuffle_read_bytes": sh_r_bytes,
            "shuffle_write_bytes": sh_w_bytes,
        })

    results.sort(key=lambda r: r.get("executionId") or -1)
    return results

def write_csv(f, rows):
    fieldnames = [
        "executionId",
        "description",
        "num_jobs",
        "num_tasks",
        "makespan_ms",
        "task_slot_ms",
        "executor_run_ms",
        "executor_cpu_ms",
        "cpu_vs_wall_pct",
        "deserialize_ms",
        "result_serialize_ms",
        "gc_ms",
        "shuffle_fetch_wait_ms",
        "shuffle_write_time_ms",
        "input_bytes",
        "output_bytes",
        "shuffle_read_bytes",
        "shuffle_write_bytes",
    ]
    w = csv.DictWriter(f, fieldnames=fieldnames, quoting=csv.QUOTE_NONNUMERIC)
    w.writeheader()
    for row in rows:
        w.writerow(row)


def main():
    ap = argparse.ArgumentParser(description="Compute per-SQL breakdown from Spark event log(s).")
    ap.add_argument("eventlogs", nargs="+", help="Path(s) to Spark event log JSON (optionally .gz or .zip).")
    ap.add_argument("-o", "--output-file", help="Path where to write CSV output (stdout by default).")
    args = ap.parse_args()

    rows = analyze_sql_breakdown(args.eventlogs)
    if not rows:
        print("No SQL executions found (or no mappable tasks). "
              "Make sure the log contains SQL events and JobStart with spark.sql.execution.id.", file=sys.stderr)
        return 2

    if args.output_file:
        with open(args.output_file, "w", newline="", encoding="utf-8") as f:
            write_csv(f, rows)
    else:
        write_csv(sys.stdout, rows)

if __name__ == "__main__":
    sys.exit(main())
