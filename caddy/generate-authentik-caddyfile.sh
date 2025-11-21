#!/bin/bash
set -e

# Simple Caddyfile generator for Authentik only.
# Place this script in your Caddy folder (where Caddyfile lives).

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CADDYFILE_PATH="${SCRIPT_DIR}/Caddyfile"

echo "=== Authentik Caddyfile Generator ==="
echo ""

read -rp "Authentik domain (e.g. auth.example.de) [auth.example.de]: " AUTH_DOMAIN
AUTH_DOMAIN=${AUTH_DOMAIN:-auth.example.de}

read -rp "Authentik upstream (Docker service:port, e.g. authentik-server:9000) [authentik-server:9000]: " AUTH_UPSTREAM
AUTH_UPSTREAM=${AUTH_UPSTREAM:-authentik-server:9000}

# Backup existing Caddyfile if present
if [[ -f "$CADDYFILE_PATH" ]]; then
  TS="$(date +%Y%m%d-%H%M%S)"
  BAK="${CADDYFILE_PATH}.bak.${TS}"
  echo ""
  echo "Existing Caddyfile found. Creating backup at:"
  echo "  $BAK"
  cp "$CADDYFILE_PATH" "$BAK"
fi

cat > "$CADDYFILE_PATH" <<EOF
# Security headers (optional)
(security_headers) {
  header * {
    Strict-Transport-Security "max-age=3600"
    X-Content-Type-Options "nosniff"
    X-Frame-Options "SAMEORIGIN"
    Referrer-Policy "strict-origin-when-cross-origin"
    -Server
  }
}

# Authentik
${AUTH_DOMAIN} {
  import security_headers
  reverse_proxy ${AUTH_UPSTREAM}
}
EOF

echo ""
echo "Caddyfile written to: ${CADDYFILE_PATH}"
echo "You can now reload/restart Caddy."