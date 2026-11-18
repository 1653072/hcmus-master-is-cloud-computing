#!/usr/bin/env bash
# Pick the network for the lab: the default VPC and two of its subnets in
# different Availability Zones (the ALB and RDS both need two AZs, and each
# web server goes into one of them). Saves the result to .state/network.env.
. "$(dirname "$0")/lib/common.sh"

log "Discovering network in $AWS_REGION"
rm -f "$RESOURCES_FILE"   # a new deployment starts with no saved IDs

# 1. The default VPC (every account has one per region).
VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' --output text)
[ "$VPC_ID" != None ] || die "No default VPC in $AWS_REGION. Create one with: aws ec2 create-default-vpc"

# 2. Its first two subnets, sorted by AZ. A default VPC has exactly one
#    public subnet per AZ, so these are always in two different AZs.
SUBNET_1=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" Name=default-for-az,Values=true \
  --query 'sort_by(Subnets, &AvailabilityZone)[0].SubnetId' --output text)

SUBNET_2=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" Name=default-for-az,Values=true \
  --query 'sort_by(Subnets, &AvailabilityZone)[1].SubnetId' --output text)

# 3. The AZ of each subnet (for display only).
AZ_1=$(aws ec2 describe-subnets --subnet-ids "$SUBNET_1" \
  --query 'Subnets[0].AvailabilityZone' --output text)

AZ_2=$(aws ec2 describe-subnets --subnet-ids "$SUBNET_2" \
  --query 'Subnets[0].AvailabilityZone' --output text)

cat > "$NETWORK_FILE" <<EOF
VPC_ID=$VPC_ID
SUBNET_1=$SUBNET_1
SUBNET_2=$SUBNET_2
AZ_1=$AZ_1
AZ_2=$AZ_2
EOF

ok "VPC      $VPC_ID"
ok "Subnet 1 $SUBNET_1 ($AZ_1)"
ok "Subnet 2 $SUBNET_2 ($AZ_2)"
