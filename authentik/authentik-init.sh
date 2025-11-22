#!/bin/bash
set -e

echo "=== Authentik init helper ==="

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
  echo "         I can still generate/update .env, but cannot start containers."
fi

########################################
# Helper: update or add key=value in .env
########################################

update_env_var() {
  local key="$1"
  local value="$2"

  if [[ -z "$key" ]]; then
    return 1
  fi

  # Remove existing line(s) starting with KEY=
  sed -i "/^${key}=.*/d" "$ENV_FILE"
  # Append new value
  echo "${key}=${value}" >> "$ENV_FILE"
}

########################################
# Helper: detect base tag from docker-compose.yml
# Logic:
#   - image: ghcr.io/goauthentik/server:2025.10.2
#         → BASE_COMPOSE_TAG=2025.10.2
#   - image: ghcr.io/goauthentik/server:${AUTHENTIK_TAG:-2025.10.2}
#         → BASE_COMPOSE_TAG=2025.10.2
#   - image: ghcr.io/goauthentik/server:${AUTHENTIK_TAG}
#         → BASE_COMPOSE_TAG="" (unknown, purely env-driven)
########################################

detect_compose_tag() {
  local img_line image tag_expr default_tag

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    return 0
  fi

  # Find first Authentik image line
  img_line=$(grep -E 'image:.*authentik|goauthentik' "$COMPOSE_FILE" | head -n1 || true)
  if [[ -z "$img_line" ]]; then
    return 0
  fi

  # Strip leading "image:" and spaces
  image=$(echo "$img_line" | sed -E 's/.*image:\s*//')

  # Get the part after the last colon
  tag_expr="${image##*:}"

  # Handle cases:
  # 1) ${AUTHENTIK_TAG:-2025.10.2}
  # 2) ${AUTHENTIK_TAG-2025.10.2}
  # 3) ${AUTHENTIK_TAG}
  # 4) plain 2025.10.2

  if [[ "$tag_expr" =~ ^\$\{AUTHENTIK_TAG(:-|\-)([^}]*)\}$ ]]; then
    # Pattern with default, e.g. ${AUTHENTIK_TAG:-2025.10.2}
    # Extract default part
    default_tag="${BASH_REMATCH[2]}"
    BASE_COMPOSE_TAG="$default_tag"
  elif [[ "$tag_expr" =~ ^\$\{AUTHENTIK_TAG\}$ ]]; then
    # Pure env-driven, no default
    BASE_COMPOSE_TAG=""
  else
    # Plain tag
    BASE_COMPOSE_TAG="$tag_expr"
  fi
}

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

