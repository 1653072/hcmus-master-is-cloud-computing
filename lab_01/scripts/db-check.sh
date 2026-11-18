#!/usr/bin/env bash
# Prove WordPress uses the RDS database:
#   1. read the seeded posts back from EACH web server directly (bypassing the
#      ALB round-robin); neither VM runs MySQL, so identical data on both can
#      only come from the shared RDS database;
#   2. show RDS-side metrics: write and network activity from the web servers.
. "$(dirname "$0")/lib/common.sh"

ALB_DNS=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
  --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || echo None)
[ "$ALB_DNS" != None ] || die "Load balancer missing. Run: make up"
DNS=$ALB_DNS
TAG=lab01-seed

DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" \
  --query 'DBInstances[0].Endpoint.Address' --output text)
DB_ENGINE=$(aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" \
  --query 'DBInstances[0].[Engine,EngineVersion]' --output text | tr '\t' ' ')
ok "RDS endpoint: $DB_ENDPOINT ($DB_ENGINE)"

tag_id=$(curl -fsS --max-time 15 "http://$DNS/?rest_route=/wp/v2/tags&slug=$TAG&_fields=id" \
  | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
[ -n "$tag_id" ] || die "No seeded posts yet. Run: make seed"

# Fetch through the ALB until both servers have answered at least once.
log "Reading seeded posts from each web server"
seen=""
for _ in $(seq 1 20); do
  headers=$(mktemp)
  body=$(curl -fsS --max-time 15 -D "$headers" \
    "http://$DNS/?rest_route=/wp/v2/posts&tags=$tag_id&per_page=100&_fields=id,title")
  server=$(grep -i '^x-served-by:' "$headers" | cut -d' ' -f2 | tr -d '\r')
  rm -f "$headers"
  case " $seen " in *" $server "*) continue ;; esac
  seen="$seen $server"
  titles=$(grep -o '"rendered":"[^"]*"' <<<"$body" | cut -d'"' -f4)
  n=$(grep -c . <<<"$titles" || true)
  echo "  --- $server returned $n posts:"
  sed 's/^/      /' <<<"$titles"
  [ "$(wc -w <<<"$seen")" -ge "$WEB_COUNT" ] && break
done
[ "$(wc -w <<<"$seen")" -ge "$WEB_COUNT" ] || warn "Only reached:$seen"

log "RDS metrics, last 30 minutes (CloudWatch)"
start=$(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '30 min ago' +%Y-%m-%dT%H:%M:%SZ)
end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# (DatabaseConnections is usually 0: WordPress connects only for the duration
#  of each request, which per-minute samples rarely catch.)
for metric in WriteIOPS NetworkReceiveThroughput NetworkTransmitThroughput; do
  METRIC_MAX=$(aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name "$metric" \
    --dimensions "Name=DBInstanceIdentifier,Value=$DB_IDENTIFIER" \
    --start-time "$start" --end-time "$end" --period 300 --statistics Maximum \
    --query 'max(Datapoints[].Maximum)' --output text)
  [ "$METRIC_MAX" != None ] && METRIC_MAX=$(printf '%.1f' "$METRIC_MAX") || METRIC_MAX=n/a
  printf '  %-26s max %s\n' "$metric" "$METRIC_MAX"
done

ok "Same posts on every web server + write/network activity on RDS => WordPress is using RDS."
echo "  In the browser: wp-admin > Tools > Site Health > Info > Database shows the RDS host."
