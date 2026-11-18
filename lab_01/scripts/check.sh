#!/usr/bin/env bash
# Pre-flight: required local tools, working AWS credentials, and read access
# to every service the lab uses (catches IAM / SCP / region restrictions early).
. "$(dirname "$0")/lib/common.sh"

for tool in aws curl openssl ssh; do
  command -v "$tool" >/dev/null || die "'$tool' is not installed"
done

IDENTITY=$(aws sts get-caller-identity --query '[Account,Arn]' --output text 2>&1) \
  || die "AWS credentials are not working: $IDENTITY"
ok "AWS identity: $IDENTITY"
ok "Region: $AWS_REGION   Project: $PROJECT"

# Each check runs one read-only call; on failure the variable holds the error.
failed=0
report() {  # report <label> <exit-code> <error-text>
  if [ "$2" = 0 ]; then
    ok "Access: $1"
  else
    warn "No access: $1"
    printf '      %s\n' "$(grep -v '^[[:space:]]*$' <<<"$3" | head -1)" >&2
    failed=1
  fi
}

EC2_CHECK=$(aws ec2 describe-vpcs --max-results 5 --output text 2>&1 >/dev/null) && rc=0 || rc=$?
report "EC2 (VPC, instances, SGs)" "$rc" "$EC2_CHECK"

ELB_CHECK=$(aws elbv2 describe-load-balancers --page-size 1 --output text 2>&1 >/dev/null) && rc=0 || rc=$?
report "ELB (load balancers)" "$rc" "$ELB_CHECK"

RDS_CHECK=$(aws rds describe-db-instances --max-records 20 --output text 2>&1 >/dev/null) && rc=0 || rc=$?
report "RDS (MySQL)" "$rc" "$RDS_CHECK"

EFS_CHECK=$(aws efs describe-file-systems --max-items 1 --output text 2>&1 >/dev/null) && rc=0 || rc=$?
report "EFS (file systems)" "$rc" "$EFS_CHECK"

SSM_CHECK=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --output text 2>&1 >/dev/null) && rc=0 || rc=$?
report "SSM (AMI lookup)" "$rc" "$SSM_CHECK"

if [ "$failed" = 1 ]; then
  die "Missing permissions in $AWS_REGION (profile: ${AWS_PROFILE:-default}).
      'explicit deny in a service control policy' = blocked above IAM: the account is on AWS's
      restricted free plan / not fully activated, or managed by another organization.
      Check Billing console > plan status; IAM policies cannot override it."
fi
