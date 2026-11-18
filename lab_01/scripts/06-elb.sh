#!/usr/bin/env bash
# Application Load Balancer (ELB) in front of the two web servers.
. "$(dirname "$0")/lib/common.sh"
load_state   # VPC/subnets + ALB_SG, WEB_1_ID, WEB_2_ID from the earlier scripts

# 1. Target group: the list of web servers the ALB forwards to, plus the
#    health check. "/" answers 302 before WordPress is installed, 200 after.
TG_ARN=$(aws elbv2 create-target-group --name "$TG_NAME" \
  --protocol HTTP --port 80 --vpc-id "$VPC_ID" --target-type instance \
  --health-check-path / --matcher HttpCode=200-399 \
  --health-check-interval-seconds 15 --healthy-threshold-count 2 \
  --tags "Key=Project,Value=$PROJECT" \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
ok "Target group = $TG_NAME"

aws elbv2 register-targets --target-group-arn "$TG_ARN" \
  --targets "Id=$WEB_1_ID" "Id=$WEB_2_ID"
ok "Registered targets: $WEB_1_ID $WEB_2_ID"

# 2. The load balancer itself, spanning both subnets.
ALB_ARN=$(aws elbv2 create-load-balancer --name "$ALB_NAME" \
  --type application --scheme internet-facing --ip-address-type ipv4 \
  --subnets "$SUBNET_1" "$SUBNET_2" --security-groups "$ALB_SG" \
  --tags "Key=Name,Value=$ALB_NAME" "Key=Project,Value=$PROJECT" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)
ok "Load balancer = $ALB_NAME"

log "Waiting for the load balancer to be active..."
aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN"

# 3. Listener: HTTP :80 -> forward to the target group.
LISTENER_ARN=$(aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP --port 80 \
  --default-actions "Type=forward,TargetGroupArn=$TG_ARN" \
  --query 'Listeners[0].ListenerArn' --output text)
ok "Listener HTTP:80 -> $TG_NAME"

ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].DNSName' --output text)
ok "Load balancer URL: http://$ALB_DNS/"
save TG_ARN ALB_ARN ALB_DNS
