#!/bin/bash
set -e

########################################
# Basic tool checks
########################################

if ! which curl >/dev/null 2>&1; then
  echo "This script uses curl to fetch OpenID configuration from the IDP."
  echo "Please install curl and re-run the script: https://curl.se/"
  echo ""
  exit 1
fi

if ! which jq >/dev/null 2>&1; then
  echo "This script uses jq to load OpenID configuration from the IDP."
  echo "Please install jq and re-run the script: https://stedolan.github.io/jq/"
  echo ""
  exit 1
fi

if ! which envsubst >/dev/null 2>&1; then
  echo "envsubst is needed to run this script."
  if [[ $(uname) == "Darwin" ]]; then
    echo "You can install it with Homebrew (https://brew.sh):"
    echo "  brew install gettext"
  else
    if which apt-get >/dev/null 2>&1; then
      echo "You can install it by running:"
      echo "  apt-get update && apt-get install gettext-base"
    else
      echo "You can install it by installing the package 'gettext' with your package manager."
    fi
  fi
  exit 1
fi

########################################
# Load configuration
########################################

if [[ ! -f "setup.env" ]]; then
  echo "setup.env not found. Please copy setup.env.example to setup.env and adjust values."
  exit 1
fi

if [[ ! -f "base.setup.env" ]]; then
  echo "base.setup.env not found. Make sure it exists in the current directory."
  exit 1
fi

# User configuration
source setup.env
# Defaults and derived values
source base.setup.env

if [[ "x-$NETBIRD_DOMAIN" == "x-" ]]; then
  echo "NETBIRD_DOMAIN is not set, please update your setup.env file."
  echo "If you are migrating from old versions, you might need to update your variable prefixes from"
  echo "WIRETRUSTEE_.. to NETBIRD_."
  exit 1
fi

########################################
# Deployment mode
########################################

DEPLOYMENT_MODE="${NETBIRD_DEPLOYMENT_MODE:-standalone}"

case "$DEPLOYMENT_MODE" in
  standalone|proxy_docker|proxy_external|proxy_docker_caddy)
    echo "Using deployment mode: $DEPLOYMENT_MODE"
    ;;
  *)
    echo "Invalid NETBIRD_DEPLOYMENT_MODE='$DEPLOYMENT_MODE'."
    echo "Valid values: standalone, proxy_docker, proxy_external, proxy_docker_caddy"
    exit 1
    ;;
esac

########################################
# Store engine: only sqlite or postgres
########################################

case "$NETBIRD_STORE_CONFIG_ENGINE" in
  sqlite|postgres)
    echo "Store engine: $NETBIRD_STORE_CONFIG_ENGINE"
    ;;
  *)
    echo "Unsupported NETBIRD_STORE_CONFIG_ENGINE='$NETBIRD_STORE_CONFIG_ENGINE'."
    echo "Only 'sqlite' and 'postgres' are supported."
    exit 1
    ;;
esac

########################################
# Built-in Postgres support
########################################
# If NETBIRD_STORE_CONFIG_ENGINE=postgres:
#   - NETBIRD_USE_INTERNAL_POSTGRES=true  → internal postgres service in compose + auto DSN
#   - NETBIRD_USE_INTERNAL_POSTGRES=false → NO postgres service in compose, DSN must be provided

: "${NETBIRD_USE_INTERNAL_POSTGRES:=true}"

# Defaults for internal Postgres
: "${NETBIRD_POSTGRES_DB:=netbird}"
: "${NETBIRD_POSTGRES_USER:=netbird}"

if [[ -z "$NETBIRD_POSTGRES_PASSWORD" ]]; then
  NETBIRD_POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=')
fi

export NETBIRD_POSTGRES_DB NETBIRD_POSTGRES_USER NETBIRD_POSTGRES_PASSWORD NETBIRD_USE_INTERNAL_POSTGRES

