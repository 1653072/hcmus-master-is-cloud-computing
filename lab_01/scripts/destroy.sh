#!/usr/bin/env bash
# Delete every AWS resource this lab created, in dependency order.
#
# Resources are found by their deterministic names and the Project tag, so it
# works after a half-finished `make up` and without .state/. Safe to re-run.
#
#   YES=1          skip the confirmation prompt
#   CLEAN_STATE=1  also remove local state (.state/: SSH key, secrets) at the end
. "$(dirname "$0")/lib/common.sh"

if [ "${YES:-}" != 1 ]; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  printf 'Delete ALL "%s" resources in account %s, region %s?\nType the project name to confirm: ' \
    "$PROJECT" "$ACCOUNT_ID" "$AWS_REGION"
  read -r answer
  [ "$answer" = "$PROJECT" ] || die "Aborted"
fi

# ---------------------------------------------------------------------------
# 1. Find everything.
# ---------------------------------------------------------------------------
ALB_ARN=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo None)
TG_ARN=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo None)
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=$PROJECT" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
DB_STATUS=$(aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" \
  --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo None)
EFS_ID=$(aws efs describe-file-systems --creation-token "$EFS_TOKEN" \
  --query 'FileSystems[0].FileSystemId' --output text)
DB_SUBNET_GROUP_ARN=$(aws rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP" \
  --query 'DBSubnetGroups[0].DBSubnetGroupArn' --output text 2>/dev/null || echo None)
KEY_PAIR_ID=$(aws ec2 describe-key-pairs --filters "Name=key-name,Values=$KEY_NAME" \
  --query 'KeyPairs[0].KeyPairId' --output text)
SG_IDS=$(aws ec2 describe-security-groups --filters "Name=tag:Project,Values=$PROJECT" \
  --query 'SecurityGroups[].GroupId' --output text)

# ---------------------------------------------------------------------------
# 2. Start the slow deletions in parallel: load balancer, VMs, database.
# ---------------------------------------------------------------------------
log "Starting deletions"

if [ "$ALB_ARN" != None ]; then
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
  ok "Deleting load balancer $ALB_NAME (its listener goes with it)"
fi

if [ -n "$INSTANCE_IDS" ]; then
  # shellcheck disable=SC2086
  TERMINATING=$(aws ec2 terminate-instances --instance-ids $INSTANCE_IDS \
    --query 'TerminatingInstances[].InstanceId' --output text)
  ok "Terminating instances: $TERMINATING"
fi

case "$DB_STATUS" in
  None) ;;
  deleting) ok "RDS instance $DB_IDENTIFIER already being deleted" ;;
  *)
    if ! DB_DELETE=$(aws rds delete-db-instance --db-instance-identifier "$DB_IDENTIFIER" \
                       --skip-final-snapshot --delete-automated-backups \
                       --query 'DBInstance.DBInstanceStatus' --output text 2>&1); then
      # e.g. still "creating"/"modifying": wait until it settles, then retry.
      grep -q InvalidDBInstanceState <<<"$DB_DELETE" || die "$DB_DELETE"
      log "RDS instance is '$DB_STATUS'; waiting until it can be deleted..."
      aws rds wait db-instance-available --db-instance-identifier "$DB_IDENTIFIER"
      DB_DELETE=$(aws rds delete-db-instance --db-instance-identifier "$DB_IDENTIFIER" \
        --skip-final-snapshot --delete-automated-backups \
        --query 'DBInstance.DBInstanceStatus' --output text)
    fi
    ok "Deleting RDS instance $DB_IDENTIFIER (status: $DB_DELETE)"
    ;;
esac

# ---------------------------------------------------------------------------
# 3. Wait for them, then remove what depended on them.
# ---------------------------------------------------------------------------
if [ "$ALB_ARN" != None ]; then
  log "Waiting for the load balancer to be deleted..."
  aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN"
  ok "Load balancer deleted"
fi

if [ "$TG_ARN" != None ]; then
  # The deleted ALB's listener can keep the target group "in use" for a while.
  start=$SECONDS
  until TG_DELETE=$(aws elbv2 delete-target-group --target-group-arn "$TG_ARN" 2>&1); do
    if grep -q ResourceInUse <<<"$TG_DELETE" && (( SECONDS - start < 300 )); then
      sleep 10
    else
      die "Could not delete target group: $TG_DELETE"
    fi
  done
  ok "Target group $TG_NAME deleted"
fi

if [ -n "$INSTANCE_IDS" ]; then
  log "Waiting for instances to terminate..."
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
  ok "Instances terminated"
