#!/bin/bash
set -e

echo "=== Authentik setup helper ==="

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE=".env"
COMPOSE_FILE="docker-compose.yml"

########################################
# Basic tool checks
########################################

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is required but not installed."
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required but not installed."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not installed."
  exit 1
fi

if command -v docker compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  COMPOSE_CMD=""
  echo "WARNING: docker compose / docker-compose not found."
  echo "         I can still generate secrets and check versions, but not start containers."
fi

########################################
# Ensure .env exists
########################################

if [[ ! -f "$ENV_FILE" ]]; then
  echo ".env not found – creating new .env ..."
  touch "$ENV_FILE"
fi

########################################
# Ask for public Authentik domain (for initial setup URL)
########################################

DEFAULT_AUTH_DOMAIN="auth.example.com"

EXISTING_AUTH_HOST=$(grep -E '^AUTHENTIK_HOST=' "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2-)
if [[ -n "$EXISTING_AUTH_HOST" ]]; then
  DEFAULT_AUTH_DOMAIN="$EXISTING_AUTH_HOST"
fi

echo ""
read -rp "Authentik public domain (used for initial setup URL) [${DEFAULT_AUTH_DOMAIN}]: " AUTH_DOMAIN
AUTH_DOMAIN=${AUTH_DOMAIN:-$DEFAULT_AUTH_DOMAIN}

# Optionally store/update AUTHENTIK_HOST in .env
if grep -qE '^AUTHENTIK_HOST=' "$ENV_FILE"; then
  sed -i "s|^AUTHENTIK_HOST=.*$|AUTHENTIK_HOST=${AUTH_DOMAIN}|" "$ENV_FILE"
else
  echo "AUTHENTIK_HOST=${AUTH_DOMAIN}" >> "$ENV_FILE"
fi

########################################
# Generate secrets and write to .env
########################################

PG_PASS=$(openssl rand -base64 36 | tr -d '\n')
AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')

echo ""
echo "Generating secrets for .env ..."
echo "  PG_PASS              = [hidden]"
echo "  AUTHENTIK_SECRET_KEY = [hidden]"

# Remove old entries if present
sed -i '/^PG_PASS=/d' "$ENV_FILE"
sed -i '/^AUTHENTIK_SECRET_KEY=/d' "$ENV_FILE"

# Append new ones
echo "PG_PASS=${PG_PASS}" >> "$ENV_FILE"
echo "AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}" >> "$ENV_FILE"

echo "Updated .env with new secrets."

########################################
# Check Authentik image tag vs latest release
########################################

echo ""
echo "Checking currently used Authentik image tag (if any) ..."

CURRENT_TAG=""
CURRENT_IMAGE=""

# 1) Try to detect from running containers
if command -v docker >/dev/null 2>&1; then
  # Grep containers that look like Authentik (server / worker / outpost, etc.)
  CURRENT_IMAGE=$(docker ps --format '{{.Image}}' | grep -E 'authentik|goauthentik' | head -n1 || true)
fi

if [[ -n "$CURRENT_IMAGE" ]]; then
  # Extract tag (part after last colon); this assumes no registry port in image URL
  CURRENT_TAG="${CURRENT_IMAGE##*:}"
  echo "Running Authentik container detected:"
  echo "  Image: ${CURRENT_IMAGE}"
  echo "  Tag:   ${CURRENT_TAG}"
else
  echo "No running Authentik container detected."
  echo "Trying to guess tag from docker-compose.yml ..."
  if [[ -f "$COMPOSE_FILE" ]]; then
    # Extract first Authentik image line
    CURRENT_IMAGE=$(grep -E 'image:.*authentik|goauthentik' "$COMPOSE_FILE" | head -n1 | sed -E 's/.*image:\s*//')
    if [[ -n "$CURRENT_IMAGE" ]]; then
      CURRENT_TAG="${CURRENT_IMAGE##*:}"
      echo "Found Authentik image in compose file:"
      echo "  Image: ${CURRENT_IMAGE}"
      echo "  Tag:   ${CURRENT_TAG}"
    else
      echo "No Authentik image found in compose file."
    fi
  else
    echo "No ${COMPOSE_FILE} present, skipping tag detection."
  fi
fi

echo ""
echo "Querying latest Authentik release tag from GitHub ..."
LATEST_RAW=$(curl -s https://api.github.com/repos/goauthentik/authentik/releases/latest | jq -r '.tag_name')

if [[ "$LATEST_RAW" == "null" || -z "$LATEST_RAW" ]]; then
  echo "WARNING: Could not determine latest release tag from GitHub."
else
  # Strip possible prefixes like "version-" or "v"
  LATEST_TAG=$(echo "$LATEST_RAW" | sed -E 's/^version-//; s/^v//')
  echo "Latest release tag reported by GitHub:"
  echo "  Raw:  ${LATEST_RAW}"
  echo "  Tag:  ${LATEST_TAG}"

  if [[ -n "$CURRENT_TAG" ]]; then
    if [[ "$CURRENT_TAG" == "$LATEST_TAG" ]]; then
      echo ""
      echo "OK: Your Authentik tag (${CURRENT_TAG}) matches the latest release."
    else
      echo ""
      echo "NOTE: Your Authentik tag appears to be different from the latest release."
      echo "  Current tag: ${CURRENT_TAG}"
      echo "  Latest tag:  ${LATEST_TAG}"
      echo "If you want to upgrade, adjust the tag in your docker-compose.yml"
      echo "accordingly and re-deploy."
    fi
  else
    echo ""
    echo "No current Authentik tag could be detected from running containers or compose."
    echo "Latest release tag is: ${LATEST_TAG}"
  fi
fi

########################################
# Optionally start Authentik stack
########################################

if [[ -n "$COMPOSE_CMD" && -f "$COMPOSE_FILE" ]]; then
  echo ""
  read -rp "Start/Restart Authentik with '${COMPOSE_CMD} up -d'? [y/N]: " START_ANSWER
  START_ANSWER=${START_ANSWER:-N}

  if [[ "$START_ANSWER" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Starting Authentik stack using ${COMPOSE_CMD} up -d ..."
    $COMPOSE_CMD up -d
    echo "Authentik stack is starting in the background."
  else
    echo "Skipping container start. You can start Authentik manually with:"
    echo "  ${COMPOSE_CMD} up -d"
  fi
else
  echo ""
  echo "No compose command or ${COMPOSE_FILE} found – skipping container start."
fi

########################################
# Initial setup URL
########################################

INITIAL_SETUP_PATH="/if/flow/initial-setup/"
INITIAL_SETUP_URL="https://${AUTH_DOMAIN}${INITIAL_SETUP_PATH}"

echo ""
echo "============================================================"
echo "Authentik initial setup URL:"
echo "  ${INITIAL_SETUP_URL}"
echo "Open this in your browser once the container is up."
echo "============================================================"