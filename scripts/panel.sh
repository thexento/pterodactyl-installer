#!/bin/bash

# ==============================================================================
# Pterodactyl Installer — Panel Installer Module (with Live Tasks)
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

collect_panel_inputs() {
  echo -e "\n  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${WHITE}${BOLD}Panel Configuration${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

  echo -e "  ${WHITE}Select Pterodactyl Version:${NC}"
  echo -e "    ${WHITE}[1]${NC} Pterodactyl v1 (Stable — Recommended for Production)"
  echo -e "    ${WHITE}[2]${NC} Pterodactyl v2 (Alpha / Pre-Release — Modernized Stack)"
  while true; do
    echo -n -e "  ${WHITE}Choice [1-2]:${NC} "
    read -r VER_CHOICE
    case "$VER_CHOICE" in
      1) PANEL_VERSION="v1"; break ;;
      2) PANEL_VERSION="v2"; break ;;
      *) error "Invalid option. Enter 1 or 2." ;;
    esac
  done

  while true; do
    echo -n -e "\n  ${WHITE}Panel Domain or IP (e.g. panel.example.com):${NC} "
    read -r PANEL_FQDN
    if validate_domain_ip "$PANEL_FQDN"; then break; else error "Invalid FQDN or IP format."; fi
  done

  while true; do
    echo -n -e "  ${WHITE}Admin Email:${NC} "
    read -r ADMIN_EMAIL
    if validate_email "$ADMIN_EMAIL"; then break; else error "Invalid email address."; fi
  done

  while true; do
    echo -n -e "  ${WHITE}Admin Username (min 3 chars):${NC} "
    read -r ADMIN_USER
    if [[ ${#ADMIN_USER} -ge 3 ]]; then break; else error "Username must be at least 3 characters."; fi
  done

  while true; do
    echo -n -e "  ${WHITE}Admin First Name:${NC} "
    read -r ADMIN_FIRST
    if [[ -n "$ADMIN_FIRST" ]]; then break; else error "First name cannot be empty."; fi
  done

  while true; do
    echo -n -e "  ${WHITE}Admin Last Name:${NC} "
    read -r ADMIN_LAST
    if [[ -n "$ADMIN_LAST" ]]; then break; else error "Last name cannot be empty."; fi
  done

  while true; do
    echo -n -e "  ${WHITE}Admin Password (min 8 chars):${NC} "
    read -rs ADMIN_PASS
    echo ""
    if [[ ${#ADMIN_PASS} -ge 8 ]]; then break; else error "Password must be at least 8 characters."; fi
  done

  echo -n -e "  ${WHITE}Timezone [UTC]:${NC} "
  read -r TIMEZONE
  TIMEZONE="${TIMEZONE:-UTC}"

  echo -e "\n  ${WHITE}SSL Options:${NC}"
  echo -e "    ${WHITE}[1]${NC} Let's Encrypt (Automated SSL)"
  echo -e "    ${WHITE}[2]${NC} Behind Reverse Proxy / Cloudflare Tunnel (Assume SSL)"
  echo -e "    ${WHITE}[3]${NC} HTTP Only (No SSL)"
  while true; do
    echo -n -e "  ${WHITE}Select SSL option [1-3]:${NC} "
    read -r SSL_CHOICE
    case "$SSL_CHOICE" in
      1) PANEL_SSL="letsencrypt"; break ;;
      2) PANEL_SSL="assume"; break ;;
      3) PANEL_SSL="none"; break ;;
      *) error "Invalid choice. Enter 1, 2, or 3." ;;
    esac
  done

  echo -n -e "  ${WHITE}Configure firewall rules? [y/N]:${NC} "
  read -r FW_RESP
  if [[ "$FW_RESP" =~ ^[Yy]$ ]]; then
    ENABLE_FW=true
  else
    ENABLE_FW=false
  fi

  MYSQL_DB="panel"
  MYSQL_USER="pterodactyl"
  MYSQL_PASS="$(generate_password 24)"

  local ver_label="(Stable)"
  if [[ "$PANEL_VERSION" == "v2" ]]; then
    ver_label="(Alpha/Pre-Release)"
  fi

  echo -e "\n  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${WHITE}${BOLD}Summary - Panel Setup${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  Version    : ${WHITE}${PANEL_VERSION} ${ver_label}${NC}"
  echo -e "  Domain/IP  : ${WHITE}${PANEL_FQDN}${NC}"
  echo -e "  Admin User : ${WHITE}${ADMIN_USER} (${ADMIN_EMAIL})${NC}"
  echo -e "  Timezone   : ${WHITE}${TIMEZONE}${NC}"
  echo -e "  SSL Mode   : ${WHITE}${PANEL_SSL}${NC}"
  echo -e "  Firewall   : ${WHITE}${ENABLE_FW}${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

  echo -n -e "  ${WHITE}Proceed with installation? [y/N]:${NC} "
  read -r CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    fatal "Installation aborted by user."
  fi
}

do_setup_php_repositories() {
  case "$OS_ID" in
    ubuntu)
      pkg_install software-properties-common ca-certificates lsb-release apt-transport-https gnupg
      add-apt-repository -y universe >> "$LOG_FILE" 2>&1 || true
      ;;
    debian)
      pkg_install ca-certificates apt-transport-https lsb-release curl gnupg
      curl -fsSL https://packages.sury.org/php/apt.gpg -o /etc/apt/trusted.gpg.d/php.gpg >> "$LOG_FILE" 2>&1
      echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
      ;;
    rocky|almalinux)
      pkg_install epel-release
      dnf install -y "https://rpms.remirepo.net/enterprise/remi-release-${OS_MAJOR}.rpm" >> "$LOG_FILE" 2>&1 || true
      dnf module reset php -y >> "$LOG_FILE" 2>&1 || true
      dnf module enable php:remi-8.3 -y >> "$LOG_FILE" 2>&1
      ;;
  esac
  pkg_update
}