if [[ "$NETBIRD_STORE_CONFIG_ENGINE" == "postgres" ]]; then
  if [[ "$NETBIRD_USE_INTERNAL_POSTGRES" == "true" ]]; then
    # Internal Postgres container, auto-generated DSN if not set
    if [[ -z "$NETBIRD_STORE_ENGINE_POSTGRES_DSN" ]]; then
      NETBIRD_STORE_ENGINE_POSTGRES_DSN="host=postgres user=$NETBIRD_POSTGRES_USER password=$NETBIRD_POSTGRES_PASSWORD dbname=$NETBIRD_POSTGRES_DB port=5432 sslmode=disable"
      echo "Postgres store enabled. Using internal Postgres instance with DSN:"
      echo "  $NETBIRD_STORE_ENGINE_POSTGRES_DSN"
    else
      echo "Postgres store enabled. Using custom DSN with internal Postgres service."
    fi
    export NETBIRD_STORE_ENGINE_POSTGRES_DSN
  else
    # External Postgres: no internal Postgres service, DSN is required
    if [[ -z "$NETBIRD_STORE_ENGINE_POSTGRES_DSN" ]]; then
      echo "NETBIRD_STORE_CONFIG_ENGINE=postgres and NETBIRD_USE_INTERNAL_POSTGRES=false,"
      echo "but NETBIRD_STORE_ENGINE_POSTGRES_DSN is not set."
      echo "Please set NETBIRD_STORE_ENGINE_POSTGRES_DSN to point to your external Postgres instance."
      exit 1
    fi
    echo "Postgres store enabled. Using external Postgres DSN:"
    echo "  $NETBIRD_STORE_ENGINE_POSTGRES_DSN"
    export NETBIRD_STORE_ENGINE_POSTGRES_DSN
  fi
fi

########################################
# Local development (localhost)
########################################

if [[ $NETBIRD_DOMAIN == "localhost" || $NETBIRD_DOMAIN == "127.0.0.1" ]]; then
  export NETBIRD_MGMT_SINGLE_ACCOUNT_MODE_DOMAIN="netbird.selfhosted"
  export NETBIRD_MGMT_API_ENDPOINT=http://$NETBIRD_DOMAIN:$NETBIRD_MGMT_API_PORT
  unset NETBIRD_MGMT_API_CERT_FILE
  unset NETBIRD_MGMT_API_CERT_KEY_FILE
fi

########################################
# TURN configuration
########################################

# TURN password
if [[ "x-$TURN_PASSWORD" == "x-" ]]; then
  export TURN_PASSWORD=$(openssl rand -base64 32 | sed 's/=//g')
fi

TURN_EXTERNAL_IP_CONFIG="#"

