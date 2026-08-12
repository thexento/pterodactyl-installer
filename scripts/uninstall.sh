#!/bin/bash

# ==============================================================================
# Pterodactyl Installer by XENTO — Safe Uninstaller Module
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

collect_uninstall_inputs() {
  echo -e "\n  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${RED}${BOLD}Uninstaller — Destructive Action Confirmation${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

  RM_PANEL=false
  RM_WINGS=false
  RM_PMA=false

  echo -n -e "  ${WHITE}Uninstall Panel? [y/N]:${NC} "
  read -r RESP
  [[ "$RESP" =~ ^[Yy]$ ]] && RM_PANEL=true

  echo -n -e "  ${WHITE}Uninstall Wings? [y/N]:${NC} "
  read -r RESP
  [[ "$RESP" =~ ^[Yy]$ ]] && RM_WINGS=true

  echo -n -e "  ${WHITE}Uninstall phpMyAdmin? [y/N]:${NC} "
  read -r RESP
  [[ "$RESP" =~ ^[Yy]$ ]] && RM_PMA=true

  if [[ "$RM_PANEL" == false && "$RM_WINGS" == false && "$RM_PMA" == false ]]; then
    info "No components selected for removal. Exiting."
    exit 0
  fi

  echo -e "\n  ${RED}${BOLD}WARNING: The selected components will be permanently deleted!${NC}"
  echo -e "  Remove Panel     : ${WHITE}${RM_PANEL}${NC}"
  echo -e "  Remove Wings     : ${WHITE}${RM_WINGS}${NC}"
  echo -e "  Remove phpMyAdmin: ${WHITE}${RM_PMA}${NC}\n"

  while true; do
    echo -n -e "  ${RED}Type 'UNINSTALL' to confirm:${NC} "
    read -r CONFIRM
    [[ "$CONFIRM" == "UNINSTALL" ]] && break
    error "Invalid confirmation. Enter exactly 'UNINSTALL'."
  done
}

remove_panel() {
  step "Removing Pterodactyl Panel..."
  create_backup "/var/www/pterodactyl" "Panel Files"

  systemctl disable --now pteroq >> "$LOG_FILE" 2>&1 || true
  rm -f /etc/systemd/system/pteroq.service

  # Remove crontab entry safely
  (crontab -l 2>/dev/null | grep -v "pterodactyl/artisan schedule:run" || true) | crontab -

  rm -rf /var/www/pterodactyl
  rm -f /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/conf.d/pterodactyl.conf

  if command -v mysql >/dev/null 2>&1; then
    mysql -u root -e "DROP DATABASE IF EXISTS \`panel\`; DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';" >> "$LOG_FILE" 2>&1 || true
  fi

  systemctl reload nginx >> "$LOG_FILE" 2>&1 || true
  success "Panel removed."
}

remove_wings() {
  step "Removing Pterodactyl Wings..."
  create_backup "/etc/pterodactyl" "Wings Config"

  systemctl disable --now wings >> "$LOG_FILE" 2>&1 || true
  rm -f /etc/systemd/system/wings.service
  rm -f /usr/local/bin/wings
  rm -rf /etc/pterodactyl /var/lib/pterodactyl

  systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
  success "Wings removed."
}

remove_pma() {
  step "Removing phpMyAdmin..."
  rm -rf /var/www/phpmyadmin
  rm -f /etc/nginx/sites-available/phpmyadmin.conf /etc/nginx/sites-enabled/phpmyadmin.conf /etc/nginx/conf.d/phpmyadmin.conf
  systemctl reload nginx >> "$LOG_FILE" 2>&1 || true
  success "phpMyAdmin removed."
}

main() {
  init_log
  check_root
  detect_os

  collect_uninstall_inputs

  [[ "$RM_PANEL" == true ]] && remove_panel
  [[ "$RM_WINGS" == true ]] && remove_wings
  [[ "$RM_PMA" == true ]] && remove_pma

  echo -e "\n  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${GREEN}${BOLD}[SUCCESS] Uninstallation Task Complete!${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

main "$@"