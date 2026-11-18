#!/usr/bin/env bash
# SSH key pair for the web servers; the private key is saved under .state/.
. "$(dirname "$0")/lib/common.sh"

# AWS returns the private key only once, at creation: save it immediately.
KEY_MATERIAL=$(aws ec2 create-key-pair --key-name "$KEY_NAME" --key-type ed25519 \
  --tag-specifications "ResourceType=key-pair,Tags=[{Key=Project,Value=$PROJECT}]" \
  --query KeyMaterial --output text)
( umask 077; printf '%s\n' "$KEY_MATERIAL" > "$KEY_FILE" )
ok "Key pair $KEY_NAME -> $KEY_FILE"
