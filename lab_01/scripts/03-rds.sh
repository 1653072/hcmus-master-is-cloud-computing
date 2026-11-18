#!/usr/bin/env bash
# MySQL database (RDS), private, reachable only from the web servers.
# Creation usually takes 5-10 minutes.
. "$(dirname "$0")/lib/common.sh"
load_state   # VPC/subnets + DB_SG from 01-security-groups.sh
ensure_secrets

# 1. DB subnet group: tells RDS which subnets (two AZs) it may use.
DB_SUBNET_GROUP_ARN=$(aws rds create-db-subnet-group \
  --db-subnet-group-name "$DB_SUBNET_GROUP" \
  --db-subnet-group-description "Lab01 WordPress DB subnets" \
  --subnet-ids "$SUBNET_1" "$SUBNET_2" \
  --tags "Key=Project,Value=$PROJECT" \
  --query 'DBSubnetGroup.DBSubnetGroupArn' --output text)
ok "DB subnet group = $DB_SUBNET_GROUP"

# 2. The DB instance.
log "Creating RDS MySQL instance $DB_IDENTIFIER ($DB_INSTANCE_CLASS)"
DB_STATUS=$(aws rds create-db-instance \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --engine mysql --db-instance-class "$DB_INSTANCE_CLASS" \
  --allocated-storage "$DB_STORAGE_GB" --storage-type gp3 \
  --db-name "$DB_NAME" \
  --master-username "$DB_USER" --master-user-password "$DB_PASSWORD" \
  --vpc-security-group-ids "$DB_SG" \
  --db-subnet-group-name "$DB_SUBNET_GROUP" \
  --no-publicly-accessible --no-multi-az \
  --backup-retention-period 0 \
  --tags "Key=Name,Value=$DB_IDENTIFIER" "Key=Project,Value=$PROJECT" \
  --query 'DBInstance.DBInstanceStatus' --output text)
ok "RDS $DB_IDENTIFIER status = $DB_STATUS"

log "Waiting for $DB_IDENTIFIER to be available (usually 5-10 min)..."
aws rds wait db-instance-available --db-instance-identifier "$DB_IDENTIFIER"

# 3. The hostname WordPress connects to.
DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" \
  --query 'DBInstances[0].Endpoint.Address' --output text)
ok "RDS endpoint = $DB_ENDPOINT"
save DB_ENDPOINT