fi

if [ "$EFS_ID" != None ]; then
  MOUNT_TARGET_IDS=$(aws efs describe-mount-targets --file-system-id "$EFS_ID" \
    --query 'MountTargets[].MountTargetId' --output text)
  for mount_target in $MOUNT_TARGET_IDS; do
    aws efs delete-mount-target --mount-target-id "$mount_target"
    ok "Deleting EFS mount target $mount_target"
  done
  wait_until "EFS mount targets to be deleted" 0 600 \
    aws efs describe-mount-targets --file-system-id "$EFS_ID" \
      --query 'length(MountTargets)' --output text
  aws efs delete-file-system --file-system-id "$EFS_ID"
  ok "EFS $EFS_ID deleted"
fi

if [ "$DB_STATUS" != None ]; then
  log "Waiting for the RDS instance to be deleted (5-10 min)..."
  aws rds wait db-instance-deleted --db-instance-identifier "$DB_IDENTIFIER"
  ok "RDS instance deleted"
fi

if [ "$DB_SUBNET_GROUP_ARN" != None ]; then
  aws rds delete-db-subnet-group --db-subnet-group-name "$DB_SUBNET_GROUP"
  ok "DB subnet group $DB_SUBNET_GROUP deleted"
fi

if [ "$KEY_PAIR_ID" != None ]; then
  aws ec2 delete-key-pair --key-pair-id "$KEY_PAIR_ID" >/dev/null
  ok "Key pair $KEY_NAME deleted"
fi

# ---------------------------------------------------------------------------
# 4. Security groups. First revoke their ingress rules (they reference each
#    other), then delete them. Network interfaces of the deleted ALB/RDS/EFS
#    can linger for a few minutes, so DependencyViolation is retried.
# ---------------------------------------------------------------------------
for sg in $SG_IDS; do
  RULE_IDS=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$sg" \
    --query 'SecurityGroupRules[?!IsEgress].SecurityGroupRuleId' --output text)
  for rule in $RULE_IDS; do  # one at a time: a rule already gone is not an error
    REVOKE=$(aws ec2 revoke-security-group-ingress --group-id "$sg" \
               --security-group-rule-ids "$rule" 2>&1 >/dev/null) ||
      grep -q 'NotFound' <<<"$REVOKE" || die "$REVOKE"
  done
done

for sg in $SG_IDS; do
  start=$SECONDS
  until SG_DELETE=$(aws ec2 delete-security-group --group-id "$sg" 2>&1); do
    if grep -q DependencyViolation <<<"$SG_DELETE" && (( SECONDS - start < 600 )); then
      sleep 15
    elif grep -q 'InvalidGroup.NotFound' <<<"$SG_DELETE"; then
      break
    else
      die "Could not delete $sg: $SG_DELETE"
    fi
  done
  ok "Security group $sg deleted"
done

# ---------------------------------------------------------------------------
# 5. Check nothing is left, and clean up local files.
# ---------------------------------------------------------------------------
log "Checking for leftovers"
LEFT_ALB=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo None)
LEFT_TG=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo None)
LEFT_EC2=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=$PROJECT" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
LEFT_EFS=$(aws efs describe-file-systems --creation-token "$EFS_TOKEN" \
  --query 'FileSystems[0].FileSystemId' --output text)
LEFT_RDS=$(aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" \
  --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo None)
LEFT_SG=$(aws ec2 describe-security-groups --filters "Name=tag:Project,Values=$PROJECT" \
  --query 'SecurityGroups[].GroupId' --output text)

left=""
[ "$LEFT_ALB" = None ] || left="$left ALB"
[ "$LEFT_TG"  = None ] || left="$left target-group"
[ -z "$LEFT_EC2" ]     || left="$left EC2"
[ "$LEFT_EFS" = None ] || left="$left EFS"
[ "$LEFT_RDS" = None ] || left="$left RDS"
[ -z "$LEFT_SG" ]      || left="$left security-groups"
[ -z "$left" ] || die "Still present:$left. Re-run: make destroy"

rm -f "$KEY_FILE" "$NETWORK_FILE" "$RESOURCES_FILE" "$STATE_DIR/user-data.sh" "$STATE_DIR/known_hosts"
if [ "${CLEAN_STATE:-}" = 1 ]; then
  rm -rf "$STATE_DIR"
  ok "Local state removed"
else
  ok "Kept $SECRETS_FILE (run 'make clean' to remove .state/)"
fi
ok "All '$PROJECT' resources in $AWS_REGION are deleted"
