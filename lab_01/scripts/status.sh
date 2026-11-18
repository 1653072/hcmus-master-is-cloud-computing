#!/usr/bin/env bash
# Show the state of every resource of this lab. Read-only.
. "$(dirname "$0")/lib/common.sh"

row() { [ "$2" = None ] && set -- "$1" "-"; printf '  %-16s %s\n' "$1" "${2:--}"; }

echo "Project $PROJECT in $AWS_REGION"

if [ -f "$NETWORK_FILE" ]; then
  . "$NETWORK_FILE"
  row VPC "$VPC_ID"
  row Subnets "$SUBNET_1 ($AZ_1), $SUBNET_2 ($AZ_2)"

  ALB_SG=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
    "Name=group-name,Values=$ALB_SG_NAME" --query 'SecurityGroups[0].GroupId' --output text)
  WEB_SG=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
    "Name=group-name,Values=$WEB_SG_NAME" --query 'SecurityGroups[0].GroupId' --output text)
  EFS_SG=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
    "Name=group-name,Values=$EFS_SG_NAME" --query 'SecurityGroups[0].GroupId' --output text)
  DB_SG=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
    "Name=group-name,Values=$DB_SG_NAME" --query 'SecurityGroups[0].GroupId' --output text)
  row "SG alb" "$ALB_SG"
  row "SG web" "$WEB_SG"
  row "SG efs" "$EFS_SG"
  row "SG db"  "$DB_SG"
else
  row Network "not discovered (make network)"
fi

EFS_ID=$(aws efs describe-file-systems --creation-token "$EFS_TOKEN" \
  --query 'FileSystems[0].FileSystemId' --output text)
if [ "$EFS_ID" != None ]; then
  EFS_STATE=$(aws efs describe-file-systems --file-system-id "$EFS_ID" \
    --query 'FileSystems[0].LifeCycleState' --output text)
  EFS_MOUNT_STATES=$(aws efs describe-mount-targets --file-system-id "$EFS_ID" \
    --query 'MountTargets[].LifeCycleState' --output text | tr '\t' ' ')
  row EFS "$EFS_ID $EFS_STATE, mount targets: ${EFS_MOUNT_STATES:-none}"
else
  row EFS None
fi

DB_INFO=$(aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" \
  --query 'DBInstances[0].[DBInstanceStatus,Engine,EngineVersion,Endpoint.Address]' \
  --output text 2>/dev/null | tr '\t' ' ' || echo None)
row RDS "${DB_INFO:-None}"

WEB_1_INFO=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$PROJECT-web-1" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[0].Instances[0].[InstanceId,State.Name,Placement.AvailabilityZone,PublicIpAddress]' \
  --output text | tr '\t' ' ')
WEB_2_INFO=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$PROJECT-web-2" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[0].Instances[0].[InstanceId,State.Name,Placement.AvailabilityZone,PublicIpAddress]' \
  --output text | tr '\t' ' ')
row "EC2 web-1" "${WEB_1_INFO:-None}"
row "EC2 web-2" "${WEB_2_INFO:-None}"

TG_ARN=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo None)
if [ "$TG_ARN" != None ]; then
  TARGET_HEALTH=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output text | tr '\t\n' ': ')
  row "Target health" "$TARGET_HEALTH"
fi

ALB_DNS=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
  --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || echo None)
[ "$ALB_DNS" != None ] && ALB_DNS="http://$ALB_DNS/"
row ALB "$ALB_DNS"
