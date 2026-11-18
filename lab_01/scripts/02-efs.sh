#!/usr/bin/env bash
# Network filesystem (EFS) with one mount target per subnet. The web servers
# mount it as wp-content so uploads, themes and plugins are shared.
. "$(dirname "$0")/lib/common.sh"
load_state   # VPC/subnets + EFS_SG from 01-security-groups.sh

# 1. The file system.
EFS_ID=$(aws efs create-file-system --creation-token "$EFS_TOKEN" \
  --performance-mode generalPurpose --throughput-mode bursting --encrypted \
  --tags "Key=Name,Value=$PROJECT-efs" "Key=Project,Value=$PROJECT" \
  --query FileSystemId --output text)
ok "EFS = $EFS_ID"
save EFS_ID

wait_until "EFS $EFS_ID to be available" available 300 \
  aws efs describe-file-systems --file-system-id "$EFS_ID" \
    --query 'FileSystems[0].LifeCycleState' --output text

# 2. One mount target in each subnet, so each web server mounts EFS in its own AZ.
MOUNT_TARGET_1=$(aws efs create-mount-target --file-system-id "$EFS_ID" \
  --subnet-id "$SUBNET_1" --security-groups "$EFS_SG" \
  --query MountTargetId --output text)
ok "Mount target 1 = $MOUNT_TARGET_1 ($SUBNET_1)"

MOUNT_TARGET_2=$(aws efs create-mount-target --file-system-id "$EFS_ID" \
  --subnet-id "$SUBNET_2" --security-groups "$EFS_SG" \
  --query MountTargetId --output text)
ok "Mount target 2 = $MOUNT_TARGET_2 ($SUBNET_2)"

wait_until "EFS mount targets to be available" 0 600 \
  aws efs describe-mount-targets --file-system-id "$EFS_ID" \
    --query "length(MountTargets[?LifeCycleState!='available'])" --output text
