#!/usr/bin/env bash
set -euo pipefail

# -------- Defaults (aanpassen als jouw interfaces/networks anders heten) --------
DEFAULT_WAN_IF="eth0"
DEFAULT_PTERO_NET="pterodactyl_nw"
DAEMON_JSON="/etc/docker/daemon.json"

# -------- Helpers --------
log()  { echo -e "\n[+] $*"; }
warn() { echo -e "\n[!] $*" >&2; }
die()  { warn "$*"; exit 1; }

need_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run als root."
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

get_mtu_from_iface() {
  local iface="$1"
  ip -o link show "$iface" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="mtu") {print $(i+1); exit}}'
}

validate_mtu() {
  local mtu="$1"
  [[ "$mtu" =~ ^[0-9]+$ ]] || return 1
  # praktische range; pas aan als je extreem wil
  (( mtu >= 576 && mtu <= 9000 )) || return 1
  return 0
}

write_docker_daemon_json() {
  local mtu="$1"
  mkdir -p "$(dirname "$DAEMON_JSON")"
  if [[ -f "$DAEMON_JSON" ]]; then
    cp -a "$DAEMON_JSON" "${DAEMON_JSON}.bak.$(date +%Y%m%d-%H%M%S)"
    log "Backup gemaakt: ${DAEMON_JSON}.bak.*"
  fi

  cat > "$DAEMON_JSON" <<EOF
{
  "mtu": ${mtu},
  "dns": ["8.8.8.8", "1.1.1.1"]
}
EOF
  log "Docker config geschreven naar $DAEMON_JSON (mtu=${mtu})."
}

pterodactyl_fix() {
  local mtu="$1"
  local ptero_net="$2"

  log "Pterodactyl fix: Docker MTU=${mtu}, network=${ptero_net}"

  write_docker_daemon_json "$mtu"

  log "Stopping wings..."
  systemctl stop wings >/dev/null 2>&1 || true

  log "Stopping running containers..."
  docker ps -q | xargs -r docker stop

  if docker network ls --format '{{.Name}}' | grep -qx "$ptero_net"; then
    log "Removing Docker network: $ptero_net"
    docker network rm "$ptero_net" || die "Kon $ptero_net niet verwijderen (zit er nog een container op?)."
  else
    warn "Network $ptero_net bestaat niet (skip)."
  fi

  log "Restarting docker..."
  systemctl restart docker

  log "Starting wings..."
  systemctl start wings >/dev/null 2>&1 || true

  log "MTU status:"
  ip link show "$DEFAULT_WAN_IF" 2>/dev/null | grep -oE "mtu [0-9]+" || true
  ip link show docker0 2>/dev/null | grep -oE "mtu [0-9]+" || warn "docker0 nog niet aanwezig"
  ip link show pterodactyl0 2>/dev/null | grep -oE "mtu [0-9]+" || warn "pterodactyl0 verschijnt zodra je een server start"
}

host_iface_mtu_fix() {
  local iface="$1"
  local mtu="$2"

  log "Host interface MTU zetten: ${iface} -> ${mtu}"
  ip link set dev "$iface" mtu "$mtu" || die "MTU aanpassen faalde op $iface."

  log "Nieuwe MTU:"
  ip link show "$iface" | grep -oE "mtu [0-9]+"
}

show_menu() {
  cat <<'EOF'

==== MTU Fix Menu ====
1) Pterodactyl (Docker MTU + recreate pterodactyl_nw)
2) Host/VPS interface MTU aanpassen (ip link set)
3) Allebei (Host MTU + Pterodactyl)
0) Exit
EOF
}

choose_mtu() {
  local wan_if="$1"
  local detected
  detected="$(get_mtu_from_iface "$wan_if" || true)"

  echo
  echo "MTU keuze:"
  echo "1) Auto-detect van ${wan_if} (gevonden: ${detected:-'n/a'})"
  echo "2) Custom MTU zelf invullen"
  read -r -p "Kies [1-2]: " mtu_choice

  case "${mtu_choice:-}" in
    1)
      [[ -n "${detected:-}" ]] || die "Kon MTU niet detecteren op ${wan_if}."
      echo "$detected"
      ;;
    2)
      read -r -p "Vul gewenste MTU in (576-9000): " custom
      validate_mtu "$custom" || die "Ongeldige MTU: $custom"
      echo "$custom"
      ;;
    *)
      die "Ongeldige keuze."
      ;;
  esac
}

main() {
  need_root
  have_cmd docker || die "docker ontbreekt."
  have_cmd ip || die "ip (iproute2) ontbreekt."
  have_cmd systemctl || warn "systemctl ontbreekt? Dan werkt wings/docker restart mogelijk niet goed."

  read -r -p "WAN interface naam [default: ${DEFAULT_WAN_IF}]: " WAN_IF
  WAN_IF="${WAN_IF:-$DEFAULT_WAN_IF}"

  show_menu
  read -r -p "Kies actie [0-3]: " action

  case "${action:-}" in
    0) exit 0 ;;
    1)
      mtu="$(choose_mtu "$WAN_IF")"
      read -r -p "Pterodactyl docker network naam [default: ${DEFAULT_PTERO_NET}]: " PNET
      PNET="${PNET:-$DEFAULT_PTERO_NET}"
      pterodactyl_fix "$mtu" "$PNET"
      ;;
    2)
      read -r -p "Welke interface wil je aanpassen? [default: ${WAN_IF}]: " IFACE
      IFACE="${IFACE:-$WAN_IF}"
      mtu="$(choose_mtu "$IFACE")"
      host_iface_mtu_fix "$IFACE" "$mtu"
      ;;
    3)
      # eerst host MTU (optioneel), daarna pterodactyl
      read -r -p "Welke host interface wil je aanpassen? [default: ${WAN_IF}]: " IFACE
      IFACE="${IFACE:-$WAN_IF}"
      mtu="$(choose_mtu "$IFACE")"

      warn "Host MTU aanpassen kan je verbinding beïnvloeden als dit verkeerd is."
      read -r -p "Weet je zeker dat je ${IFACE} MTU=${mtu} wilt zetten? (yes/no): " confirm
      [[ "${confirm:-}" == "yes" ]] || die "Afgebroken."

      host_iface_mtu_fix "$IFACE" "$mtu"

      read -r -p "Pterodactyl docker network naam [default: ${DEFAULT_PTERO_NET}]: " PNET
      PNET="${PNET:-$DEFAULT_PTERO_NET}"
      pterodactyl_fix "$mtu" "$PNET"
      ;;
    *)
      die "Ongeldige keuze."
      ;;
  esac

  log "Klaar."
  echo "Tip: test daarna in je container:"
  echo "  docker exec -it <container> bash -lc 'curl -I --max-time 10 https://api.minecraftservices.com/publickeys'"
}

main "$@"
