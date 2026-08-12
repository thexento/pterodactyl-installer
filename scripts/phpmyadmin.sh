#!/bin/bash

# ==============================================================================
# Pterodactyl Installer by XENTO — phpMyAdmin Module
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

collect_pma_inputs() {
  echo -e "\n  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${WHITE}${BOLD}phpMyAdmin Configuration${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

  while true; do
    echo -n -e "  ${WHITE}phpMyAdmin Domain or IP:${NC} "
    read -r PMA_FQDN
    if validate_domain_ip "$PMA_FQDN"; then break; else error "Invalid FQDN or IP format."; fi
  done

  echo -e "\n  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${WHITE}${BOLD}Summary - phpMyAdmin Setup${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  phpMyAdmin URL : ${WHITE}${PMA_FQDN}${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

  echo -n -e "  ${WHITE}Proceed with installation? [y/N]:${NC} "
  read -r CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    fatal "Installation aborted by user."
  fi
}

install_phpmyadmin() {
  step "Downloading and installing phpMyAdmin..."
  local pma_dir="/var/www/phpmyadmin"
  mkdir -p "$pma_dir"

  local version="5.2.1"
  local url="https://files.phpmyadmin.net/phpMyAdmin/${version}/phpMyAdmin-${version}-all-languages.tar.gz"

  curl -fsSL "$url" -o /tmp/pma.tar.gz
  tar -xzf /tmp/pma.tar.gz --strip-components=1 -C "$pma_dir"
  rm -f /tmp/pma.tar.gz

  local blowfish
  blowfish="$(generate_password 32)"
  cp "${pma_dir}/config.sample.inc.php" "${pma_dir}/config.inc.php"
  sed -i "s/\$cfg\['blowfish_secret'\] = '';/\$cfg\['blowfish_secret'\] = '${blowfish}';/g" "${pma_dir}/config.inc.php"

  local web_user="www-data"
  [[ "$PKG_MANAGER" == "dnf" ]] && web_user="nginx"
  chown -R "${web_user}:${web_user}" "$pma_dir"

  success "phpMyAdmin downloaded."
}

configure_pma_nginx() {
  step "Configuring Nginx virtual host for phpMyAdmin..."
  local php_sock="/run/php/php8.3-fpm.sock"
  [[ "$PKG_MANAGER" == "dnf" ]] && php_sock="/run/php-fpm/www.sock"

  local conf_path="/etc/nginx/sites-available/phpmyadmin.conf"
  [[ "$PKG_MANAGER" == "dnf" ]] && conf_path="/etc/nginx/conf.d/phpmyadmin.conf"

  cat > "$conf_path" <<NGINX
server {
    listen 80;
    server_name ${PMA_FQDN};
    root /var/www/phpmyadmin;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:${php_sock};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
    }

    location ~ /\.ht { deny all; }
}
NGINX

  if [[ "$PKG_MANAGER" == "apt" ]]; then
    mkdir -p /etc/nginx/sites-enabled
    ln -sf "$conf_path" /etc/nginx/sites-enabled/phpmyadmin.conf
  fi

  if ! nginx -t >> "$LOG_FILE" 2>&1; then
    fatal "Nginx test failed for phpMyAdmin config."
  fi

  service_enable_start nginx
  success "Nginx configured for phpMyAdmin."
}

main() {
  init_log
  check_root
  detect_os
  detect_arch

  collect_pma_inputs
  install_phpmyadmin
  configure_pma_nginx

  echo -e "\n  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${GREEN}${BOLD}[SUCCESS] phpMyAdmin Installed!${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  URL : ${WHITE}http://${PMA_FQDN}${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

main "$@"