#!/usr/bin/env bash
set -euo pipefail

# Build and install tiny API for systemd usage.
#
# Defaults:
#   SERVICE_NAME=tiny-api
#   INSTALL_BIN=/usr/local/bin/tiny-api
#   PROJECT_DIR=~/git_projects/tiny
#   OUTPUT_BIN=bin/api
#   UNIT_SOURCE=deploy/systemd/tiny-api.service
#   UNIT_TARGET=/etc/systemd/system/tiny-api.service
#
# Usage:
#   chmod +x scripts/build-api-systemd.sh
#   ./scripts/build-api-systemd.sh

SERVICE_NAME="${SERVICE_NAME:-tiny-api}"
INSTALL_BIN="${INSTALL_BIN:-/usr/local/bin/tiny-api}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/git_projects/tiny}"
OUTPUT_BIN="${OUTPUT_BIN:-bin/api}"
UNIT_SOURCE="${UNIT_SOURCE:-deploy/systemd/tiny-api.service}"
UNIT_TARGET="${UNIT_TARGET:-/etc/systemd/system/tiny-api.service}"

if ! command -v go >/dev/null 2>&1; then
  echo "go command not found. Install Go first."
  exit 1
fi

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "Project directory not found: $PROJECT_DIR"
  exit 1
fi

cd "$PROJECT_DIR"
mkdir -p "$(dirname "$OUTPUT_BIN")"

echo "Resolving Go modules..."
go mod tidy

echo "Building Linux API binary..."
ARCH_RAW="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$ARCH_RAW" in
  amd64|x86_64)
    GOARCH_VALUE="amd64"
    ;;
  arm64|aarch64)
    GOARCH_VALUE="arm64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH_RAW"
    exit 1
    ;;
esac

CGO_ENABLED=0 GOOS=linux GOARCH="$GOARCH_VALUE" go build -o "$OUTPUT_BIN" ./cmd/api
chmod 0755 "$OUTPUT_BIN"

echo "Installing API binary to $INSTALL_BIN"
sudo install -m 0755 "$OUTPUT_BIN" "$INSTALL_BIN"

if [[ -f "$UNIT_SOURCE" ]]; then
  echo "Installing systemd unit from $UNIT_SOURCE to $UNIT_TARGET"
  sudo install -m 0644 "$UNIT_SOURCE" "$UNIT_TARGET"
else
  echo "Warning: unit file not found at $UNIT_SOURCE; keeping existing systemd unit"
fi

echo "Reloading and restarting systemd service: $SERVICE_NAME"
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE_NAME"
sudo systemctl status "$SERVICE_NAME" --no-pager -l

echo "Loaded ExecStart:"
sudo systemctl show "$SERVICE_NAME" -p ExecStart

echo
echo "Done. API installed at: $INSTALL_BIN"
echo "Recent logs:"
journalctl -u "$SERVICE_NAME" -n 30 --no-pager
