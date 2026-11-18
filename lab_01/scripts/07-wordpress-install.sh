#!/usr/bin/env bash
# Run the WordPress installer through the load balancer (equivalent to
# filling in the "Welcome" form at /wp-admin/install.php), then check the site.
. "$(dirname "$0")/lib/common.sh"
load_state   # TG_ARN, ALB_DNS from 06-elb.sh
ensure_secrets

BASE="http://$ALB_DNS"

wait_until "both web servers to be healthy behind the ALB" "$WEB_COUNT" 900 \
  aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$BASE/wp-admin/install.php"; }
wait_until "$BASE to answer" 200 300 http_code

log "Installing WordPress ('$WP_TITLE', admin user '$WP_ADMIN_USER')"
# The install can be saved even if the response is an error (e.g. a 500 from
# the welcome email failing), so judge by the installer's state afterwards.
response=$(curl -sS --max-time 60 "$BASE/wp-admin/install.php?step=2" \
  --data-urlencode "weblog_title=$WP_TITLE" \
  --data-urlencode "user_name=$WP_ADMIN_USER" \
  --data-urlencode "admin_password=$WP_ADMIN_PASSWORD" \
  --data-urlencode "admin_password2=$WP_ADMIN_PASSWORD" \
  --data-urlencode "admin_email=$WP_ADMIN_EMAIL" \
  --data "pw_weak=1&blog_public=0&language=&Submit=Install+WordPress" || true)
grep -q 'Success!' <<<"$response" ||
  curl -fsS --max-time 15 "$BASE/wp-admin/install.php" | grep -q 'Already Installed' || {
  echo "$response" | sed -e 's/<[^>]*>//g' | grep -v '^[[:space:]]*$' | tail -20 >&2
  die "WordPress installation did not report success"
}
ok "WordPress installed"

title=$(curl -fsS --max-time 15 "$BASE/" | sed -n 's:.*<title>\(.*\)</title>.*:\1:p' | head -1)
[ -n "$title" ] || die "Home page did not return a title"
ok "Home page title: $title"

cat <<EOF

  WordPress is ready
  ------------------
  Site:     $BASE/
  Admin:    $BASE/wp-admin/
  User:     $WP_ADMIN_USER
  Password: $WP_ADMIN_PASSWORD   (stored in .state/secrets.env)

EOF
