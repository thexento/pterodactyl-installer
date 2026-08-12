#!/bin/bash

# ==============================================================================
# Pterodactyl Installer by XENTO — Shared Common Library
# Repository: https://github.com/thexento/Pterodactyl-Installer
# Website:    https://pterodactyl-installer.xento.us.kg
# License:    GNU General Public License v3.0
# ==============================================================================

set -Eeuo pipefail

# --- Constants ---
export LOG_FILE="/var/log/pterodactyl-xento.log"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Logging & UI Functions ---
init_log() {
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE"
}

sanitize_log() {
  sed -E 's/(pass|password|token|secret|key)=[^& ]+/\1=**********/gi'
}

log_write() {
  local level="$1"
  shift
  local msg="$*"
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${level}] ${msg}" | sanitize_log >> "$LOG_FILE"
}

info() {
  echo -e "${CYAN}[INFO]${NC}  $*"
  log_write "INFO" "$*"
}

step() {
  echo -e "${WHITE}${BOLD}[STEP]${NC}  $*"
  log_write "STEP" "$*"
}

success() {
  echo -e "${GREEN}[OK]${NC}    $*"
  log_write "SUCCESS" "$*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC}  $*"
  log_write "WARN" "$*"
}

error() {
  echo -e "${RED}[ERR]${NC}   $*" >&2
  log_write "ERROR" "$*"
}

fatal() {
  echo -e "${RED}${BOLD}[FATAL]${NC} $*" >&2
  log_write "FATAL" "$*"
  exit 1
}

# --- System Checks ---
check_root() {
  if [[ $EUID -ne 0 ]]; then
    fatal "This script must be executed as root. (e.g. sudo bash $0)"
  fi
}

detect_os() {
  if [[ ! -f /etc/os-release ]]; then
    fatal "Operating system release information (/etc/os-release) not found."
  fi

  # Shellcheck source=/dev/null
  source /etc/os-release

  OS_ID="${ID:-unknown}"
  OS_VERSION_ID="${VERSION_ID:-0}"
  OS_MAJOR="${OS_VERSION_ID%%.*}"

  case "$OS_ID" in
    ubuntu)
      case "$OS_VERSION_ID" in
        22.04|24.04) ;;
        *) fatal "Unsupported Ubuntu version: ${OS_VERSION_ID}. Supported: 22.04, 24.04." ;;
      esac
      PKG_MANAGER="apt"
      ;;
    debian)
      case "$OS_MAJOR" in
        11|12) ;;
        *) fatal "Unsupported Debian version: ${OS_VERSION_ID}. Supported: 11, 12." ;;
      esac
      PKG_MANAGER="apt"
      ;;
    rocky|almalinux)
      case "$OS_MAJOR" in
        8|9) ;;
        *) fatal "Unsupported ${OS_ID} version: ${OS_VERSION_ID}. Supported: 8, 9." ;;
      esac
      PKG_MANAGER="dnf"
      ;;
    *)
      fatal "Unsupported operating system: ${OS_ID}. Supported: Ubuntu, Debian, Rocky Linux, AlmaLinux."
      ;;
  esac

  info "Detected OS: ${NAME} ${VERSION_ID} (${PKG_MANAGER})"
}

detect_arch() {
  local raw_arch
  raw_arch="$(uname -m)"

  case "$raw_arch" in
    x86_64|amd64)
      ARCH="amd64"
      ;;
    aarch64|arm64|armv8*)
      ARCH="arm64"
      ;;
    *)
      fatal "Unsupported architecture: ${raw_arch}. Supported: x86_64, aarch64."
      ;;
  esac

  info "Detected Architecture: ${raw_arch} (${ARCH})"
}

# --- Validation Helpers ---
validate_email() {
  [[ "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validate_domain_ip() {
  [[ "$1" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || \
  [[ "$1" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
}

validate_url() {
  [[ "$1" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]
}

validate_token() {
  [[ "$1" =~ ^ptla_[a-zA-Z0-9]{32,}$ ]]
}

validate_node_id() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]
}

generate_password() {
  local length="${1:-24}"
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
}

# --- Package Management Wrappers ---
pkg_update() {
  log_write "EXEC" "Updating package databases"
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    DEBIAN_FRONTEND=noninteractive apt-get update -y >> "$LOG_FILE" 2>&1
  else
    dnf makecache -y >> "$LOG_FILE" 2>&1
  fi
}

pkg_install() {
  log_write "EXEC" "Installing packages: $*"
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" >> "$LOG_FILE" 2>&1
  else
    dnf install -y "$@" >> "$LOG_FILE" 2>&1
  fi
}

# --- Service Wrappers ---
service_enable_start() {
  local service_name="$1"
  log_write "EXEC" "Enabling and starting service: ${service_name}"
  systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
  systemctl enable "$service_name" >> "$LOG_FILE" 2>&1
  systemctl restart "$service_name" >> "$LOG_FILE" 2>&1
}

service_is_active() {
  systemctl is-active --quiet "$1"
}

# --- Backup Helper ---
create_backup() {
  local target_path="$1"
  local label="$2"

  if [[ -e "$target_path" ]]; then
    local ts
    ts="$(date +'%Y%m%d_%H%M%S')"
    local backup_dir="/var/backups/pterodactyl-xento/${ts}"
    mkdir -p "$backup_dir"

    info "Creating backup of ${label} at ${backup_dir}..."
    cp -rf "$target_path" "${backup_dir}/" >> "$LOG_FILE" 2>&1
    success "Backup created for ${label}."
  fi
}

# --- Firewall Helper ---
configure_firewall_ports() {
  local ports=("$@")

  if command -v ufw >/dev/null 2>&1; then
    info "Configuring UFW rules..."
    for port in "${ports[@]}"; do
      ufw allow "$port" >> "$LOG_FILE" 2>&1 || true
    done
    ufw --force enable >> "$LOG_FILE" 2>&1 || true
    success "UFW firewall updated."
  elif command -v firewall-cmd >/dev/null 2>&1; then
    info "Configuring firewalld rules..."
    for port in "${ports[@]}"; do
      firewall-cmd --permanent --add-port="$port" >> "$LOG_FILE" 2>&1 || true
    done
    firewall-cmd --reload >> "$LOG_FILE" 2>&1 || true
    success "firewalld updated."
  else
    warn "No supported firewall manager (ufw/firewalld) found active. Skipping firewall setup."
  fi
}