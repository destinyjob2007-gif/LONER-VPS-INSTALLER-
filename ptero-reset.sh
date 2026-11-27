set -u
[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }
echo "This will DELETE your Pterodactyl panel, its database and every server inside it."
read -r -p "Type RESET (capital letters) to continue: " a
[ "$a" = RESET ] || { echo "Cancelled. Nothing was changed."; exit 0; }

echo "[1/6] stopping services"
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null; then
  systemctl disable --now wings pteroq ptero-schedule.timer >/dev/null 2>&1
  systemctl stop nginx >/dev/null 2>&1
else
  pkill -f ptero-cron.sh 2>/dev/null; pkill -f 'queue:work' 2>/dev/null; pkill -x wings 2>/dev/null; pkill -x ngrok 2>/dev/null
  service nginx stop >/dev/null 2>&1
fi

echo "[2/6] removing all servers (Docker containers made by the panel)"
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  ids=$(docker ps -aq 2>/dev/null); [ -n "$ids" ] && docker rm -f $ids >/dev/null 2>&1
  docker network rm pterodactyl_nw >/dev/null 2>&1
fi

echo "[3/6] dropping the panel database"
if command -v mysql >/dev/null; then
  (service mariadb start || systemctl start mariadb) >/dev/null 2>&1
  mysql -e "DROP DATABASE IF EXISTS panel; DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1'; FLUSH PRIVILEGES;" 2>/dev/null || echo "   (could not reach the database, skipping)"
fi

echo "[4/6] removing panel, Wings and server files"
rm -rf /var/www/pterodactyl /etc/pterodactyl /var/lib/pterodactyl
rm -f /usr/local/bin/wings
rm -f /etc/systemd/system/wings.service /etc/systemd/system/pteroq.service /etc/systemd/system/ptero-schedule.service /etc/systemd/system/ptero-schedule.timer
rm -f /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf
rm -f /etc/letsencrypt/renewal-hooks/pre/ptero.sh /etc/letsencrypt/renewal-hooks/post/ptero.sh
command -v systemctl >/dev/null && systemctl daemon-reload >/dev/null 2>&1

echo "[5/6] clearing the installer's saved progress"
for d in /var/lib/ptero-data /data; do
  [ -d "$d/.ptero-install" ] || continue
  rm -rf "$d/.ptero-install" "$d/conf" "$d/www" "$d/pterodactyl" "$d/ptero-cron.sh" "$d/start-ptero.sh"
done

echo "[6/6] done"
echo
echo "Clean. Now run the installer again from the top:"
echo "  curl -fsSL https://raw.githubusercontent.com/destinyjob2007-gif/LONER-VPS-INSTALLER-/main/ptero-install.sh -o ptero-install.sh && bash ptero-install.sh"
