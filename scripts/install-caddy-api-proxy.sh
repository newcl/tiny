#!/usr/bin/env bash
set -euo pipefail

# Install Caddy on Ubuntu/Debian and configure HTTPS reverse proxy for tiny API.
#
# Defaults:
#   API_DOMAIN=tinyjobsapi.elladali.com
#   API_UPSTREAM=127.0.0.1:8080
#   HEALTH_PATH=/healthz
#
# Usage:
#   chmod +x scripts/install-caddy-api-proxy.sh
#   sudo API_DOMAIN=tinyjobsapi.elladali.com API_UPSTREAM=127.0.0.1:8080 ./scripts/install-caddy-api-proxy.sh

API_DOMAIN="${API_DOMAIN:-tinyjobsapi.elladali.com}"
API_UPSTREAM="${API_UPSTREAM:-127.0.0.1:8080}"
HEALTH_PATH="${HEALTH_PATH:-/healthz}"

as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1"
    exit 1
  }
}

need_cmd curl
need_cmd gpg
need_cmd tee
need_cmd systemctl

echo "[1/8] Installing apt transport dependencies..."
as_root apt-get update -y
as_root apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  debian-keyring \
  debian-archive-keyring \
  apt-transport-https

echo "[2/8] Adding Caddy apt repo key..."
as_root mkdir -p /usr/share/keyrings
curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
  | as_root gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

echo "[3/8] Adding Caddy apt repo source..."
curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt \
  | as_root tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null

echo "[4/8] Installing Caddy..."
as_root apt-get update -y
as_root apt-get install -y caddy

echo "[5/8] Writing Caddyfile for API domain ${API_DOMAIN} -> ${API_UPSTREAM}..."
as_root tee /etc/caddy/Caddyfile >/dev/null <<EOF
${API_DOMAIN} {
  encode gzip zstd
  reverse_proxy ${API_UPSTREAM}
}
EOF

echo "[6/8] Restarting and enabling Caddy..."
as_root systemctl daemon-reload
as_root systemctl enable caddy
as_root systemctl restart caddy

echo "[7/8] Configuring UFW (if enabled)..."
if command -v ufw >/dev/null 2>&1; then
  ufw_status="$(as_root ufw status 2>/dev/null || true)"
  if grep -q "Status: active" <<<"${ufw_status}"; then
    as_root ufw allow 80/tcp
    as_root ufw allow 443/tcp
  else
    echo "UFW installed but not active; skipping firewall rule changes."
  fi
else
  echo "UFW not installed; skipping firewall rule changes."
fi

echo "[8/8] Verifying service and endpoint..."
as_root systemctl --no-pager --full status caddy | sed -n '1,20p'

echo
echo "Attempting HTTPS health check: https://${API_DOMAIN}${HEALTH_PATH}"
if curl -fsS "https://${API_DOMAIN}${HEALTH_PATH}"; then
  echo
  echo "Caddy reverse proxy is ready."
else
  echo
  echo "Health check failed. Verify DNS for ${API_DOMAIN}, Cloudflare proxy status, and API upstream ${API_UPSTREAM}."
  exit 1
fi
