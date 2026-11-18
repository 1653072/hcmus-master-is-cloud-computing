#!/bin/bash
# WordPress web-server bootstrap, run once as EC2 user-data on Amazon Linux 2023.
#
# scripts/05-ec2.sh prepends these variables when it renders the user-data:
#   EFS_ID DB_HOST DB_NAME DB_USER DB_PASSWORD WP_*_KEY WP_*_SALT
# Every server gets the same salts, so login cookies work on both of them.
#
# Log on the VM: /var/log/wordpress-bootstrap.log
set -euo pipefail
exec > >(tee -a /var/log/wordpress-bootstrap.log) 2>&1

WEB_ROOT=/var/www/html
WP_CONTENT=$WEB_ROOT/wp-content
step() { echo; echo "=== [$(date '+%F %T')] $*"; }

step "1/7 Mount the network filesystem (EFS $EFS_ID) at $WP_CONTENT"
dnf install -y amazon-efs-utils
mkdir -p "$WP_CONTENT"
grep -q "^$EFS_ID:" /etc/fstab || echo "$EFS_ID:/ $WP_CONTENT efs _netdev,tls,nofail 0 0" >> /etc/fstab
for _ in $(seq 1 30); do
  mountpoint -q "$WP_CONTENT" && break
  mount "$WP_CONTENT" || sleep 10
done
mountpoint -q "$WP_CONTENT" || { echo "EFS mount failed"; exit 1; }
df -h "$WP_CONTENT"

step "2/7 Install Apache and PHP"
dnf install -y httpd php php-fpm php-mysqlnd php-gd php-mbstring php-xml php-opcache

step "3/7 Download and extract the latest WordPress release"
curl -fsSL --retry 5 -o /tmp/wordpress.tar.gz https://wordpress.org/latest.tar.gz
rm -rf /tmp/wordpress /tmp/wp-content-seed
tar -xzf /tmp/wordpress.tar.gz -C /tmp
mv /tmp/wordpress/wp-content /tmp/wp-content-seed
cp -a /tmp/wordpress/. "$WEB_ROOT"/
# wp-content lives on EFS: the first server to grab the lock seeds it,
# the other waits until seeding is finished.
if mkdir "$WP_CONTENT/.seed-lock" 2>/dev/null; then
  echo "Seeding wp-content on EFS"
  cp -a /tmp/wp-content-seed/. "$WP_CONTENT"/
  touch "$WP_CONTENT/.seeded"
else
  echo "Another server is seeding wp-content; waiting"
  for _ in $(seq 1 60); do [ -f "$WP_CONTENT/.seeded" ] && break; sleep 5; done
  [ -f "$WP_CONTENT/.seeded" ] || { echo "wp-content was never seeded"; exit 1; }
fi
grep "wp_version =" "$WEB_ROOT/wp-includes/version.php"

step "4/7 Configure WordPress to use RDS ($DB_HOST)"
cat > "$WEB_ROOT/wp-config.php" <<EOF
<?php
define( 'DB_NAME',     '$DB_NAME' );
define( 'DB_USER',     '$DB_USER' );
define( 'DB_PASSWORD', '$DB_PASSWORD' );
define( 'DB_HOST',     '$DB_HOST' );
define( 'DB_CHARSET',  'utf8mb4' );
define( 'DB_COLLATE',  '' );

define( 'AUTH_KEY',         '$WP_AUTH_KEY' );
define( 'SECURE_AUTH_KEY',  '$WP_SECURE_AUTH_KEY' );
define( 'LOGGED_IN_KEY',    '$WP_LOGGED_IN_KEY' );
define( 'NONCE_KEY',        '$WP_NONCE_KEY' );
define( 'AUTH_SALT',        '$WP_AUTH_SALT' );
define( 'SECURE_AUTH_SALT', '$WP_SECURE_AUTH_SALT' );
define( 'LOGGED_IN_SALT',   '$WP_LOGGED_IN_SALT' );
define( 'NONCE_SALT',       '$WP_NONCE_SALT' );

\$table_prefix = 'wp_';

define( 'WP_DEBUG', false );
define( 'FS_METHOD', 'direct' );

if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOF
chown -R apache:apache "$WEB_ROOT"
chmod 640 "$WEB_ROOT/wp-config.php"

step "5/7 Configure Apache"
imds() {
  local token
  token=$(curl -fsS -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')
  curl -fsS -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254/latest/meta-data/$1"
}
INSTANCE_ID=$(imds instance-id)
AZ=$(imds placement/availability-zone)
cat > /etc/httpd/conf.d/wordpress.conf <<EOF
<Directory "$WEB_ROOT">
    AllowOverride All
</Directory>
# Shows which server answered a request (see: make verify)
Header always set X-Served-By "$INSTANCE_ID ($AZ)"
EOF

step "6/7 Start Apache and PHP-FPM"
systemctl enable --now php-fpm httpd

step "7/7 Local smoke test"
for _ in $(seq 1 10); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost/wp-admin/install.php || true)
  echo "GET /wp-admin/install.php -> HTTP $code"
  [ "$code" = 200 ] && break
  sleep 5
done

step "Bootstrap finished on $INSTANCE_ID ($AZ)"