if [[ "x-$NETBIRD_TURN_EXTERNAL_IP" == "x-" ]]; then
  echo "Discovering server's public IP for TURN..."
  IP=$(curl -s -4 https://jsonip.com | jq -r '.ip')
  if [[ "x-$IP" != "x-" ]]; then
    TURN_EXTERNAL_IP_CONFIG="external-ip=$IP"
  else
    echo "Unable to discover server's public IP."
  fi
else
  echo "${NETBIRD_TURN_EXTERNAL_IP}" | egrep '([0-9]{1,3}\.){3}[0-9]{1,3}$' >/dev/null
  if [[ $? -eq 0 ]]; then
    echo "Using provided server's public IP for TURN."
    TURN_EXTERNAL_IP_CONFIG="external-ip=$NETBIRD_TURN_EXTERNAL_IP"
  else
    echo "Provided NETBIRD_TURN_EXTERNAL_IP '$NETBIRD_TURN_EXTERNAL_IP' is invalid, please correct it and try again."
    exit 1
  fi
fi

export TURN_EXTERNAL_IP_CONFIG

########################################
# Relay secret
########################################

if [[ "x-$NETBIRD_RELAY_AUTH_SECRET" == "x-" ]]; then
  export NETBIRD_RELAY_AUTH_SECRET=$(openssl rand -base64 32 | sed 's/=//g')
fi

########################################
# Artifacts & data paths
########################################

artifacts_path="./artifacts"
mkdir -p "$artifacts_path"

###############################################################################
# Prepare data directories inside ./artifacts
###############################################################################

# Base data root inside artifacts
DATA_ROOT="$artifacts_path/data"

MGMT_DATA_DIR="$DATA_ROOT/management"
SIGNAL_DATA_DIR="$DATA_ROOT/signal"
LETSENCRYPT_DATA_DIR="$DATA_ROOT/letsencrypt"
# Important: we do NOT create postgres data dir here to avoid permission issues
# POSTGRES_DATA_DIR="$DATA_ROOT/postgres"

mkdir -p "$MGMT_DATA_DIR" "$SIGNAL_DATA_DIR" "$LETSENCRYPT_DATA_DIR"

# Make sure config files exist in ./artifacts so Docker bind mounts a file, not a directory
[ ! -f "$artifacts_path/management.json" ] && touch "$artifacts_path/management.json"
[ ! -f "$artifacts_path/turnserver.conf" ] && touch "$artifacts_path/turnserver.conf"
[ ! -f "$artifacts_path/Caddyfile" ] && touch "$artifacts_path/Caddyfile"

export DATA_PATH MGMT_DATA_PATH SIGNAL_DATA_PATH LETSENCRYPT_DATA_PATH POSTGRES_DATA_PATH

########################################
# OIDC configuration & backward compatibility
########################################

if [[ -z "${NETBIRD_AUTH_OIDC_CONFIGURATION_ENDPOINT}" ]]; then
  if [[ -z "${NETBIRD_AUTH0_DOMAIN}" ]]; then
    echo "NETBIRD_AUTH_OIDC_CONFIGURATION_ENDPOINT must be set in setup.env."
    exit 1
  fi

  echo "It seems like you provided an old setup.env file."
  echo "Since release v0.8.10, a new set of properties was introduced."
  echo "The script is backward compatible and will continue automatically."
  echo "In future versions it will be deprecated. See: https://netbird.io/docs/getting-started/self-hosting"

  export NETBIRD_AUTH_OIDC_CONFIGURATION_ENDPOINT="https://${NETBIRD_AUTH0_DOMAIN}/.well-known/openid-configuration"
  export NETBIRD_USE_AUTH0="true"
  export NETBIRD_AUTH_AUDIENCE=${NETBIRD_AUTH0_AUDIENCE}
  export NETBIRD_AUTH_CLIENT_ID=${NETBIRD_AUTH0_CLIENT_ID}
fi

echo "Loading OpenID configuration from ${NETBIRD_AUTH_OIDC_CONFIGURATION_ENDPOINT}..."
curl "${NETBIRD_AUTH_OIDC_CONFIGURATION_ENDPOINT}" -q -o ${artifacts_path}/openid-configuration.json

export NETBIRD_AUTH_AUTHORITY=$(jq -r '.issuer' ${artifacts_path}/openid-configuration.json)
export NETBIRD_AUTH_JWT_CERTS=$(jq -r '.jwks_uri' ${artifacts_path}/openid-configuration.json)
export NETBIRD_AUTH_TOKEN_ENDPOINT=$(jq -r '.token_endpoint' ${artifacts_path}/openid-configuration.json)
export NETBIRD_AUTH_DEVICE_AUTH_ENDPOINT=$(jq -r '.device_authorization_endpoint' ${artifacts_path}/openid-configuration.json)
export NETBIRD_AUTH_PKCE_AUTHORIZATION_ENDPOINT=$(jq -r '.authorization_endpoint' ${artifacts_path}/openid-configuration.json)

# Device Authorization Flow
if [[ -n "${NETBIRD_AUTH_DEVICE_AUTH_CLIENT_ID}" ]]; then
  export NETBIRD_AUTH_DEVICE_AUTH_PROVIDER="hosted"
fi

# PKCE token source
if [ "$NETBIRD_TOKEN_SOURCE" = "idToken" ]; then
  export NETBIRD_AUTH_PKCE_USE_ID_TOKEN=true
fi

########################################
# Deployment-mode-specific networking
########################################

case "$DEPLOYMENT_MODE" in
  standalone)
    : "${NETBIRD_DISABLE_LETSENCRYPT:=false}"
    export NETBIRD_DISABLE_LETSENCRYPT

    if [[ -n "$NETBIRD_MGMT_API_CERT_FILE" && -n "$NETBIRD_MGMT_API_CERT_KEY_FILE" ]]; then
      export NETBIRD_SIGNAL_PROTOCOL="https"
    fi

    : "${NETBIRD_SIGNAL_PUBLIC_PORT:=$NETBIRD_SIGNAL_PORT}"
    ;;

  proxy_docker|proxy_external|proxy_docker_caddy)
    NETBIRD_DISABLE_LETSENCRYPT=true
    export NETBIRD_DISABLE_LETSENCRYPT

    : "${NETBIRD_EXTERNAL_TLS_PORT:=443}"

    : "${NETBIRD_DASHBOARD_INTERNAL_PORT:=80}"
    : "${NETBIRD_SIGNAL_INTERNAL_PORT:=80}"
    : "${NETBIRD_RELAY_INTERNAL_PORT:=33080}"
    : "${NETBIRD_MGMT_INTERNAL_PORT:=${NETBIRD_MGMT_API_PORT:-33073}}"

    export NETBIRD_DASHBOARD_ENDPOINT="https://$NETBIRD_DOMAIN:${NETBIRD_EXTERNAL_TLS_PORT}"
    export NETBIRD_SIGNAL_ENDPOINT="https://$NETBIRD_DOMAIN:${NETBIRD_EXTERNAL_TLS_PORT}"
    export NETBIRD_RELAY_ENDPOINT="rels://$NETBIRD_DOMAIN:${NETBIRD_EXTERNAL_TLS_PORT}/relay"
    export NETBIRD_MGMT_API_ENDPOINT="https://$NETBIRD_DOMAIN:${NETBIRD_EXTERNAL_TLS_PORT}"

    export NETBIRD_SIGNAL_PUBLIC_PORT="$NETBIRD_EXTERNAL_TLS_PORT"
    export NETBIRD_SIGNAL_PROTOCOL="https"

    export NETBIRD_DASHBOARD_PORT="$NETBIRD_DASHBOARD_INTERNAL_PORT"
    export NETBIRD_SIGNAL_PORT="$NETBIRD_SIGNAL_INTERNAL_PORT"
    export NETBIRD_RELAY_PORT="$NETBIRD_RELAY_INTERNAL_PORT"
    export NETBIRD_MGMT_API_PORT="$NETBIRD_MGMT_INTERNAL_PORT"

    unset NETBIRD_LETSENCRYPT_DOMAIN
    unset NETBIRD_MGMT_API_CERT_FILE
    unset NETBIRD_MGMT_API_CERT_KEY_FILE

    echo "Reverse proxy mode ($DEPLOYMENT_MODE) enabled."
    echo "Clients will connect to: https://$NETBIRD_DOMAIN:${NETBIRD_EXTERNAL_TLS_PORT}"

    : "${NETBIRD_REVERSE_PROXY_NETWORK:=reverse_proxy_net}"
    export NETBIRD_REVERSE_PROXY_NETWORK
    ;;
