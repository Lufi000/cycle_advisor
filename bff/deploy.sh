#!/usr/bin/env bash
# Deploy the CycleAdvisor BFF to the production server.
#
# One command does everything: cross-compile → upload via Aliyun Workbench CLI
# → swap binary (old one kept as cycle-advisor-bff.bak) → restart → verify.
# This exists so the deployed binary can never drift from the source again.
#
# Prerequisites on this machine:
#   - Go toolchain
#   - workbench CLI configured (https://workbench-cli.oss-cn-hangzhou.aliyuncs.com/install.sh)
#
# Usage:  bff/deploy.sh            # deploy current working tree
#         INSTANCE_ID=i-xxx bff/deploy.sh
set -euo pipefail

INSTANCE_ID="${INSTANCE_ID:-i-bp1bal3zezgaul8tc0m6}"
REMOTE_DIR="/opt/cycle-advisor-bff"
SERVICE="cycle-advisor-bff"
HEALTH_URL="https://api.smallbeebee.com/health"

cd "$(dirname "$0")"

VERSION="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
if ! git diff --quiet -- . 2>/dev/null; then
    VERSION="${VERSION}-dirty"
fi

OUT="$(mktemp -t cycle-advisor-bff)"
trap 'rm -f "$OUT"' EXIT

echo "==> Building linux/amd64 (version=$VERSION)"
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build \
    -ldflags "-X main.version=$VERSION" \
    -o "$OUT" .

echo "==> Uploading to $INSTANCE_ID:/tmp/cycle-advisor-bff.new"
workbench upload "$OUT" /tmp/cycle-advisor-bff.new --instance-id "$INSTANCE_ID" -f

echo "==> Swapping binary and restarting $SERVICE"
workbench exec --instance-id "$INSTANCE_ID" --timeout 60 --command "
  set -e
  cp $REMOTE_DIR/cycle-advisor-bff $REMOTE_DIR/cycle-advisor-bff.bak
  mv /tmp/cycle-advisor-bff.new $REMOTE_DIR/cycle-advisor-bff
  chmod +x $REMOTE_DIR/cycle-advisor-bff
  systemctl restart $SERVICE
  sleep 1
  systemctl is-active $SERVICE
"

echo "==> Verifying startup log (expect version=$VERSION)"
workbench exec --instance-id "$INSTANCE_ID" --command \
    "journalctl -u $SERVICE -n 1 --no-pager | grep 'listening'"

echo "==> Checking $HEALTH_URL"
curl -fsS --max-time 10 "$HEALTH_URL"
echo
echo "==> Deploy OK (version=$VERSION)"
