#!/usr/bin/env bash
# Access WordPress through the load balancer and show which server answered.
. "$(dirname "$0")/lib/common.sh"

ALB_DNS=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
  --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || echo None)
[ "$ALB_DNS" != None ] || die "Load balancer missing. Run: make elb"
BASE="http://$ALB_DNS"

log "GET $BASE/ x ${REQUESTS:=8}"
for i in $(seq 1 "$REQUESTS"); do
  headers=$(curl -s -o /dev/null -D - --max-time 10 "$BASE/" || true)
  code=$(sed -n '1s/^HTTP[^ ]* \([0-9]*\).*/\1/p' <<<"$headers")
  server=$(grep -i '^x-served-by:' <<<"$headers" | cut -d' ' -f2- | tr -d '\r')
  printf '  #%-2s HTTP %s  served by %s\n' "$i" "${code:-???}" "${server:-?}"
done

title=$(curl -fsS --max-time 10 "$BASE/" | sed -n 's:.*<title>\(.*\)</title>.*:\1:p' | head -1 || true)
ok "Title: ${title:-<none>}"
ok "Open:  $BASE/"