esac

: "${NETBIRD_SIGNAL_PUBLIC_PORT:=$NETBIRD_SIGNAL_PORT}"
export NETBIRD_SIGNAL_PUBLIC_PORT

########################################
# IDP management extra config
########################################

if [ -n "$NETBIRD_MGMT_IDP" ] && [ "$NETBIRD_MGMT_IDP" != "none" ]; then
  EXTRA_CONFIG={}

  for var in ${!NETBIRD_IDP_MGMT_EXTRA_*}; do
    key=$(
      echo "${var#NETBIRD_IDP_MGMT_EXTRA_}" | awk -F "_" \
        '{for (i=1; i<=NF; i++) {output=output substr($i,1,1) tolower(substr($i,2))} print output}'
    )
    value="${!var}"

    echo "$var"
    EXTRA_CONFIG=$(jq --arg k "$key" --arg v "$value" '.[$k] = $v' <<<"$EXTRA_CONFIG")
  done

  export NETBIRD_MGMT_IDP
  export NETBIRD_IDP_MGMT_CLIENT_ID
  export NETBIRD_IDP_MGMT_CLIENT_SECRET
  export NETBIRD_IDP_MGMT_EXTRA_CONFIG=$EXTRA_CONFIG
else
  export NETBIRD_IDP_MGMT_EXTRA_CONFIG={}