EXISTING_AUTH_HOST=$(grep -E '^AUTHENTIK_HOST=' "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- || true)
if [[ -n "$EXISTING_AUTH_HOST" ]]; then
  DEFAULT_AUTH_DOMAIN="$EXISTING_AUTH_HOST"
fi

echo ""
read -rp "Authentik public domain (used for initial setup URL) [${DEFAULT_AUTH_DOMAIN}]: " AUTH_DOMAIN
AUTH_DOMAIN=${AUTH_DOMAIN:-$DEFAULT_AUTH_DOMAIN}

update_env_var "AUTHENTIK_HOST" "$AUTH_DOMAIN"

########################################
# Generate secrets and write to .env
########################################

PG_PASS=$(openssl rand -base64 36 | tr -d '\n')
AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')

echo ""
echo "Generating secrets for .env ..."
echo "  PG_PASS              = [hidden]"
echo "  AUTHENTIK_SECRET_KEY = [hidden]"

update_env_var "PG_PASS" "$PG_PASS"
update_env_var "AUTHENTIK_SECRET_KEY" "$AUTHENTIK_SECRET_KEY"

echo "Updated .env with new secrets."

########################################
# Read AUTHENTIK_TAG from .env (override)
########################################

CURRENT_CONFIG_TAG=$(grep -E '^AUTHENTIK_TAG=' "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- || true)
if [[ -n "$CURRENT_CONFIG_TAG" ]]; then
  echo ""
  echo "AUTHENTIK_TAG currently set in .env: ${CURRENT_CONFIG_TAG}"
else
  echo ""
  echo "AUTHENTIK_TAG is not set in .env yet."
fi

########################################
# Detect base tag from docker-compose.yml
########################################

BASE_COMPOSE_TAG=""
detect_compose_tag

if [[ -n "$BASE_COMPOSE_TAG" ]]; then
  echo "Base tag from docker-compose.yml (image line): ${BASE_COMPOSE_TAG}"
else
  echo "No static tag could be deduced from docker-compose.yml (image may be purely env-driven)."
fi

########################################
# Decide effective current tag
# Priority:
#   1) AUTHENTIK_TAG in .env
#   2) base tag from compose (if any)
########################################

EFFECTIVE_CURRENT_TAG=""
if [[ -n "$CURRENT_CONFIG_TAG" ]]; then
  EFFECTIVE_CURRENT_TAG="$CURRENT_CONFIG_TAG"
  EFFECTIVE_SOURCE="AUTHENTIK_TAG in .env"
elif [[ -n "$BASE_COMPOSE_TAG" ]]; then
  EFFECTIVE_CURRENT_TAG="$BASE_COMPOSE_TAG"
  EFFECTIVE_SOURCE="docker-compose.yml image tag"
else
  EFFECTIVE_SOURCE="(none)"
fi

if [[ -n "$EFFECTIVE_CURRENT_TAG" ]]; then
  echo ""
  echo "Effective current Authentik tag (priority: .env > compose):"
  echo "  Source: ${EFFECTIVE_SOURCE}"
  echo "  Tag:    ${EFFECTIVE_CURRENT_TAG}"
else
  echo ""
  echo "No effective current tag could be determined (.env + compose)."
fi

########################################
# Check latest Authentik release tag from GitHub
########################################

echo ""
echo "Querying latest Authentik release tag from GitHub ..."
LATEST_RAW=$(curl -s https://api.github.com/repos/goauthentik/authentik/releases/latest | jq -r '.tag_name')

LATEST_TAG=""
if [[ "$LATEST_RAW" == "null" || -z "$LATEST_RAW" ]]; then
  echo "WARNING: Could not determine latest release tag from GitHub."
else
  # Strip 'version/' and leading 'v' if present
  LATEST_TAG="${LATEST_RAW#version/}"
  LATEST_TAG="${LATEST_TAG#v}"

  echo "Latest upstream tag:"
  echo "  Raw:   ${LATEST_RAW}"
  echo "  Clean: ${LATEST_TAG}"
fi

########################################
# Offer to update AUTHENTIK_TAG in .env
########################################

if [[ -n "$LATEST_TAG" ]]; then
  echo ""

  if [[ -n "$EFFECTIVE_CURRENT_TAG" ]]; then
    echo "Comparing effective current tag with latest upstream tag..."
    echo "  Effective: ${EFFECTIVE_CURRENT_TAG}"
    echo "  Latest:    ${LATEST_TAG}"

    if [[ "$EFFECTIVE_CURRENT_TAG" == "$LATEST_TAG" ]]; then
      echo "OK: Effective tag already matches latest upstream."

      # If AUTHENTIK_TAG is not set explicitly, offer to set it
      if [[ -z "$CURRENT_CONFIG_TAG" ]]; then
        read -rp "AUTHENTIK_TAG is not set in .env. Set it to '${LATEST_TAG}' now? [y/N]: " SET_TAG
        SET_TAG=${SET_TAG:-N}
        if [[ "$SET_TAG" =~ ^[Yy]$ ]]; then
          update_env_var "AUTHENTIK_TAG" "$LATEST_TAG"
          echo "AUTHENTIK_TAG set to ${LATEST_TAG} in .env."
        else
          echo "AUTHENTIK_TAG remains unset."
        fi
      fi
    else
      echo ""
      echo "NOTE: Effective tag differs from latest upstream."
      read -rp "Update .env AUTHENTIK_TAG to latest tag '${LATEST_TAG}'? [y/N]: " UPDATE_TAG
      UPDATE_TAG=${UPDATE_TAG:-N}
      if [[ "$UPDATE_TAG" =~ ^[Yy]$ ]]; then
        update_env_var "AUTHENTIK_TAG" "$LATEST_TAG"
        echo "AUTHENTIK_TAG updated to ${LATEST_TAG} in .env."
      else
        echo "AUTHENTIK_TAG not changed."
      fi
    fi
  else
    echo "No effective current tag available."
    echo "Latest upstream tag is: ${LATEST_TAG}"
    read -rp "Write AUTHENTIK_TAG='${LATEST_TAG}' into .env now? [y/N]: " WRITE_TAG
    WRITE_TAG=${WRITE_TAG:-N}
    if [[ "$WRITE_TAG" =~ ^[Yy]$ ]]; then
      update_env_var "AUTHENTIK_TAG" "$LATEST_TAG"
      echo "AUTHENTIK_TAG set to ${LATEST_TAG} in .env."
    else
      echo "AUTHENTIK_TAG remains unset."
    fi
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