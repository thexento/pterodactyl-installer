#!/bin/bash

# ==============================================================================
# Pterodactyl Installer by XENTO — Wings Installer Module
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

collect_wings_inputs() {
  echo -e "\n  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${WHITE}${BOLD}Wings Configuration${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

  while true; do
    echo -n -e "  ${WHITE}Wings Hostname or IP:${NC} "
    read -r WINGS_FQDN
    if validate_domain_ip "$WINGS_FQDN"; then break; else error "Invalid FQDN or IP format."; fi
  done

  echo -n -e "  ${WHITE}Auto-configure Wings from Panel? [y/N]:${NC} "
  read -r AUTO_CONF_RESP
  if [[ "$AUTO_CONF_RESP" =~ ^[Yy]$ ]]; then
    AUTO_CONFIGURE=true
    while true; do
      echo -n -e "  ${WHITE}Panel URL (e.g. https://panel.example.com):${NC} "
      read -r PANEL_URL
      if validate_url "$PANEL_URL"; then break; else error "Invalid URL format."; fi
    done

    while true; do
      echo -n -e "  ${WHITE}Application API Token (ptla_...):${NC} "
      read -r API_TOKEN
      if validate_token "$API_TOKEN"; then break; else error "Token must start with ptla_ and be valid."; fi
    done

    while true; do
      echo -n -e "  ${WHITE}Node ID:${NC} "
      read -r NODE_ID
      if validate_node_id "$NODE_ID"; then break; else error "Node ID must be a positive integer."; fi
    done
  else
    AUTO_CONFIGURE=false
  fi

  echo -n -e "  ${WHITE}Configure firewall rules? [y/N]:${NC} "
  read -r FW_RESP
  [[ "$FW_RESP" =~ ^[Yy]$ ]] && ENABLE_FW=true || ENABLE_FW=false

  echo -e "\n  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${WHITE}${BOLD}Summary - Wings Setup${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  Wings Hostname : ${WHITE}${WINGS_FQDN}${NC}"
  echo -e "  Auto Config    : ${WHITE}${AUTO_CONFIGURE}${NC}"
  echo -e "  Firewall       : ${WHITE}${ENABLE_FW}${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

  echo -n -e "  ${WHITE}Proceed with installation? [y/N]:${NC} "
  read -r CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    fatal "Installation aborted by user."
  fi
}

install_docker() {
  step "Installing Docker Engine..."
  if command -v docker >/dev/null 2>&1; then
    info "Docker is already installed. Skipping installation."
    return
  fi

  case "$OS_ID" in
    ubuntu|debian)
      pkg_install ca-certificates curl gnupg
      mkdir -p /etc/apt/keyrings
      curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg >> "$LOG_FILE" 2>&1
      chmod a+r /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} ${VERSION_CODENAME:-$OS_VERSION_ID} stable" > /etc/apt/sources.list.d/docker.list
      pkg_update
      pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    rocky|almalinux)
      pkg_install dnf-plugins-core
      dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >> "$LOG_FILE" 2>&1
      pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
  esac

  service_enable_start docker
  if ! docker info >> "$LOG_FILE" 2>&1; then
    fatal "Docker installed but failed to start."
  fi
  success "Docker installed successfully."
}

install_wings_binary() {
  step "Downloading Pterodactyl Wings binary..."
  mkdir -p /etc/pterodactyl /var/log/pterodactyl /var/lib/pterodactyl

  local latest_tag
  latest_tag=$(curl -fsSL https://api.github.com/repos/pterodactyl/wings/releases/latest | grep -oP '"tag_name": "\K[^"]+' || echo "v1.11.13")

  local download_url="https://github.com/pterodactyl/wings/releases/download/${latest_tag}/wings_linux_${ARCH}"
  info "Downloading Wings (${ARCH}) from ${download_url}..."

  curl -fsSL "$download_url" -o /usr/local/bin/wings
  chmod +x /usr/local/bin/wings

  if ! /usr/local/bin/wings --version >> "$LOG_FILE" 2>&1; then
    fatal "Wings binary verification failed."
  fi
  success "Wings binary installed."
}

configure_wings_service() {
  step "Configuring Wings systemd service..."

  cat > /etc/systemd/system/wings.service <<SERVICE
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=65535
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
SERVICE

  systemctl daemon-reload >> "$LOG_FILE" 2>&1
  systemctl enable wings >> "$LOG_FILE" 2>&1
  success "Wings systemd service created."
}

run_auto_configure() {
  if [[ "$AUTO_CONFIGURE" == true ]]; then
    step "Running automatic Wings configuration from Panel..."
    if /usr/local/bin/wings configure --panel-url "$PANEL_URL" --token "$API_TOKEN" --node "$NODE_ID" >> "$LOG_FILE" 2>&1; then
      success "Wings auto-configuration succeeded."
      service_enable_start wings
    else
      warn "Auto-configuration failed. You must manually copy config.yml into /etc/pterodactyl/config.yml."
    fi
  fi
}

main() {
  init_log
  check_root
  detect_os
  detect_arch

  collect_wings_inputs
  [[ "$ENABLE_FW" == true ]] && configure_firewall_ports 8080 2022 22

  install_docker
  install_wings_binary
  configure_wings_service
  run_auto_configure

  echo -e "\n  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${GREEN}${BOLD}[SUCCESS] Pterodactyl Wings Installation Complete!${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  if [[ -f /etc/pterodactyl/config.yml ]]; then
    echo -e "  Status       : ${WHITE}Wings is configured and running.${NC}"
  else
    echo -e "  Manual Action: ${WHITE}Copy configuration from Panel to /etc/pterodactyl/config.yml${NC}"
    echo -e "  Start Command: ${WHITE}systemctl start wings${NC}"
  fi
  echo -e "  Log File     : ${WHITE}${LOG_FILE}${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

main "$@"