fi

########################################
# PKCE redirect URLs
########################################

IFS=',' read -r -a REDIRECT_URL_PORTS <<<"$NETBIRD_AUTH_PKCE_REDIRECT_URL_PORTS"
REDIRECT_URLS=""
for port in "${REDIRECT_URL_PORTS[@]}"; do
  REDIRECT_URLS+="\"http://localhost:${port}\","
done
export NETBIRD_AUTH_PKCE_REDIRECT_URLS=${REDIRECT_URLS%,}

########################################
# Audience handling
########################################

if [ "$NETBIRD_DASH_AUTH_USE_AUDIENCE" = "false" ]; then
  export NETBIRD_DASH_AUTH_AUDIENCE=none
  export NETBIRD_AUTH_PKCE_AUDIENCE=
fi

########################################
# Management datastore encryption key
########################################

if test -f 'management.json'; then
  encKey=$(jq -r ".DataStoreEncryptionKey" management.json)
  if [[ "$encKey" != "null" ]]; then
    export NETBIRD_DATASTORE_ENC_KEY=$encKey
  fi
fi

########################################
# Debug print
########################################

env | grep NETBIRD || true

########################################
# Backups of previous artifacts
########################################

bkp_postfix="$(date +%s)"
if test -f "${artifacts_path}/docker-compose.yml"; then
  cp "$artifacts_path/docker-compose.yml" "${artifacts_path}/docker-compose.yml.bkp.${bkp_postfix}"
fi

if test -f "${artifacts_path}/management.json"; then
  cp "$artifacts_path/management.json" "${artifacts_path}/management.json.bkp.${bkp_postfix}"
fi

if test -f "${artifacts_path}/turnserver.conf"; then
  cp "${artifacts_path}/turnserver.conf" "${artifacts_path}/turnserver.conf.bkp.${bkp_postfix}"
fi

########################################
# Render templates (with/without internal Postgres)
########################################

compose_base=""
case "$DEPLOYMENT_MODE" in
  standalone)
    compose_base="docker-compose.standalone"
    ;;
  proxy_docker)
    compose_base="docker-compose.proxy-docker"
    ;;
  proxy_external)
    compose_base="docker-compose.proxy-external"
    ;;
  proxy_docker_caddy)
    compose_base="docker-compose.proxy-docker-caddy"
    ;;
esac

if [[ "$NETBIRD_STORE_CONFIG_ENGINE" == "postgres" && "$NETBIRD_USE_INTERNAL_POSTGRES" == "true" ]]; then
  compose_tmpl="${compose_base}.with-postgres.yml.tmpl"
else
  compose_tmpl="${compose_base}.nopostgres.yml.tmpl"
fi

envsubst <"$compose_tmpl" >"$artifacts_path/docker-compose.yml"
envsubst <management.json.tmpl | jq . >"$artifacts_path/management.json"
envsubst <turnserver.conf.tmpl >"$artifacts_path/turnserver.conf"

# Generate Caddyfile only in proxy_docker_caddy mode
if [[ "$DEPLOYMENT_MODE" == "proxy_docker_caddy" ]]; then
  envsubst <Caddyfile.tmpl >"$artifacts_path/Caddyfile"
  echo "Generated Caddyfile at $artifacts_path/Caddyfile"
fi

echo ""
echo "Generated files in $artifacts_path:"
echo "  - docker-compose.yml (from $compose_tmpl)"
echo "  - management.json"
echo "  - turnserver.conf"
if [[ "$DEPLOYMENT_MODE" == "proxy_docker_caddy" ]]; then
  echo "  - Caddyfile"
fi
echo ""
echo "You can now start NetBird with:"
echo "  docker compose -f $artifacts_path/docker-compose.yml up -d"