do_install_dependencies() {
  case "$PKG_MANAGER" in
    apt)
      local php_pkgs=()
      if apt-cache policy php8.3-mysql 2>/dev/null | grep -E "Candidate:\s+[0-9]" >/dev/null 2>&1; then
        php_pkgs=(php8.3 php8.3-cli php8.3-common php8.3-gd php8.3-mysql php8.3-mbstring \
                  php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl php8.3-zip php8.3-intl)
      else
        php_pkgs=(php php-cli php-common php-gd php-mysql php-mbstring \
                  php-bcmath php-xml php-fpm php-curl php-zip php-intl)
      fi
      pkg_install "${php_pkgs[@]}" mariadb-server nginx redis-server curl tar unzip git cron
      ;;
    dnf)
      pkg_install php php-cli php-common php-gd php-mysqlnd php-mbstring php-bcmath \
                  php-xml php-fpm php-curl php-zip php-intl \
                  mariadb mariadb-server nginx redis curl tar unzip git cronie
      ;;
  esac

  if [[ "$PANEL_VERSION" == "v2" ]]; then
    if ! command -v node >/dev/null 2>&1; then
      curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >> "$LOG_FILE" 2>&1 || true
      pkg_install nodejs
    fi
  fi
}

do_install_composer() {
  curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
  php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer >> "$LOG_FILE" 2>&1
  rm -f /tmp/composer-setup.php
  composer --version >> "$LOG_FILE" 2>&1
}

