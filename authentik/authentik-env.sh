#!/bin/bash
set -e

ENV_FILE=".env"

echo "=== Authentik Secret Generator ==="
echo "Target file: $ENV_FILE"
echo ""

# Create .env if it does not exist
if [[ ! -f "$ENV_FILE" ]]; then
    echo ".env does not exist — creating it..."
    touch "$ENV_FILE"
fi

# Generate secrets
PG_PASS=$(openssl rand -base64 36 | tr -d '\n')
AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')

echo "Generated:"
echo "  PG_PASS=[hidden]"
echo "  AUTHENTIK_SECRET_KEY=[hidden]"
echo ""

# Remove old entries if they exist
sed -i '/^PG_PASS=/d' "$ENV_FILE"
sed -i '/^AUTHENTIK_SECRET_KEY=/d' "$ENV_FILE"

# Append new values
echo "PG_PASS=$PG_PASS" | sudo tee -a "$ENV_FILE" >/dev/null
echo "AUTHENTIK_SECRET_KEY=$AUTHENTIK_SECRET_KEY" | sudo tee -a "$ENV_FILE" >/dev/null

echo ""
echo "Secrets written to $ENV_FILE"
echo "Done."