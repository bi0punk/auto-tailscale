#!/usr/bin/env bash
set -Eeuo pipefail

# install_tailscale_server.sh
# Instala y configura Tailscale en Linux, mostrando cada paso.
# Uso:
#   sudo bash install_tailscale_server.sh
#   sudo TS_AUTHKEY=tskey-xxxxx bash install_tailscale_server.sh
#   sudo bash install_tailscale_server.sh --ssh --accept-routes
#
# Variables opcionales:
#   TS_AUTHKEY        Auth key de Tailscale para alta automática
#   TS_HOSTNAME       Nombre deseado del nodo en Tailscale
#   TS_LOGIN_SERVER   Control server (por defecto, Tailscale SaaS)
#
# Flags:
#   --ssh             Habilita Tailscale SSH
#   --accept-routes   Acepta rutas anunciadas por otros nodos
#   --reset           Fuerza reconexión limpia con tailscale up --reset

SCRIPT_NAME="$(basename "$0")"
LOG_FILE="/tmp/tailscale_setup_$(date +%Y%m%d_%H%M%S).log"
ENABLE_SSH="false"
ACCEPT_ROUTES="false"
FORCE_RESET="false"
TS_AUTHKEY="${TS_AUTHKEY:-}"
TS_HOSTNAME="${TS_HOSTNAME:-$(hostname -s 2>/dev/null || hostname)}"
TS_LOGIN_SERVER="${TS_LOGIN_SERVER:-}"
TAILSCALE_BIN="/usr/bin/tailscale"
TAILSCALED_SERVICE="tailscaled"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
  echo -e "${BLUE}[$(date '+%F %T')]${NC} $*" | tee -a "$LOG_FILE"
}

ok() {
  echo -e "${GREEN}[$(date '+%F %T')] OK:${NC} $*" | tee -a "$LOG_FILE"
}

warn() {
  echo -e "${YELLOW}[$(date '+%F %T')] WARN:${NC} $*" | tee -a "$LOG_FILE"
}

fail() {
  echo -e "${RED}[$(date '+%F %T')] ERROR:${NC} $*" | tee -a "$LOG_FILE" >&2
  exit 1
}

cleanup_on_error() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo -e "${RED}Falló ${SCRIPT_NAME} (exit=${exit_code}). Revisa el log:${NC} $LOG_FILE" >&2
  fi
}
trap cleanup_on_error EXIT

usage() {
  cat <<USAGE
Uso:
  sudo bash ${SCRIPT_NAME} [--ssh] [--accept-routes] [--reset]

Ejemplos:
  sudo bash ${SCRIPT_NAME}
  sudo TS_AUTHKEY=tskey-xxxxx bash ${SCRIPT_NAME}
  sudo TS_HOSTNAME=server-atacama bash ${SCRIPT_NAME} --ssh --accept-routes

Variables opcionales:
  TS_AUTHKEY        Auth key para alta automática sin navegador
  TS_HOSTNAME       Hostname visible en Tailscale
  TS_LOGIN_SERVER   URL de control server personalizado (ej. Headscale)
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ssh)
        ENABLE_SSH="true"
        shift
        ;;
      --accept-routes)
        ACCEPT_ROUTES="true"
        shift
        ;;
      --reset)
        FORCE_RESET="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Argumento no reconocido: $1"
        ;;
    esac
  done
}

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    fail "Debes ejecutar este script como root o con sudo."
  fi
}

check_os() {
  log "Verificando sistema operativo..."
  if [[ ! -f /etc/os-release ]]; then
    fail "No existe /etc/os-release. No puedo identificar la distro Linux."
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  ok "Sistema detectado: ${PRETTY_NAME:-Linux}"
}

check_requirements() {
  log "Validando dependencias básicas..."
  command -v systemctl >/dev/null 2>&1 || fail "systemctl no está disponible."
  command -v curl >/dev/null 2>&1 || fail "curl no está instalado. Instálalo e intenta nuevamente."

  if [[ ! -e /dev/net/tun ]]; then
    warn "No existe /dev/net/tun. En contenedores LXC/Proxmox esto suele impedir que Tailscale levante el túnel."
  else
    ok "Dispositivo TUN detectado: /dev/net/tun"
  fi
}

install_tailscale() {
  if command -v tailscale >/dev/null 2>&1; then
    ok "Tailscale ya está instalado: $(tailscale version 2>/dev/null | head -n1 || echo 'versión no disponible')"
    return 0
  fi

  log "Instalando Tailscale usando el script oficial..."
  curl -fsSL https://tailscale.com/install.sh | sh 2>&1 | tee -a "$LOG_FILE"

  command -v tailscale >/dev/null 2>&1 || fail "La instalación terminó pero el binario tailscale no quedó disponible."
  ok "Tailscale instalado correctamente."
}

enable_service() {
  log "Habilitando y levantando el servicio ${TAILSCALED_SERVICE}..."
  systemctl enable --now "$TAILSCALED_SERVICE" 2>&1 | tee -a "$LOG_FILE"
  sleep 2
  systemctl is-active --quiet "$TAILSCALED_SERVICE" || fail "${TAILSCALED_SERVICE} no quedó activo."
  ok "Servicio ${TAILSCALED_SERVICE} activo y habilitado al arranque."
}

build_up_args() {
  local args=()

  if [[ -n "$TS_AUTHKEY" ]]; then
    args+=("--auth-key=${TS_AUTHKEY}")
  fi

  if [[ -n "$TS_HOSTNAME" ]]; then
    args+=("--hostname=${TS_HOSTNAME}")
  fi

  if [[ "$ENABLE_SSH" == "true" ]]; then
    args+=("--ssh")
  fi

  if [[ "$ACCEPT_ROUTES" == "true" ]]; then
    args+=("--accept-routes")
  fi

  if [[ "$FORCE_RESET" == "true" ]]; then
    args+=("--reset")
  fi

  if [[ -n "$TS_LOGIN_SERVER" ]]; then
    args+=("--login-server=${TS_LOGIN_SERVER}")
  fi

  printf '%s\n' "${args[@]}"
}

