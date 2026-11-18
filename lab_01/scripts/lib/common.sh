# shellcheck shell=bash
# Shared helpers for the lab_01 scripts. Source this file; do not execute it.
# Written for bash 3.2 (macOS default) and newer.
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$LAB_DIR/.state"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

# ---------------------------------------------------------------- config ---
# Precedence: shell environment / make VAR=... > lab_01/.env > config.env defaults.
if [ -f "$LAB_DIR/.env" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    key=${line%%=*}
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [ -z "${!key+x}" ] && eval "export $line"
  done < "$LAB_DIR/.env"
  unset line key
fi
. "$LAB_DIR/config.env"

export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION" AWS_PAGER=""

if ! [[ "$PROJECT" =~ ^[a-z][a-z0-9-]{0,19}$ ]] || [[ "$PROJECT" == *- ]] || [[ "$PROJECT" == *--* ]]; then
  echo "PROJECT='$PROJECT' is invalid: use lowercase letters, digits and single hyphens, max 20 chars." >&2
  exit 1
fi

# Resource names (also used by destroy.sh / status.sh to find them).
ALB_SG_NAME="$PROJECT-alb-sg"
WEB_SG_NAME="$PROJECT-web-sg"
EFS_SG_NAME="$PROJECT-efs-sg"
DB_SG_NAME="$PROJECT-db-sg"
EFS_TOKEN="$PROJECT-efs"
DB_IDENTIFIER="$PROJECT-db"
DB_SUBNET_GROUP="$PROJECT-db-subnets"
KEY_NAME="$PROJECT-key"
KEY_FILE="$STATE_DIR/$KEY_NAME.pem"
TG_NAME="$PROJECT-tg"
ALB_NAME="$PROJECT-alb"
WEB_COUNT=2

NETWORK_FILE="$STATE_DIR/network.env"
SECRETS_FILE="$STATE_DIR/secrets.env"
RESOURCES_FILE="$STATE_DIR/resources.env"   # IDs created by the scripts

# --------------------------------------------------------------- logging ---
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m  ✗\033[0m %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------ wait ---
# wait_until <description> <expected> <timeout-seconds> <command...>
# Polls the command every 10s until its stdout equals <expected>.
wait_until() {
  local desc=$1 want=$2 timeout=$3 start=$SECONDS got
  shift 3
  log "Waiting for $desc (timeout ${timeout}s)..."
  while :; do
    got=$("$@" || true)
    if [ "$got" = "$want" ]; then ok "$desc"; return 0; fi
    if (( SECONDS - start >= timeout )); then
      die "Timed out waiting for $desc (last value: '${got:-<empty>}')"
    fi
    sleep 10
  done
}

# ----------------------------------------------------------------- state ---
# load_state: read the network and every ID saved by the previous scripts.
load_state() {
  [ -f "$NETWORK_FILE" ] || die "Network not discovered yet. Run: make network"
  . "$NETWORK_FILE"
  if [ -f "$RESOURCES_FILE" ]; then . "$RESOURCES_FILE"; fi
}

# save VAR...: append VAR=value to .state/resources.env for the next scripts.
save() {
  local v
  for v in "$@"; do echo "$v=${!v}" >> "$RESOURCES_FILE"; done
}

rand_hex() { openssl rand -hex 64 | cut -c1-"$1"; }

# Generates DB/WordPress passwords and WordPress salts once, then reuses them.
# All values are hex, so they are safe in shell, PHP and RDS passwords.
ensure_secrets() {
  if [ ! -f "$SECRETS_FILE" ]; then
    log "Generating secrets in $SECRETS_FILE"
    (
      umask 077
      {
        echo "DB_PASSWORD=${DB_PASSWORD:-$(rand_hex 32)}"
        echo "WP_ADMIN_PASSWORD=${WP_ADMIN_PASSWORD:-$(rand_hex 20)}"
        for k in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY \
                 AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
          echo "WP_$k=$(rand_hex 64)"
        done
      } > "$SECRETS_FILE"
    )
  fi
  . "$SECRETS_FILE"
}
