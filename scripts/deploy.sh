#!/usr/bin/env bash
# Deploy one stack from ./stacks/<name> to the VPS and (re)start it.
# Usage: VPS=ubuntu@92.4.74.185 SSH_KEY=~/.ssh/vps_key scripts/deploy.sh <stack>
set -euo pipefail
STACK="${1:?usage: deploy.sh <stack-name>}"
VPS="${VPS:?set VPS=user@host}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
APPS_DIR="${APPS_DIR:-/opt/apps}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new"

[ -f "$ROOT/stacks/$STACK/compose.yaml" ] || { echo "no stacks/$STACK/compose.yaml"; exit 1; }
rsync -az --delete --exclude '.env' -e "$SSH" "$ROOT/stacks/$STACK/" "$VPS:$APPS_DIR/$STACK/"
$SSH "$VPS" "cd $APPS_DIR/$STACK && docker compose pull --quiet && docker compose up -d --remove-orphans && docker compose ps"