do_setup_database() {
  service_enable_start mariadb
  local sql_cmd="mysql"
  command -v mariadb >/dev/null 2>&1 && sql_cmd="mariadb"

  $sql_cmd -u root <<SQL >> "$LOG_FILE" 2>&1
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DB}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASS}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DB}\`.* TO '${MYSQL_USER}'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
}

do_download_panel() {
  mkdir -p /var/www/pterodactyl
  cd /var/www/pterodactyl

  if [[ "$PANEL_VERSION" == "v1" ]]; then
    local latest_tag
    latest_tag=$(curl -fsSL https://api.github.com/repos/pterodactyl/panel/releases/latest | grep -oP '"tag_name": "\K[^"]+' || echo "v1.11.11")
    curl -fsSL "https://github.com/pterodactyl/panel/releases/download/${latest_tag}/panel.tar.gz" -o panel.tar.gz
    tar -xzf panel.tar.gz
    rm -f panel.tar.gz
  else
    curl -fsSL "https://github.com/pterodactyl/panel/archive/refs/heads/2.0-develop.zip" -o panel.zip
    unzip -q panel.zip
    cp -a panel-2.0-develop/. .
    rm -rf panel-2.0-develop panel.zip
  fi

  chmod -R 755 storage bootstrap/cache
  cp .env.example .env
}

do_configure_panel_app() {
  cd /var/www/pterodactyl

  local scheme="http"
  [[ "$PANEL_SSL" != "none" ]] && scheme="https"
  local app_url="${scheme}://${PANEL_FQDN}"

  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction --ignore-platform-req=php+ >> "$LOG_FILE" 2>&1

  if [[ "$PANEL_VERSION" == "v2" && ! -d "public/build" ]]; then
    npm ci >> "$LOG_FILE" 2>&1 || npm install >> "$LOG_FILE" 2>&1
    npm run build >> "$LOG_FILE" 2>&1 || npm run build:production >> "$LOG_FILE" 2>&1 || true
  fi

  php artisan key:generate --force >> "$LOG_FILE" 2>&1

  php artisan p:environment:setup \
    --author="${ADMIN_EMAIL}" \
    --url="${app_url}" \
    --timezone="${TIMEZONE}" \
    --cache="redis" \
    --session="redis" \
    --queue="redis" \
    --redis-host="127.0.0.1" \
    --redis-pass="null" \
    --redis-port="6379" \
    --settings-ui=true \
    --no-interaction >> "$LOG_FILE" 2>&1

  php artisan p:environment:database \
    --host="127.0.0.1" \
    --port="3306" \
    --database="${MYSQL_DB}" \
    --username="${MYSQL_USER}" \
    --password="${MYSQL_PASS}" \
    --no-interaction >> "$LOG_FILE" 2>&1

  php artisan migrate --seed --force >> "$LOG_FILE" 2>&1

  php artisan p:user:make \
    --email="${ADMIN_EMAIL}" \
    --username="${ADMIN_USER}" \
    --name-first="${ADMIN_FIRST}" \
    --name-last="${ADMIN_LAST}" \
    --password="${ADMIN_PASS}" \
    --admin=1 \
    --no-interaction >> "$LOG_FILE" 2>&1

  local web_user="www-data"
  [[ "$PKG_MANAGER" == "dnf" ]] && web_user="nginx"
  chown -R "${web_user}:${web_user}" /var/www/pterodactyl
}

do_setup_services() {
  (crontab -l 2>/dev/null | grep -v "pterodactyl/artisan schedule:run" || true; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -

  local web_user="www-data"
  [[ "$PKG_MANAGER" == "dnf" ]] && web_user="nginx"

  cat > /etc/systemd/system/pteroq.service <<SERVICE
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service mariadb.service
Wants=redis-server.service mariadb.service

[Service]
User=${web_user}
Group=${web_user}
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
SERVICE

  service_enable_start redis-server || service_enable_start redis
  service_enable_start pteroq
}

do_configure_nginx() {
  systemctl restart php*-fpm >> "$LOG_FILE" 2>&1 || true
  sleep 1

  local php_sock=""
  php_sock="$(find /run/php -maxdepth 1 -name "*fpm.sock" 2>/dev/null | head -n 1 || true)"
  if [[ -z "$php_sock" ]]; then
    for s in /run/php/php*-fpm.sock /run/php/php-fpm.sock /run/php/php8.3-fpm.sock; do
      [[ -S "$s" ]] && php_sock="$s" && break
    done
  fi
  [[ -z "$php_sock" ]] && php_sock="/run/php/php-fpm.sock"

  local conf_path="/etc/nginx/sites-available/pterodactyl.conf"
  [[ "$PKG_MANAGER" == "dnf" ]] && conf_path="/etc/nginx/conf.d/pterodactyl.conf"

  cat > "$conf_path" <<NGINX
server {
    listen 80;
    server_name ${PANEL_FQDN};
    root /var/www/pterodactyl/public;
    index index.php;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:${php_sock};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size = 100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht { deny all; }
}
NGINX

  if [[ "$PKG_MANAGER" == "apt" ]]; then
    mkdir -p /etc/nginx/sites-enabled
    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
  fi

  nginx -t >> "$LOG_FILE" 2>&1
  service_enable_start nginx
}

do_setup_ssl() {
  if [[ "$PANEL_SSL" == "letsencrypt" ]]; then
    pkg_install certbot python3-certbot-nginx
    certbot --nginx --redirect --no-eff-email --email "${ADMIN_EMAIL}" -d "${PANEL_FQDN}" --non-interactive >> "$LOG_FILE" 2>&1 || true
  fi
}

main() {
  init_log
  detect_os
  detect_arch

  collect_panel_inputs
  [[ "$ENABLE_FW" == true ]] && configure_firewall_ports 80 443 22

  # Tasks run with live spinner and elapsed timer
  run_task "Configuring package repositories" do_setup_php_repositories
  run_task "Installing system & runtime dependencies" do_install_dependencies
  run_task "Installing Composer package manager" do_install_composer
  run_task "Setting up MariaDB database and user" do_setup_database
  run_task "Downloading Pterodactyl Panel source" do_download_panel
  run_task "Configuring environment & compiling assets" do_configure_panel_app
  run_task "Registering systemd queue workers & cron" do_setup_services
  run_task "Configuring Nginx web server" do_configure_nginx
  run_task "Configuring SSL certificate" do_setup_ssl

  local scheme="http"
  [[ "$PANEL_SSL" != "none" ]] && scheme="https"

  echo -e "\n  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${GREEN}${BOLD}[SUCCESS] Pterodactyl Panel (${PANEL_VERSION}) Installed!${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  URL          : ${WHITE}${scheme}://${PANEL_FQDN}${NC}"
  echo -e "  Username     : ${WHITE}${ADMIN_USER}${NC}"
  echo -e "  Email        : ${WHITE}${ADMIN_EMAIL}${NC}"
  echo -e "  DB Password  : ${WHITE}${MYSQL_PASS}${NC}"
  echo -e "  Log File     : ${WHITE}${LOG_FILE}${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

main "$@"