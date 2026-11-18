#!/usr/bin/env bash
# Firewall rules (security groups), chained so each tier only accepts
# traffic from the tier in front of it:
#
#   internet --80--> ALB --80--> web servers --2049--> EFS
#   your IP  --22---------------^           \--3306--> RDS
. "$(dirname "$0")/lib/common.sh"
load_state

# 1. One security group per tier.
log "Creating security groups in $VPC_ID"

ALB_SG=$(aws ec2 create-security-group --vpc-id "$VPC_ID" \
  --group-name "$ALB_SG_NAME" --description "Lab01 ALB: HTTP from the internet" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$ALB_SG_NAME},{Key=Project,Value=$PROJECT}]" \
  --query GroupId --output text)
ok "$ALB_SG_NAME = $ALB_SG"

WEB_SG=$(aws ec2 create-security-group --vpc-id "$VPC_ID" \
  --group-name "$WEB_SG_NAME" --description "Lab01 web servers: HTTP from ALB, SSH from admin" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$WEB_SG_NAME},{Key=Project,Value=$PROJECT}]" \
  --query GroupId --output text)
ok "$WEB_SG_NAME = $WEB_SG"

EFS_SG=$(aws ec2 create-security-group --vpc-id "$VPC_ID" \
  --group-name "$EFS_SG_NAME" --description "Lab01 EFS: NFS from web servers" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$EFS_SG_NAME},{Key=Project,Value=$PROJECT}]" \
  --query GroupId --output text)
ok "$EFS_SG_NAME = $EFS_SG"

DB_SG=$(aws ec2 create-security-group --vpc-id "$VPC_ID" \
  --group-name "$DB_SG_NAME" --description "Lab01 RDS: MySQL from web servers" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$DB_SG_NAME},{Key=Project,Value=$PROJECT}]" \
  --query GroupId --output text)
ok "$DB_SG_NAME = $DB_SG"

save ALB_SG WEB_SG EFS_SG DB_SG

# 2. Inbound rules.
log "Adding rules"

# Internet -> ALB on HTTP
ALB_HTTP_RULE=$(aws ec2 authorize-security-group-ingress --group-id "$ALB_SG" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0 \
  --query 'SecurityGroupRules[0].SecurityGroupRuleId' --output text)
ok "ALB  tcp/80   from 0.0.0.0/0    : $ALB_HTTP_RULE"

# ALB -> web servers on HTTP
WEB_HTTP_RULE=$(aws ec2 authorize-security-group-ingress --group-id "$WEB_SG" \
  --protocol tcp --port 80 --source-group "$ALB_SG" \
  --query 'SecurityGroupRules[0].SecurityGroupRuleId' --output text)
ok "WEB  tcp/80   from $ALB_SG_NAME : $WEB_HTTP_RULE"

# Web servers -> EFS on NFS
EFS_NFS_RULE=$(aws ec2 authorize-security-group-ingress --group-id "$EFS_SG" \
  --protocol tcp --port 2049 --source-group "$WEB_SG" \
  --query 'SecurityGroupRules[0].SecurityGroupRuleId' --output text)
ok "EFS  tcp/2049 from $WEB_SG_NAME : $EFS_NFS_RULE"

# Web servers -> RDS on MySQL
DB_MYSQL_RULE=$(aws ec2 authorize-security-group-ingress --group-id "$DB_SG" \
  --protocol tcp --port 3306 --source-group "$WEB_SG" \
  --query 'SecurityGroupRules[0].SecurityGroupRuleId' --output text)
ok "RDS  tcp/3306 from $WEB_SG_NAME : $DB_MYSQL_RULE"

# Your IP(s) -> web servers on SSH. SSH_CIDR may list several CIDRs; if empty,
# detect your public IP(s) (some ISPs rotate between several).
if [ -z "$SSH_CIDR" ]; then
  SSH_CIDR=$(for _ in 1 2 3 4; do
      curl -fsS --max-time 5 https://checkip.amazonaws.com 2>/dev/null
      curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null; echo
    done | tr -d ' \r' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u | sed 's|$|/32|' | tr '\n' ' ' || true)
fi
[ -n "${SSH_CIDR// /}" ] || warn "Could not detect your public IP; SSH is not opened (set SSH_CIDR)."
for cidr in $(tr ',' ' ' <<<"$SSH_CIDR"); do
  WEB_SSH_RULE=$(aws ec2 authorize-security-group-ingress --group-id "$WEB_SG" \
    --protocol tcp --port 22 --cidr "$cidr" \
    --query 'SecurityGroupRules[0].SecurityGroupRuleId' --output text)
  ok "WEB  tcp/22   from $cidr : $WEB_SSH_RULE"
done
