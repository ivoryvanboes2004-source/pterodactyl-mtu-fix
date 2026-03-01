#!/usr/bin/env bash
set -euo pipefail

WAN_IF="eth0"
PTERO_NET="pterodactyl_nw"
DAEMON_JSON="/etc/docker/daemon.json"

echo "[+] Detecting MTU on ${WAN_IF}..."
MTU=$(ip -o link show "$WAN_IF" | awk '{for(i=1;i<=NF;i++) if($i=="mtu") {print $(i+1); exit}}')

if [ -z "$MTU" ]; then
  echo "[!] Could not detect MTU on ${WAN_IF}"
  exit 1
fi

echo "[+] Detected MTU: $MTU"

echo "[+] Backing up existing Docker config (if exists)..."
if [ -f "$DAEMON_JSON" ]; then
  cp -a "$DAEMON_JSON" "${DAEMON_JSON}.bak.$(date +%Y%m%d-%H%M%S)"
fi

echo "[+] Writing new Docker MTU config..."
cat > "$DAEMON_JSON" <<EOF
{
  "mtu": ${MTU},
  "dns": ["8.8.8.8", "1.1.1.1"]
}
EOF

echo "[+] Stopping wings..."
systemctl stop wings || true

echo "[+] Stopping running containers..."
docker ps -q | xargs -r docker stop

if docker network ls --format '{{.Name}}' | grep -qx "$PTERO_NET"; then
  echo "[+] Removing network ${PTERO_NET}..."
  docker network rm "$PTERO_NET"
fi

echo "[+] Restarting Docker..."
systemctl restart docker

echo "[+] Starting wings..."
systemctl start wings || true

echo "[+] Current MTU status:"
ip link show "$WAN_IF" | grep mtu
ip link show docker0 2>/dev/null | grep mtu || true
ip link show pterodactyl0 2>/dev/null | grep mtu || true

echo "[+] Done."
