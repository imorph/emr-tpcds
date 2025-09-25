#!/usr/bin/env bash
# emr-host-stats.sh  — compact, comparable per-host summary
# Usage:
#   ./emr-host-stats.sh <cluster-id>
#   # or:
#   CURRENT_SPARK_CLUSTER_ID=j-XXXXXXXX ./emr-host-stats.sh
#
# Optional env:
#   SSH_USER=ec2-user
#   SSH_KEY=~/.ssh/your-key.pem
#   PARALLEL=1            # enable concurrent SSH
#   JOBS=8                # max concurrent connections when PARALLEL=1

set -euo pipefail

CLUSTER_ID="${1:-${CURRENT_SPARK_CLUSTER_ID:-}}"
if [[ -z "${CLUSTER_ID}" ]]; then
  echo "Usage: $0 <cluster-id>   (or set CURRENT_SPARK_CLUSTER_ID)" >&2
  exit 1
fi

SSH_USER="${SSH_USER:-ec2-user}"
SSH_KEY="${SSH_KEY:-}"
PARALLEL="${PARALLEL:-1}"
JOBS="${JOBS:-10}"

ssh_opts=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout=5
  -o BatchMode=yes
)
[[ -n "$SSH_KEY" ]] && ssh_opts+=(-i "$SSH_KEY")

# Collect private IPs of all instances in the cluster
mapfile -t IPS < <(
  aws emr list-instances \
    --cluster-id "$CLUSTER_ID" \
    --query 'Instances[].PrivateIpAddress' \
    --output text | tr '\t' '\n' | sed '/^$/d'
)

if ((${#IPS[@]}==0)); then
  echo "No instances found for cluster: $CLUSTER_ID" >&2
  exit 1
fi

# Print header
printf "%-15s %5s %7s %7s %3s %3s %3s %3s %3s %3s\n" \
  "ip" "mnt%" "mem" "free" "r" "us" "sy" "id" "wa" "st"

run_checks() {
  local ip="$1"
  local out
  # Run a tiny script remotely that returns: mnt% mem_used r us sy id wa st
  out=$(
    ssh "${ssh_opts[@]}" -l "$SSH_USER" "$ip" 'bash -s' <<'REMOTE'
set -euo pipefail
mnt_use=$(df -hP /mnt 2>/dev/null | awk 'NR==2{print $5}')
if [[ -z "${mnt_use:-}" ]]; then
  mnt_use=$(df -hP / | awk 'NR==2{print $5}')
fi
mem_used=$(free -h | awk '/^Mem:/ {print $3}')
mem_free=$(free -h | awk '/^Mem:/ {print $7}')
if command -v vmstat >/dev/null 2>&1; then
  # Use the final sample line; print r and cpu columns us sy id wa st
  read r us sy id wa st < <(vmstat 1 3 | awk 'END{print $1,$13,$14,$15,$16,$17}')
else
  r="?"; us="?"; sy="?"; id="?"; wa="?"; st="?"
fi
printf "%s %s %s %s %s %s %s %s %s\n" "$mnt_use" "$mem_used" "$mem_free" "$r" "$us" "$sy" "$id" "$wa" "$st"
REMOTE
  ) || out="?? ?? ?? ?? ?? ?? ?? ?? ??"

  # One compact, aligned line per host
  # Fields: ip mnt% mem r us sy id wa st
  printf "%-15s %5s %7s %7s %3s %3s %3s %3s %3s %3s\n" "$ip" $out
}

if [[ "$PARALLEL" == "1" ]]; then
  i=0
  for ip in "${IPS[@]}"; do
    run_checks "$ip" &
    (( (++i % JOBS) == 0 )) && wait
  done
  wait
else
  for ip in "${IPS[@]}"; do
    run_checks "$ip"
  done
fi