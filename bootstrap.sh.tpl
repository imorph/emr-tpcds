#!/bin/bash
set -euo pipefail

exec > >(tee -a /tmp/bootstrap.log)
exec 2>&1

echo "=== Bootstrap script started at $(date) ==="

# Runtime variant and URLs
RUNTIME_VARIANT="${runtime_variant}"
TAR_URL="${tar_url}"

sudo curl -L -f --connect-timeout 30 --max-time 300 -o /tmp/ap.tar.gz https://github.com/async-profiler/async-profiler/releases/download/v4.1/async-profiler-4.1-linux-arm64.tar.gz
sudo mkdir -p /opt/async-profiler
sudo mkdir -p /mnt/spark
sudo chown -R yarn:yarn /mnt/spark
sudo chmod -R 0777 /mnt/spark
sudo tar vxf /tmp/ap.tar.gz -C /opt/async-profiler --strip-components=1
sudo chmod -R 0755 /opt/async-profiler
sudo chown -R yarn:yarn /opt/async-profiler
sudo sysctl kernel.perf_event_paranoid=1
sudo sysctl kernel.kptr_restrict=0
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo defer | sudo tee /sys/kernel/mm/transparent_hugepage/defrag
echo 1 | sudo tee /sys/kernel/mm/transparent_hugepage/khugepaged/defrag

sudo mkdir -p /mnt/vmoutput
# Add any additional files you need to download here
# Example:
# sudo curl -L -f --connect-timeout 30 --max-time 300 -o /mnt/vmoutput/your-file.profile https://your-repository.com/path/to/your-file.profile
sudo chmod -R 1777 /mnt/vmoutput

sudo dnf install htop -y
echo '[ -n "$SSH_TTY" ] && export TERM=xterm' | sudo tee -a /etc/profile.d/ssh-tty.sh


if [[ "$RUNTIME_VARIANT" == "default" ]]; then
  echo "=== Using default JVM (EMR Java) ==="
  exit 0
fi

echo "=== Installing $RUNTIME_VARIANT JVM alongside EMR Java ==="
curl -L -f --connect-timeout 30 --max-time 300 -o /tmp/azul.tar.gz "$TAR_URL"
sudo mkdir -p /opt/azul-jdk
sudo tar vxf /tmp/azul.tar.gz -C /opt/azul-jdk --strip-components=1