get_status_json() {
  "$TAILSCALE_BIN" status --json 2>/dev/null || true
}

extract_with_python() {
  local field="$1"
  python3 - "$field" <<'PY'
import json, sys
field = sys.argv[1]
raw = sys.stdin.read().strip()
if not raw:
    print("")
    raise SystemExit(0)
try:
    data = json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)

if field == "backend_state":
    print(data.get("BackendState", ""))
elif field == "dns_name":
    print((data.get("Self") or {}).get("DNSName", ""))
elif field == "hostname":
    print((data.get("Self") or {}).get("HostName", ""))
elif field == "ipv4":
    ips = (data.get("Self") or {}).get("TailscaleIPs", [])
    print(ips[0] if ips else "")
else:
    print("")
PY
}

get_backend_state() {
  local raw
  raw="$(get_status_json)"
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$raw" | extract_with_python backend_state
  else
    echo ""
  fi
}

get_dns_name() {
  local raw
  raw="$(get_status_json)"
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$raw" | extract_with_python dns_name
  else
    echo ""
  fi
}

get_tail_ip() {
  local ip
  ip="$($TAILSCALE_BIN ip -4 2>/dev/null | head -n1 || true)"
  if [[ -n "$ip" ]]; then
    echo "$ip"
    return
  fi

  local raw
  raw="$(get_status_json)"
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$raw" | extract_with_python ipv4
  else
    echo ""
  fi
}

bring_up_tailscale() {
  log "Configurando Tailscale..."
  mapfile -t up_args < <(build_up_args)

  if [[ ${#up_args[@]} -eq 0 ]]; then
    log "Ejecutando: tailscale up"
  else
    log "Ejecutando: tailscale up ${up_args[*]}"
  fi

  local up_output=""
  if [[ ${#up_args[@]} -eq 0 ]]; then
    up_output="$($TAILSCALE_BIN up 2>&1 | tee -a "$LOG_FILE")" || true
  else
    up_output="$($TAILSCALE_BIN up "${up_args[@]}" 2>&1 | tee -a "$LOG_FILE")" || true
  fi

  local auth_url=""
  auth_url="$(printf '%s\n' "$up_output" | grep -Eo 'https://login\.tailscale\.com[^ ]+|https://controlplane\.tailscale\.com[^ ]+' | head -n1 || true)"

  local backend_state
  backend_state="$(get_backend_state)"

  if [[ -n "$TS_AUTHKEY" ]]; then
    ok "Alta automática solicitada con auth key."
  fi

  if [[ "$backend_state" != "Running" ]]; then
    if [[ -n "$auth_url" ]]; then
      warn "Hace falta autenticar este equipo en Tailscale."
      echo
      echo "=============================================================="
      echo "Abre esta URL en tu navegador para autorizar el servidor:"
      echo "$auth_url"
      echo "=============================================================="
      echo

      log "Esperando autenticación externa..."
      local i
      for i in $(seq 1 180); do
        sleep 2
        backend_state="$(get_backend_state)"
        if [[ "$backend_state" == "Running" ]]; then
          ok "Autenticación completada."
          break
        fi
        if (( i % 15 == 0 )); then
          log "Aún esperando autorización... estado actual: ${backend_state:-desconocido}"
        fi
      done
    fi
  fi

  backend_state="$(get_backend_state)"
  if [[ "$backend_state" != "Running" ]]; then
    fail "Tailscale no quedó en estado Running. Estado actual: ${backend_state:-desconocido}."
  fi

  ok "Tailscale quedó conectado correctamente."
}

print_summary() {
  local dns_name tail_ip local_user ssh_target ssh_url admin_url
  dns_name="$(get_dns_name)"
  tail_ip="$(get_tail_ip)"
  local_user="${SUDO_USER:-${USER:-root}}"

  if [[ -n "$dns_name" ]]; then
    ssh_target="${local_user}@${dns_name%.}"
    ssh_url="ssh://${ssh_target}"
  else
    ssh_target="${local_user}@${tail_ip:-<TAILSCALE-IP>}"
    ssh_url="ssh://${ssh_target}"
  fi

  admin_url="https://login.tailscale.com/admin/machines"

  echo
  echo "=============================================================="
  echo "TAILSCALE INSTALADO Y FUNCIONANDO"
  echo "=============================================================="
  echo "Equipo         : ${TS_HOSTNAME}"
  echo "DNS Tailscale  : ${dns_name:-no disponible aún}"
  echo "IP Tailscale   : ${tail_ip:-no disponible aún}"
  echo "Servicio       : ${TAILSCALED_SERVICE} activo"
  echo "SSH habilitado : ${ENABLE_SSH}"
  echo "Acepta rutas   : ${ACCEPT_ROUTES}"
  echo ""
  echo "Conéctate a este equipo usando esta URL SSH:"
  echo "  ${ssh_url}"
  echo ""
  echo "O con comando tradicional:"
  echo "  ssh ${ssh_target}"
  echo ""
  echo "Admin Tailscale:"
  echo "  ${admin_url}"
  echo ""
  echo "Log de instalación: ${LOG_FILE}"
  echo "=============================================================="
}

main() {
  parse_args "$@"
  require_root
  check_os
  check_requirements
  install_tailscale
  enable_service
  bring_up_tailscale
  print_summary
}

main "$@"
