#!/bin/bash

# ==============================================================================
# Pterodactyl Installer — Main Entrypoint
# Repository: https://github.com/thexento/Pterodactyl-Installer
# License:    GNU General Public License v3.0
# ==============================================================================

set -Eeuo pipefail

# --- 1. Root Auto-Elevation ---
if [[ $EUID -ne 0 ]]; then
  echo -e "\033[0;36m[INFO]\033[0m  Root privileges required. Elevating via sudo..."
  if ! command -v sudo >/dev/null 2>&1; then
    echo -e "\033[0;31m[FATAL]\033[0m Root privileges required and 'sudo' was not found. Run as root." >&2
    exit 1
  fi

  SELF="${BASH_SOURCE[0]:-$0}"
  if [[ -n "$SELF" && -f "$SELF" && ! "$SELF" =~ ^/dev/fd/ ]]; then
    exec sudo bash "$SELF" "$@"
  else
    mkdir -p /tmp/pterodactyl-installer
    curl -fsSL "https://raw.githubusercontent.com/thexento/Pterodactyl-Installer/main/install.sh" -o /tmp/pterodactyl-installer/install.sh
    chmod +x /tmp/pterodactyl-installer/install.sh
    exec sudo bash /tmp/pterodactyl-installer/install.sh "$@"
  fi
fi

# --- 2. Directory & Dependency Resolution ---
CURRENT_SCRIPT="${BASH_SOURCE[0]:-$0}"
if [[ -n "$CURRENT_SCRIPT" && -f "$CURRENT_SCRIPT" && ! "$CURRENT_SCRIPT" =~ ^/dev/fd/ ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$CURRENT_SCRIPT")" && pwd)"
  SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
else
  SCRIPT_DIR="/tmp/pterodactyl-installer"
  SCRIPTS_DIR="/tmp/pterodactyl-installer/scripts"
fi

# Download fresh helper modules when executing remotely
if [[ "$SCRIPTS_DIR" == "/tmp/pterodactyl-installer/scripts" || ! -f "${SCRIPTS_DIR}/common.sh" ]]; then
  mkdir -p "$SCRIPTS_DIR"
  BASE_RAW_URL="https://raw.githubusercontent.com/thexento/Pterodactyl-Installer/main/scripts"
  curl -fsSL "${BASE_RAW_URL}/common.sh" -o "${SCRIPTS_DIR}/common.sh"
  curl -fsSL "${BASE_RAW_URL}/panel.sh" -o "${SCRIPTS_DIR}/panel.sh"
  curl -fsSL "${BASE_RAW_URL}/wings.sh" -o "${SCRIPTS_DIR}/wings.sh"
  curl -fsSL "${BASE_RAW_URL}/phpmyadmin.sh" -o "${SCRIPTS_DIR}/phpmyadmin.sh"
  curl -fsSL "${BASE_RAW_URL}/uninstall.sh" -o "${SCRIPTS_DIR}/uninstall.sh"
  chmod +x "${SCRIPTS_DIR}"/*.sh
fi

# shellcheck source=/dev/null
source "${SCRIPTS_DIR}/common.sh"

print_header() {
  clear
  echo -e "\n  ${BOLD}Pterodactyl Installer${NC} ${DIM}(v1.1.0)${NC}"
  echo -e "  ${DIM}https://github.com/thexento/Pterodactyl-Installer${NC}"
  echo -e "  ──────────────────────────────────────────────────\n"
}

check_system_status() {
  print_header
  step "System & Service Health Check"

  echo -n -e "  MariaDB Service : "
  service_is_active mariadb && echo -e "${GREEN}Running${NC}" || echo -e "${RED}Stopped / Not Installed${NC}"

  echo -n -e "  Redis Service   : "
  (service_is_active redis-server || service_is_active redis) && echo -e "${GREEN}Running${NC}" || echo -e "${RED}Stopped / Not Installed${NC}"

  echo -n -e "  Nginx Service   : "
  service_is_active nginx && echo -e "${GREEN}Running${NC}" || echo -e "${RED}Stopped / Not Installed${NC}"

  echo -n -e "  Pteroq Worker   : "
  service_is_active pteroq && echo -e "${GREEN}Running${NC}" || echo -e "${RED}Stopped / Not Installed${NC}"

  echo -n -e "  Docker Service  : "
  service_is_active docker && echo -e "${GREEN}Running${NC}" || echo -e "${RED}Stopped / Not Installed${NC}"

  echo -n -e "  Wings Service   : "
  service_is_active wings && echo -e "${GREEN}Running${NC}" || echo -e "${RED}Stopped / Not Installed${NC}"

  echo -e "\n  Press Enter to return to menu..."
  read -r
}

interactive_menu() {
  while true; do
    print_header
    echo -e "  ${WHITE}Select an action:${NC}\n"
    echo -e "  [1] Install Pterodactyl Panel"
    echo -e "  [2] Install Pterodactyl Wings"
    echo -e "  [3] Install Panel + Wings (Same Machine)"
    echo -e "  [4] Install phpMyAdmin"
    echo -e "  [5] Check System Status"
    echo -e "  [6] Uninstall Components"
    echo -e "  [7] Exit"
    echo -e "\n  ──────────────────────────────────────────────────\n"

    echo -n -e "  Choice [1-7]: "
    read -r CHOICE

    case "$CHOICE" in
      1) bash "${SCRIPTS_DIR}/panel.sh"; break ;;
      2) bash "${SCRIPTS_DIR}/wings.sh"; break ;;
      3)
        bash "${SCRIPTS_DIR}/panel.sh"
        bash "${SCRIPTS_DIR}/wings.sh"
        break
        ;;
      4) bash "${SCRIPTS_DIR}/phpmyadmin.sh"; break ;;
      5) check_system_status ;;
      6) bash "${SCRIPTS_DIR}/uninstall.sh"; break ;;
      7) echo -e "\n  Goodbye!"; exit 0 ;;
      *) error "Invalid choice. Please select 1 to 7." ; sleep 1 ;;
    esac
  done
}

main() {
  init_log
  detect_os
  detect_arch

  if [[ $# -gt 0 ]]; then
    case "$1" in
      panel) bash "${SCRIPTS_DIR}/panel.sh" ;;
      wings) bash "${SCRIPTS_DIR}/wings.sh" ;;
      both)
        bash "${SCRIPTS_DIR}/panel.sh"
        bash "${SCRIPTS_DIR}/wings.sh"
        ;;
      phpmyadmin) bash "${SCRIPTS_DIR}/phpmyadmin.sh" ;;
      uninstall) bash "${SCRIPTS_DIR}/uninstall.sh" ;;
      status) check_system_status ;;
      *)
        fatal "Unknown CLI argument '$1'. Valid options: panel, wings, both, phpmyadmin, uninstall, status."
        ;;
    esac
  else
    interactive_menu
  fi
}

main "$@"