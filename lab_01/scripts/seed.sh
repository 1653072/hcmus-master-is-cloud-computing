#!/usr/bin/env bash
# Seed sample posts (wordpress/seed-posts.tsv) into the RDS database through
# WordPress's XML-RPC API on the load balancer. Seeded posts get the tag
# "lab01-seed"; re-running skips seeding unless FORCE=1.
. "$(dirname "$0")/lib/common.sh"
ensure_secrets

ALB_DNS=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
  --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || echo None)
[ "$ALB_DNS" != None ] || die "Load balancer missing. Run: make up"
BASE="http://$ALB_DNS"
SEED_FILE="$LAB_DIR/wordpress/seed-posts.tsv"
TAG=lab01-seed

seeded=$(curl -fsS --max-time 15 "$BASE/?rest_route=/wp/v2/tags&slug=$TAG&_fields=count" \
  | sed -n 's/.*"count":\([0-9]*\).*/\1/p')
if [ "${seeded:-0}" -gt 0 ] && [ "${FORCE:-}" != 1 ]; then
  ok "Already seeded ($seeded posts tagged '$TAG'). FORCE=1 adds another copy."
  exit 0
fi

xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<<"$1"; }

new_post() {  # new_post <title> <category> <content> -> post id
  local body response
  body="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<methodCall><methodName>wp.newPost</methodName><params>
 <param><value><int>1</int></value></param>
 <param><value><string>$(xml_escape "$WP_ADMIN_USER")</string></value></param>
 <param><value><string>$WP_ADMIN_PASSWORD</string></value></param>
 <param><value><struct>
  <member><name>post_type</name><value><string>post</string></value></member>
  <member><name>post_status</name><value><string>publish</string></value></member>
  <member><name>post_title</name><value><string>$(xml_escape "$1")</string></value></member>
  <member><name>post_content</name><value><string>$(xml_escape "$3")</string></value></member>
  <member><name>terms_names</name><value><struct>
   <member><name>category</name><value><array><data><value><string>$(xml_escape "$2")</string></value></data></array></value></member>
   <member><name>post_tag</name><value><array><data><value><string>$TAG</string></value></data></array></value></member>
  </struct></value></member>
 </struct></value></param>
</params></methodCall>"
  response=$(curl -sS --max-time 30 -H 'Content-Type: text/xml; charset=UTF-8' \
    --data-binary "$body" "$BASE/xmlrpc.php")
  if grep -q '<fault>' <<<"$response"; then
    die "XML-RPC error for '$1': $(tr -d '\n' <<<"$response" | sed -n 's:.*<name>faultString</name><value><string>\([^<]*\).*:\1:p')"
  fi
  tr -d '\n ' <<<"$response" | sed -n 's:.*<string>\([0-9]*\)</string>.*:\1:p'
}

log "Seeding posts into RDS via $BASE/xmlrpc.php"
count=0
while IFS=$'\t' read -r title category content; do
  [ "$title" = title ] && continue   # header
  [ -n "$title" ] || continue
  id=$(new_post "$title" "$category" "$content")
  ok "Post #$id  [$category] $title"
  count=$((count + 1))
done < "$SEED_FILE"

ok "Seeded $count posts. Check them with: make db-check"
