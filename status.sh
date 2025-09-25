#!/usr/bin/env bash

# Check for CURRENT_SPARK_CLUSTER_ID BEFORE enabling strict mode
if [[ -z "${CURRENT_SPARK_CLUSTER_ID:-}" ]]; then
    echo "ERROR: CURRENT_SPARK_CLUSTER_ID environment variable is not set!" >&2
    echo "Please ensure you have run the 'run_test.sh' script properly first." >&2
    echo "This variable should contain your EMR cluster ID." >&2
    exit 1
fi

# Now enable strict mode after variable validation
set -euo pipefail

echo "Listing steps for EMR cluster: ${CURRENT_SPARK_CLUSTER_ID}"
echo "=================================================="

# Enhanced EMR list-steps command with truncated timestamps (removes microseconds)
aws emr list-steps \
    --cluster-id "${CURRENT_SPARK_CLUSTER_ID}" \
    --query 'Steps[].{StepName:Name,State:Status.State,Created:Status.Timeline.CreationDateTime,Started:Status.Timeline.StartDateTime,Ended:Status.Timeline.EndDateTime}' \
    --output table \
    --no-paginate

aws emr list-steps \
    --cluster-id "${CURRENT_SPARK_CLUSTER_ID}" \
    --no-paginate \
    --output json | jq -r '
def normalize_timestamp(ts):
    if ts == null then null
    else
        # Remove microseconds and convert timezone offset to UTC
        ts | sub("\\.[0-9]+"; "") | sub("([+-][0-9]{2}):([0-9]{2})$"; "Z")
    end;

def parse_timestamp(ts):
    if ts == null then null
    else
        normalize_timestamp(ts) | fromdateiso8601
    end;

def format_duration(seconds):
    if seconds == null then "N/A"
    else
        (seconds / 60 | floor) as $minutes |
        (seconds % 60 | floor) as $secs |
        "\($minutes)m \($secs)s"
    end;

def calculate_duration_alt(start_ts; end_ts):
    if start_ts == null or end_ts == null then null
    else
        # Extract components manually for calculation
        (start_ts | sub("\\.[0-9]+"; "") | sub("T"; " ") | sub("([+-][0-9]{2}):([0-9]{2})$"; "")) as $start_clean |
        (end_ts | sub("\\.[0-9]+"; "") | sub("T"; " ") | sub("([+-][0-9]{2}):([0-9]{2})$"; "")) as $end_clean |
        # Simple duration calculation (this is approximate for same timezone)
        ($end_clean | strptime("%Y-%m-%d %H:%M:%S") | mktime) - ($start_clean | strptime("%Y-%m-%d %H:%M:%S") | mktime)
    end;

["StepName", "State", "Started", "Ended", "Duration"],
(.Steps[] | 
    calculate_duration_alt(.Status.Timeline.StartDateTime; .Status.Timeline.EndDateTime) as $duration |
    [
        .Name,
        .Status.State,
        .Status.Timeline.StartDateTime,
        .Status.Timeline.EndDateTime,
        format_duration($duration)
    ]
) | @tsv
' | column -t -s $'\t' 2>/dev/null || true