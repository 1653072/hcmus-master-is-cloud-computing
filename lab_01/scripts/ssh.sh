#!/usr/bin/env bash
# ssh.sh <n> [command...]: SSH into web server n (1 or 2).
. "$(dirname "$0")/lib/common.sh"

n=${1:-1}
shift || true

INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$PROJECT-web-$n" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId | [0]' --output text)
[ "$INSTANCE_ID" != None ] || die "Web server $n is not running"

PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
[ "$PUBLIC_IP" != None ] || die "Web server $n ($INSTANCE_ID) has no public IP"
[ -f "$KEY_FILE" ] || die "Missing $KEY_FILE"

exec ssh -i "$KEY_FILE" \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="$STATE_DIR/known_hosts" \
  "ec2-user@$PUBLIC_IP" "$@"
