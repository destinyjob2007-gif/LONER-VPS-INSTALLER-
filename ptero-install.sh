set -u
export DEBIAN_FRONTEND=noninteractive
export COMPOSER_ALLOW_SUPERUSER=1
LOG=/root/ptero-install.log
: > "$LOG"

say()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31mSTOPPED: %s\033[0m\nDetails: tail -40 %s\nFix it, then run the script again.\n' "$*" "$LOG"; exit 1; }
run()  { "$@" >>"$LOG" 2>&1; }

banner() {
  clear 2>/dev/null || true
  printf '\033[1;31m'
  cat <<'BANNER'
█    ████ █  █ ████ ███
█    █  █ ██ █ █    █  █
█    █  █ █ ██ ███  ███
█    █  █ █  █ █    █ █
████ ████ █  █ ████ █  █

█  █ ███  ████
█  █ █  █ █
█  █ ███  ████
█  █ █       █
 ██  █    ████

████ █  █ ████ ████ ████ █    █    ████ ███
 ██  ██ █ █     ██  █  █ █    █    █    █  █
 ██  █ ██ ████  ██  ████ █    █    ███  ███
 ██  █  █    █  ██  █  █ █    █    █    █ █
████ █  █ ████  ██  █  █ ████ ████ ████ █  █
BANNER
  printf '\033[0m\n\033[31m  Pterodactyl panel + Wings + Docker, one run.\033[0m\n\n'
}
pause() { read -r -p "  Press Enter when done... " _ </dev/tty; }

[ "$(id -u)" = 0 ] || die "Run as root."
. /etc/os-release
case "${ID:-}" in ubuntu|debian) ;; *) die "This installer supports Ubuntu and Debian only (you have ${PRETTY_NAME:-unknown})." ;; esac
case "${ID}-${VERSION_ID:-}" in ubuntu-22.04|ubuntu-24.04|debian-11|debian-12|debian-13) ;; *) warn "Tested on Ubuntu 22.04/24.04 and Debian 11/12/13 (you have ${PRETTY_NAME:-unknown}). Continuing anyway." ;; esac
PHPV=8.3
SYSTEMD=0
[ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1 && SYSTEMD=1

# ---------- where to keep data -------------------------------------------------
# Normal servers (systemd) keep everything in the usual places. Only no-systemd VMs link folders into /data.
if [ "$SYSTEMD" = 1 ]; then DATA=/var/lib/ptero-data
elif mountpoint -q /data 2>/dev/null; then DATA=/data
else DATA=/var/lib/ptero-data; fi
mkdir -p "$DATA"/{conf,docker,www,mysql,pterodactyl,.ptero-install}
STATE="$DATA/.ptero-install"
CONF="$STATE/config.env"
banner
say "Data folder: $DATA"

# ---------- questions (asked once, saved) --------------------------------------
if [ -f "$CONF" ]; then
  . "$CONF"
  say "Using saved answers from $CONF"
else
  ask() { local v; read -r -p "$1" v </dev/tty; echo "$v"; }
  echo "Answer a few questions. Nothing is sent anywhere."
  echo
  echo "How will people reach your panel?"
  echo "  1) ngrok  - free, no domain needed (best for beginners)"
  echo "  2) My own domain - you own a domain (like panel.example.com) and this"
  echo "     VPS has a public IP with ports 80 and 443 open"
  MODE_ANS=$(ask "Choose 1 or 2 [1]: ")
  if [ "$MODE_ANS" = 2 ]; then MODE=domain; else MODE=ngrok; fi
  NGROK_TOKEN=""
  if [ "$MODE" = domain ]; then
    banner
    VPS_IP=$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)
    echo "  OWN DOMAIN SETUP. Before you continue, do this at your domain provider"
    echo "  (Namecheap, GoDaddy, Cloudflare, etc.):"
    echo "    1. Add a DNS record:  Type A   Name: panel (or any name you like)"
    echo "       Value: ${VPS_IP:-your VPS IP}"
    echo "    2. If you use Cloudflare, set the record to DNS only (grey cloud)."
    echo "    3. In your VPS provider's firewall, open ports 80 and 443."
    echo "    4. Wait a few minutes for DNS to update."
    pause
    PANEL_DOMAIN=$(ask "Your full panel domain (e.g. panel.example.com): ")
    PANEL_DOMAIN=${PANEL_DOMAIN#https://}; PANEL_DOMAIN=${PANEL_DOMAIN#http://}; PANEL_DOMAIN=${PANEL_DOMAIN%%/*}
    DOM_IP=$(getent hosts "$PANEL_DOMAIN" | awk '{print $1; exit}')
    if [ -z "$DOM_IP" ] || { [ -n "$VPS_IP" ] && [ "$DOM_IP" != "$VPS_IP" ]; }; then
      warn "$PANEL_DOMAIN points to '${DOM_IP:-nothing yet}' but this VPS is '${VPS_IP:-unknown}'."
      warn "The free HTTPS certificate will fail until DNS matches. Fix DNS, wait, then run this script again."
      exit 1
    fi
    echo "  DNS looks good: $PANEL_DOMAIN -> $DOM_IP"
  else
  echo
  echo "ngrok gives your panel a free public https address, so you do not"
  echo "need to buy a domain."
  have=$(ask "Do you already have an ngrok domain and authtoken? [y/N]: ")
  if [[ ! "$have" =~ ^[Yy] ]]; then
    banner
    echo "  STEP A - Make a free ngrok account (on your phone or PC browser)"
    echo "    1. Open:  https://dashboard.ngrok.com/signup"
    echo "    2. Sign up with email or Google, then confirm the email they send."
    pause
    echo
    echo "  STEP B - Get your free domain"
    echo "    1. Open:  https://dashboard.ngrok.com/domains"
    echo "    2. Tap  Create Domain  (or  + New Domain)."
    echo "    3. You get a name like  happy-cat-1234.ngrok-free.dev"
    echo "       Copy it. This is your PANEL DOMAIN."
    pause
    echo
    echo "  STEP C - Get your authtoken"
    echo "    1. Open:  https://dashboard.ngrok.com/get-started/your-authtoken"
    echo "    2. Tap the copy button next to the long token."
    echo "    Keep it secret. Never post it in a chat or screenshot."
    pause
    echo
    echo "  Now paste them below. (Long-press to paste. The token is hidden"
    echo "  while you paste, that is normal.)"
    echo
  fi
  PANEL_DOMAIN=$(ask "Panel ngrok domain (e.g. name.ngrok-free.dev): ")
  PANEL_DOMAIN=${PANEL_DOMAIN#https://}; PANEL_DOMAIN=${PANEL_DOMAIN#http://}; PANEL_DOMAIN=${PANEL_DOMAIN%%/*}
  read -r -s -p "ngrok authtoken (hidden): " NGROK_TOKEN </dev/tty; echo
  fi
  ADMIN_EMAIL=$(ask "Admin email: ")
  ADMIN_USER=$(ask "Admin username: ")
  while true; do
    read -r -s -p "Admin password (8+ chars, 1 capital, 1 number): " ADMIN_PASS </dev/tty; echo
    read -r -s -p "Repeat password: " P2 </dev/tty; echo
    [ "$ADMIN_PASS" = "$P2" ] && [[ ${#ADMIN_PASS} -ge 8 && "$ADMIN_PASS" =~ [A-Z] && "$ADMIN_PASS" =~ [0-9] && "$ADMIN_PASS" != *\'* ]] && break
    warn "Passwords differ, are too weak, or contain a quote mark. Try again."
  done
  NODE_NAME=$(ask "Node name [Node1]: "); NODE_NAME=${NODE_NAME:-Node1}
  while true; do
    TZONE=$(ask "Timezone [Africa/Lagos]: "); TZONE=${TZONE:-Africa/Lagos}
    [ -f "/usr/share/zoneinfo/$TZONE" ] || ! [ -d /usr/share/zoneinfo ] && break
    warn "Unknown timezone '$TZONE'. Use a name like Africa/Lagos or Europe/London."
  done
  DB_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
  umask 077
  cat > "$CONF" <<EOF
MODE='$MODE'
PANEL_DOMAIN='$PANEL_DOMAIN'
NGROK_TOKEN='$NGROK_TOKEN'
ADMIN_EMAIL='$ADMIN_EMAIL'
ADMIN_USER='$ADMIN_USER'
ADMIN_PASS='$ADMIN_PASS'
NODE_NAME='$NODE_NAME'
TZONE='$TZONE'
DB_PASS='$DB_PASS'
EOF
  umask 022
fi
MODE=${MODE:-ngrok}
[ -n "${PANEL_DOMAIN:-}" ] || die "Saved answers are incomplete. Delete $CONF and run again."
[ "$MODE" = domain ] || [ -n "${NGROK_TOKEN:-}" ] || die "Saved answers are incomplete. Delete $CONF and run again."
PANEL_URL="https://$PANEL_DOMAIN"
PANEL=/var/www/pterodactyl
NGROK_CFG="$DATA/conf/ngrok.yml"

# ---------- 1. packages --------------------------------------------------------
say "1/10 Installing system packages (a few minutes)"
if ! dpkg -s php$PHPV-fpm mariadb-server nginx redis-server >/dev/null 2>&1; then
  run apt-get update || die "apt update failed"
  run apt-get -y install apt-utils curl ca-certificates gnupg lsb-release tar unzip git procps python3 || die "base packages failed"
  if [ "$ID" = ubuntu ]; then
    run apt-get -y install software-properties-common || die "base packages failed"
    LC_ALL=C.UTF-8 run add-apt-repository -y ppa:ondrej/php || die "could not add the PHP repository"
  else
    # Debian does not carry PHP 8.3, so use the Sury repository
    run apt-get -y install apt-transport-https || die "base packages failed"
    curl -fsSL -o /tmp/sury-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb >>"$LOG" 2>&1 || die "could not download the PHP repository key"
    dpkg -i /tmp/sury-keyring.deb >>"$LOG" 2>&1 || die "could not install the PHP repository key"
    echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/sury-php.list
  fi
  run apt-get update
  run apt-get -y install php$PHPV php$PHPV-cli php$PHPV-fpm php$PHPV-common php$PHPV-mysql php$PHPV-mbstring php$PHPV-bcmath php$PHPV-xml php$PHPV-curl php$PHPV-zip php$PHPV-gd php$PHPV-intl mariadb-server nginx redis-server || die "PHP/MariaDB/nginx/redis install failed"
fi
if [ "$MODE" = domain ] && ! command -v certbot >/dev/null; then
  run apt-get -y install certbot || die "could not install certbot"
fi
if ! command -v composer >/dev/null; then
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >>"$LOG" 2>&1 || die "composer install failed"
fi

# ---------- 2. keep important data on the data disk ----------------------------
say "2/10 Linking data folders"
link_dir() {  # link_dir <real location> <expected path>
  local real=$1 path=$2
  mkdir -p "$real"
  if [ -L "$path" ]; then :; elif [ -d "$path" ] && [ -n "$(ls -A "$path" 2>/dev/null)" ] && [ -z "$(ls -A "$real" 2>/dev/null)" ]; then
    cp -a "$path/." "$real/" && rm -rf "$path" && ln -s "$real" "$path"
  else
    rm -rf "$path" 2>/dev/null; mkdir -p "$(dirname "$path")"; ln -sfn "$real" "$path"
  fi
}
if [ "$SYSTEMD" = 1 ]; then
  say "   (normal server: data stays in the usual folders)"
  mkdir -p "$PANEL" /etc/pterodactyl /var/lib/pterodactyl
else
  service mariadb stop >>"$LOG" 2>&1 || true
  link_dir "$DATA/mysql" /var/lib/mysql
  link_dir "$DATA/www/pterodactyl" "$PANEL"
  link_dir "$DATA/conf/pterodactyl" /etc/pterodactyl
  link_dir "$DATA/pterodactyl" /var/lib/pterodactyl
  chown -R mysql:mysql "$DATA/mysql" 2>/dev/null || true
fi

# ---------- 3. start base services --------------------------------------------
say "3/10 Starting MariaDB, Redis, PHP"
mkdir -p /run/mysqld /run/php; chown mysql:mysql /run/mysqld
if [ "$SYSTEMD" = 0 ] && [ -z "$(ls -A "$DATA/mysql" 2>/dev/null)" ]; then mysql_install_db --user=mysql --datadir="$DATA/mysql" >>"$LOG" 2>&1 || true; fi
service mariadb start >>"$LOG" 2>&1; service redis-server start >>"$LOG" 2>&1; service php$PHPV-fpm start >>"$LOG" 2>&1
for i in $(seq 1 30); do mysql -u root -e 'SELECT 1' >/dev/null 2>&1 && break; sleep 1; done
mysql -u root -e 'SELECT 1' >/dev/null 2>&1 || die "MariaDB did not start"

# ---------- 4. database --------------------------------------------------------
say "4/10 Database"
mysql -u root >>"$LOG" 2>&1 <<EOF || die "could not create the database"
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
ALTER USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

# ---------- 5. panel files -----------------------------------------------------
say "5/10 Panel files (a few minutes)"
if [ ! -f "$PANEL/artisan" ]; then
  cd "$PANEL" || die "no panel folder"
  curl -fL -o panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz >>"$LOG" 2>&1 || die "could not download the panel"
  tar -xzf panel.tar.gz && rm -f panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/
fi
cd "$PANEL" || die "no panel folder"
[ -f .env ] || cp .env.example .env
[ -d vendor ] || { composer install --no-dev --optimize-autoloader >>"$LOG" 2>&1 || die "composer install failed"; }
grep -q '^APP_KEY=base64' .env || php artisan key:generate --force >>"$LOG" 2>&1

# ---------- 6. panel settings, admin, location, node ---------------------------
say "6/10 Panel settings, admin account, location and node"
if [ ! -f "$STATE/panel.done" ]; then
  php artisan p:environment:setup --author="$ADMIN_EMAIL" --url="$PANEL_URL" --timezone="$TZONE" \
     --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-pass=null --redis-port=6379 \
     --settings-ui=true --telemetry=0 >>"$LOG" 2>&1 || die "p:environment:setup failed"
  php artisan p:environment:database --host=127.0.0.1 --port=3306 --database=panel --username=pterodactyl --password="$DB_PASS" >>"$LOG" 2>&1 || die "p:environment:database failed"
  sed -i 's/^MAIL_MAILER=.*/MAIL_MAILER=log/' .env
  php artisan migrate --seed --force >>"$LOG" 2>&1 || die "database migration failed"
  php artisan p:user:make --email="$ADMIN_EMAIL" --username="$ADMIN_USER" --name-first=Admin --name-last=User --password="$ADMIN_PASS" --admin=1 >>"$LOG" 2>&1 || die "could not create the admin user"
  touch "$STATE/panel.done"
fi
chown -R www-data:www-data "$PANEL/"

if [ ! -f "$STATE/node.done" ]; then
  php artisan p:location:make --short=NG --long=Nigeria >>"$LOG" 2>&1 || warn "location may already exist"
  LOC_ID=$(mysql -N -e 'SELECT id FROM panel.locations ORDER BY id LIMIT 1')
  RAM_MB=$(free -m | awk '/^Mem:/{print $2}'); NODE_MEM=$(( RAM_MB * 80 / 100 ))
  AVAIL_MB=$(df -m --output=avail "$DATA" | tail -1 | tr -d ' '); NODE_DISK=$(( AVAIL_MB * 85 / 100 ))
  php artisan p:node:make --name="$NODE_NAME" --description="Main node" --locationId="$LOC_ID" --fqdn="$PANEL_DOMAIN" \
     --public=1 --scheme=https --proxy=1 --maintenance=0 --maxMemory="$NODE_MEM" --overallocateMemory=0 \
     --maxDisk="$NODE_DISK" --overallocateDisk=0 --uploadSize=100 --daemonListeningPort=443 --daemonSFTPPort=2022 \
     --daemonBase=/var/lib/pterodactyl/volumes >>"$LOG" 2>&1 || die "could not create the node"
  touch "$STATE/node.done"
fi
NODE_ID=$(mysql -N -e 'SELECT id FROM panel.nodes ORDER BY id LIMIT 1')
[ -n "$NODE_ID" ] || die "node was not created"

# ports for servers (non-fatal)
COUNT=$(mysql -N -e "SELECT COUNT(*) FROM panel.allocations WHERE node_id=$NODE_ID")
if [ "${COUNT:-0}" -eq 0 ]; then
  mysql >>"$LOG" 2>&1 -e "INSERT INTO panel.allocations (node_id, ip, port, created_at, updated_at) WITH RECURSIVE s(n) AS (SELECT 20000 UNION ALL SELECT n+1 FROM s WHERE n<20500) SELECT $NODE_ID, '0.0.0.0', n, NOW(), NOW() FROM s" \
    || warn "could not add ports 20000-20500; add them in Admin > Nodes > Allocation"
fi

# ---------- 7. nginx, cron, queue ---------------------------------------------
say "7/10 Web server and background workers"
rm -f /etc/nginx/sites-enabled/default
IFS= read -r -d '' NGBODY <<'EOF'
    root /var/www/pterodactyl/public;
    index index.php;
    client_max_body_size 100m;
    location ~ ^/(api/servers|api/system|api/update|api/transfers|api/deauthorize-user|download|upload)(/|$) {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_buffering off;
        client_max_body_size 0;
        proxy_read_timeout 3600s;
    }
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTPS on;
    }
    location ~ /\.ht {
        deny all;
    }
EOF
NGBODY=${NGBODY//php8.3-fpm.sock/php$PHPV-fpm.sock}
if [ "$MODE" = domain ]; then
  CERT=/etc/letsencrypt/live/$PANEL_DOMAIN/fullchain.pem
  if [ ! -f "$CERT" ]; then
    say "Getting a free HTTPS certificate for $PANEL_DOMAIN"
    service nginx stop >>"$LOG" 2>&1
    certbot certonly --standalone -d "$PANEL_DOMAIN" --agree-tos -m "$ADMIN_EMAIL" -n >>"$LOG" 2>&1 \
      || die "certificate failed. Check that $PANEL_DOMAIN points to this VPS and ports 80 and 443 are open"
  fi
  cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80 default_server;
    server_name _;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl default_server;
    server_name $PANEL_DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$PANEL_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PANEL_DOMAIN/privkey.pem;
$NGBODY
}
EOF
else
  cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80 default_server;
    server_name _;
$NGBODY
}
EOF
fi
ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
nginx -t >>"$LOG" 2>&1 || die "nginx config test failed"
service nginx restart >>"$LOG" 2>&1 || service nginx start >>"$LOG" 2>&1

cat > "$DATA/ptero-cron.sh" <<'EOF'
while true; do
  runuser -u www-data -- php /var/www/pterodactyl/artisan schedule:run > /dev/null 2>&1
  [ "$(date +%H%M)" = 0330 ] && command -v certbot >/dev/null && certbot renew -q --pre-hook "service nginx stop" --post-hook "service nginx start" >/dev/null 2>&1
  sleep 60
done
EOF

# ---------- 8. Docker ---------------------------------------------------------
say "8/10 Docker (a few minutes)"
FRESH_DOCKER=0
if ! command -v docker >/dev/null; then
  FRESH_DOCKER=1
  run apt-get -y remove docker-compose-v2
  curl -fsSL https://get.docker.com | CHANNEL=stable sh >>"$LOG" 2>&1 || warn "docker script reported an error; trying to repair"
  dpkg --remove --force-remove-reinstreq docker-compose-plugin >>"$LOG" 2>&1 || true
  run apt-get -y --fix-broken install
  run dpkg --configure -a
fi
command -v docker >/dev/null || die "Docker did not install"
if [ "$SYSTEMD" = 1 ]; then
  # normal server: Docker runs as a system service and starts by itself after a reboot
  systemctl enable --now docker >>"$LOG" 2>&1 || true
  for i in $(seq 1 40); do docker info >/dev/null 2>&1 && break; sleep 1; done
else
  if [ "$FRESH_DOCKER" = 1 ]; then
    service docker stop >>"$LOG" 2>&1 || true
    pkill dockerd 2>/dev/null; pkill containerd 2>/dev/null; sleep 3
  fi
  if ! docker info >/dev/null 2>&1; then
    nohup dockerd --data-root="$DATA/docker" >/var/log/dockerd.log 2>&1 &
    for i in $(seq 1 40); do docker info >/dev/null 2>&1 && break; sleep 1; done
  fi
fi
docker info >/dev/null 2>&1 || die "Docker daemon did not start (see /var/log/dockerd.log or: journalctl -u docker)"
docker run --rm hello-world >>"$LOG" 2>&1 || die "Docker cannot run containers (see $LOG)"

# ---------- 9. Wings ----------------------------------------------------------
say "9/10 Wings"
if [ ! -x /usr/local/bin/wings ]; then
  ARCH=amd64; [ "$(uname -m)" = aarch64 ] && ARCH=arm64
  curl -fL -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$ARCH" >>"$LOG" 2>&1 || die "could not download Wings"
  chmod u+x /usr/local/bin/wings
fi
mkdir -p /etc/pterodactyl
( cd "$PANEL" && php artisan p:node:configuration "$NODE_ID" > /etc/pterodactyl/config.yml 2>>"$LOG" ) || die "could not generate the Wings config"
grep -q '^api:' /etc/pterodactyl/config.yml || die "Wings config looks wrong (see /etc/pterodactyl/config.yml)"
# Wings listens on 8080 locally (nginx forwards to it); the panel itself reaches it on 443 through ngrok
sed -i '/^api:/,/^[a-z]/ s/^\( *port: *\)[0-9]\+/\18080/' /etc/pterodactyl/config.yml

# ---------- 10. ngrok ---------------------------------------------------------
if [ "$MODE" = ngrok ]; then
say "10/10 ngrok"
if ! command -v ngrok >/dev/null; then
  curl -fL -o /root/ngrok.tgz https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz >>"$LOG" 2>&1 || die "could not download ngrok"
  tar -xzf /root/ngrok.tgz -C /usr/local/bin && rm -f /root/ngrok.tgz
fi
ngrok config add-authtoken "$NGROK_TOKEN" --config "$NGROK_CFG" >>"$LOG" 2>&1 || die "ngrok token was rejected"
else
say "10/10 (skipped: you use your own domain, no ngrok needed)"
fi

# ---------- start everything ---------------------------------------------------
START="$DATA/start-ptero.sh"
if [ "$SYSTEMD" = 1 ]; then
  # Normal server: systemd starts everything by itself at boot and restarts it if it stops.
  cat > /etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service mariadb.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  cat > /etc/systemd/system/ptero-schedule.service <<EOF
[Unit]
Description=Pterodactyl scheduled tasks

[Service]
Type=oneshot
User=www-data
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan schedule:run
EOF
  cat > /etc/systemd/system/ptero-schedule.timer <<EOF
[Unit]
Description=Run Pterodactyl scheduled tasks every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF
  cat > /etc/systemd/system/wings.service <<EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service nginx.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  if [ "$MODE" = domain ]; then
    # free certificate renewal: certbot's own timer runs it, nginx is stopped for a moment while it does
    mkdir -p /etc/letsencrypt/renewal-hooks/pre /etc/letsencrypt/renewal-hooks/post
    printf '#!/bin/sh\nsystemctl stop nginx\n' > /etc/letsencrypt/renewal-hooks/pre/ptero.sh
    printf '#!/bin/sh\nsystemctl start nginx\n' > /etc/letsencrypt/renewal-hooks/post/ptero.sh
    chmod +x /etc/letsencrypt/renewal-hooks/pre/ptero.sh /etc/letsencrypt/renewal-hooks/post/ptero.sh
    systemctl enable --now certbot.timer >>"$LOG" 2>&1 || true
  fi
  systemctl daemon-reload
  systemctl enable --now mariadb redis-server php$PHPV-fpm nginx >>"$LOG" 2>&1
  systemctl enable --now pteroq.service ptero-schedule.timer >>"$LOG" 2>&1
  systemctl enable wings.service >>"$LOG" 2>&1
  [ "$MODE" = ngrok ] && warn "ngrok mode on a normal server: start ngrok yourself (ngrok http 80 --url=$PANEL_DOMAIN) or use the own-domain option."
  # Wings needs the panel to answer first
  for i in $(seq 1 60); do curl -sf -o /dev/null $PANEL_URL/auth/login && break; sleep 2; done
  systemctl restart wings.service >>"$LOG" 2>&1
  cat > "$START" <<EOF
#!/usr/bin/env bash
# Everything starts by itself at boot. This only restarts it by hand if you ever need to.
systemctl restart mariadb redis-server php$PHPV-fpm nginx pteroq wings
EOF
else
  cat > "$START" <<EOF
#!/usr/bin/env bash
# Starts everything. Safe to run more than once.
mkdir -p /run/mysqld /run/php; chown mysql:mysql /run/mysqld
service mariadb start; service redis-server start; service php$PHPV-fpm start; service nginx start
pgrep -f ptero-cron.sh >/dev/null || nohup bash $DATA/ptero-cron.sh >/dev/null 2>&1 &
pgrep -f 'queue:work' >/dev/null || nohup runuser -u www-data -- php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3 >/var/log/pteroq.log 2>&1 &
[ "$MODE" = ngrok ] && { pgrep -x ngrok >/dev/null || nohup ngrok http 80 --log=stdout --config $NGROK_CFG --url=$PANEL_DOMAIN >/var/log/ngrok.log 2>&1 & }
pgrep -x dockerd >/dev/null || nohup dockerd --data-root=$DATA/docker >/var/log/dockerd.log 2>&1 &
for i in \$(seq 1 40); do docker info >/dev/null 2>&1 && break; sleep 1; done
for i in \$(seq 1 60); do curl -sf -o /dev/null $PANEL_URL/auth/login && break; sleep 2; done
pgrep -x wings >/dev/null || nohup wings >/var/log/wings.log 2>&1 &
EOF
  chmod +x "$START"
  bash "$START" >>"$LOG" 2>&1
fi
chmod +x "$START"
for i in $(seq 1 30); do [ "$(curl -s -o /dev/null -w %{http_code} http://127.0.0.1:8080/api/system)" = 401 ] && break; sleep 2; done

# ---------- checks -------------------------------------------------------------
say "Checking"
OK=1
c1=$(curl -s -o /dev/null -w '%{http_code}' "$PANEL_URL/auth/login"); [ "$c1" = 200 ] && echo "panel:           OK" || { echo "panel:           FAIL ($c1)"; OK=0; }
c2=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/api/system); [ "$c2" = 401 ] && echo "wings (local):  OK" || { echo "wings (local):  FAIL ($c2)"; OK=0; }
if [ "$MODE" = ngrok ]; then
  curl -s localhost:4040/api/tunnels | grep -q "$PANEL_DOMAIN" && echo "ngrok tunnel:   OK" || { echo "ngrok tunnel:   FAIL (see /var/log/ngrok.log)"; OK=0; }
fi
c3=$(curl -s -o /dev/null -w '%{http_code}' "$PANEL_URL/api/system"); [ "$c3" = 401 ] && echo "wings via domain: OK" || { echo "wings via domain: unexpected ($c3) - wait a minute and check the node heart"; }

cat <<EOF

=============================================================================
 DONE. Panel: $PANEL_URL   (login: $ADMIN_EMAIL)
 $( [ "$SYSTEMD" = 1 ] && echo "Everything starts by itself after a reboot. To restart by hand: bash $START" || echo "After any restart run:   bash $START" )
 Saved answers and DB password: $CONF  (keep private)

 STILL TO DO BY HAND (panel pages):
  1. Admin > Nests > Create "Bots", then Import Egg (Node.js and Python):
     https://raw.githubusercontent.com/pterodactyl/generic-eggs/main/nodejs/egg-node-js-generic.json
     https://raw.githubusercontent.com/pterodactyl/generic-eggs/main/python/egg-python-generic.json
  2. Admin > Application API > Create (Read & Write on everything). Copy the ptla_ key.
  3. Admin > Nodes: the heart should turn green within a minute.
  4. Put the key and https://$PANEL_DOMAIN in your TCPANEL config.js.
=============================================================================
EOF
[ "$OK" = 1 ] || warn "Some checks failed. Look at the lines marked FAIL and $LOG"
