#!/bin/bash

# ==============================================================================
# Pterodactyl Installer by XENTO — Main Entrypoint
# Repository: https://github.com/thexento/Pterodactyl-Installer
# Website:    https://pterodactyl-installer.xento.us.kg
# License:    GNU General Public License v3.0
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# If executing remotely via pipe, download helper scripts automatically
if [[ ! -d "$SCRIPTS_DIR" ]]; then
  mkdir -p /tmp/pterodactyl-installer/scripts
  BASE_RAW_URL="https://raw.githubusercontent.com/thexento/Pterodactyl-Installer/main/scripts"
  curl -fsSL "${BASE_RAW_URL}/common.sh" -o /tmp/pterodactyl-installer/scripts/common.sh
  curl -fsSL "${BASE_RAW_URL}/panel.sh" -o /tmp/pterodactyl-installer/scripts/panel.sh
  curl -fsSL "${BASE_RAW_URL}/wings.sh" -o /tmp/pterodactyl-installer/scripts/wings.sh
  curl -fsSL "${BASE_RAW_URL}/phpmyadmin.sh" -o /tmp/pterodactyl-installer/scripts/phpmyadmin.sh
  curl -fsSL "${BASE_RAW_URL}/uninstall.sh" -o /tmp/pterodactyl-installer/scripts/uninstall.sh
  SCRIPTS_DIR="/tmp/pterodactyl-installer/scripts"
  chmod +x "${SCRIPTS_DIR}"/*.sh
fi

# shellcheck source=scripts/common.sh
source "${SCRIPTS_DIR}/common.sh"

print_header() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo -e "  ██╗  ██╗███████╗███╗   ██╗████████╗ ██████╗ "
  echo -e "  ╚██╗██╔╝██╔════╝████╗  ██║╚══██╔══╝██╔═══██╗"
  echo -e "   ╚███╔╝ █████╗  ██╔██╗ ██║   ██║   ██║   ██║"
  echo -e "   ██╔██╗ ██╔══╝  ██║╚██╗██║   ██║   ██║   ██║"
  echo -e "  ██╔╝ ██╗███████╗██║ ╚████║   ██║   ╚██████╔╝"
  echo -e "  ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ "
  echo -e "${NC}"
  echo -e "  ${WHITE}${BOLD}Pterodactyl Installer — by XENTO${NC}"
  echo -e "  ${DIM}https://github.com/thexento/Pterodactyl-Installer${NC}"
  echo -e "  ${DIM}https://pterodactyl-installer.xento.us.kg${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
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
    echo -e "  ${WHITE}${BOLD}Select an action:${NC}\n"
    echo -e "  ${WHITE}[1]${NC} Install Pterodactyl Panel"
    echo -e "  ${WHITE}[2]${NC} Install Pterodactyl Wings"
    echo -e "  ${WHITE}[3]${NC} Install Panel + Wings (Same Machine)"
    echo -e "  ${WHITE}[4]${NC} Install phpMyAdmin"
    echo -e "  ${WHITE}[5]${NC} Check System Status"
    echo -e "  ${WHITE}[6]${NC} Uninstall Components"
    echo -e "  ${WHITE}[7]${NC} Exit"
    echo -e "\n  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    echo -n -e "  ${WHITE}Choice [1-7]:${NC} "
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
  elevate_root  # Auto-elevates BEFORE trying to create log files
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