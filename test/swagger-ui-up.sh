# swagger-ui-up.sh

#!/usr/bin/env bash
set -Eeuo pipefail

################################################################################
# Script Name:  swagger-ui-up.sh
# Author:       Daniel Cruz
# Description:  Launch a temporary Swagger UI container for this API project.
#
#               Modes:
#               - local    -> use api/openapi.json from this repo
#               - prodlike -> same local spec by default, but external TLS paths
#
# Usage:
#   ./test/swagger-ui-up.sh
#   ./test/swagger-ui-up.sh --mode local
#   ./test/swagger-ui-up.sh --mode prodlike -f repo.mydatacenter.io
#   ./test/swagger-ui-up.sh --dry-run
################################################################################

#------------------------------------------------------------------------------
# Script / repo discovery
#------------------------------------------------------------------------------
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

#------------------------------------------------------------------------------
# Defaults
#------------------------------------------------------------------------------
readonly DEFAULT_MODE="local"
readonly DEFAULT_BASE_DIR="/opt/certbot"
readonly DEFAULT_FQDN="repo.example.com"
readonly DEFAULT_HOST_PORT="8443"
readonly DEFAULT_CONTAINER_PORT="8080"
readonly DEFAULT_CONTAINER_NAME="swaggerui"
readonly DEFAULT_SPEC_PATH="${DEFAULT_BASE_DIR}/api/openapi.json"

MODE="${DEFAULT_MODE}"
BASE_DIR="${DEFAULT_BASE_DIR}"
FQDN="${DEFAULT_FQDN}"
HOST_PORT="${DEFAULT_HOST_PORT}"
CONTAINER_PORT="${DEFAULT_CONTAINER_PORT}"
CONTAINER_NAME="${DEFAULT_CONTAINER_NAME}"
SPEC_PATH="${DEFAULT_SPEC_PATH}"
DRY_RUN="false"
DETACH="false"
USE_TLS="true"

# Resolved later
TLS_CERT_FILE=""
TLS_KEY_FILE=""

#------------------------------------------------------------------------------
# UI helpers
#------------------------------------------------------------------------------
info()    { printf "ℹ️  %s\n" "$*"; }
success() { printf "✅ %s\n" "$*"; }
warn()    { printf "⚠️  %s\n" "$*" >&2; }
error()   { printf "❌ %s\n" "$*" >&2; }
die()     { error "$*"; exit 1; }

usage() {
  cat <<EOF
📘 Swagger UI Launcher

Launch a temporary Swagger UI container for the current API project.

Usage:
  ${SCRIPT_NAME} [options]

Options:
  --mode <local|prodlike>   Path resolution mode
                            Default: ${MODE}
  -f <fqdn>                 Domain used to locate Let's Encrypt certs
                            Default: ${FQDN}
  -p <port>                 Host port to expose Swagger UI on
                            Default: ${HOST_PORT}
  --base-dir <path>         External base directory
                            Default: ${BASE_DIR}
  --spec <path>             OpenAPI spec file to serve
                            Default: ${SPEC_PATH}
  --name <container-name>   Docker container name
                            Default: ${CONTAINER_NAME}
  --http                    Disable TLS-related mounts/env and serve plain HTTP
  --detach                  Run container in background
  --dry-run                 Show resolved config and command, do not execute
  -h, --help                Show this help

Modes:
  local
    Uses the repo-local OpenAPI spec:
      ${REPO_ROOT}/api/openapi.json

  prodlike
    Still uses the repo-local OpenAPI spec by default, but assumes TLS assets
    live under:
      ${DEFAULT_BASE_DIR}/datastore/certbot-data/letsencrypt/live/<fqdn>/

Examples:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --mode local --dry-run
  ${SCRIPT_NAME} --mode prodlike -f repo.mydatacenter.io
  ${SCRIPT_NAME} --http -p 8081
  ${SCRIPT_NAME} --detach
EOF
}

#------------------------------------------------------------------------------
# Argument parsing
#------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || die "--mode requires a value"
      MODE="$2"
      shift 2
      ;;
    -f)
      [[ $# -ge 2 ]] || die "-f requires a value"
      FQDN="$2"
      shift 2
      ;;
    -p)
      [[ $# -ge 2 ]] || die "-p requires a value"
      HOST_PORT="$2"
      shift 2
      ;;
    --base-dir)
      [[ $# -ge 2 ]] || die "--base-dir requires a value"
      BASE_DIR="$2"
      shift 2
      ;;
    --spec)
      [[ $# -ge 2 ]] || die "--spec requires a value"
      SPEC_PATH="$2"
      shift 2
      ;;
    --name)
      [[ $# -ge 2 ]] || die "--name requires a value"
      CONTAINER_NAME="$2"
      shift 2
      ;;
    --http)
      USE_TLS="false"
      shift
      ;;
    --detach)
      DETACH="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "Unknown argument: $1"
      ;;
  esac
done

#------------------------------------------------------------------------------
# Validation helpers
#------------------------------------------------------------------------------
require_file() {
  local file_path="$1"
  local purpose="${2:-required input}"
  [[ -f "$file_path" ]] || die "Missing file: $file_path (${purpose})"
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found in PATH: $cmd"
}

require_mode() {
  case "$MODE" in
    local|prodlike) ;;
    *) die "Invalid mode: ${MODE}. Expected: local or prodlike." ;;
  esac
}

#------------------------------------------------------------------------------
# Path resolution
#------------------------------------------------------------------------------
resolve_paths() {
  local live_dir
  live_dir="${BASE_DIR}/datastore/certbot-data/letsencrypt/live/${FQDN}"

  TLS_CERT_FILE="${live_dir}/fullchain.pem"
  TLS_KEY_FILE="${live_dir}/privkey.pem"
}

#------------------------------------------------------------------------------
# Pre-flight validation
#------------------------------------------------------------------------------
require_mode
require_command docker
resolve_paths

require_file "${SPEC_PATH}" "OpenAPI specification"

[[ "${HOST_PORT}" =~ ^[0-9]+$ ]] || die "Port must be numeric: ${HOST_PORT}"
(( HOST_PORT >= 1 && HOST_PORT <= 65535 )) || die "Port must be between 1 and 65535"

if [[ "${USE_TLS}" == "true" ]]; then
  require_file "${TLS_CERT_FILE}" "server TLS certificate"
  require_file "${TLS_KEY_FILE}" "server TLS private key"
fi

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
cat <<EOF
════════════════════════════════════════════════════════════
📘 Swagger UI Launcher
════════════════════════════════════════════════════════════
Mode           : ${MODE}
Repo Root      : ${REPO_ROOT}
FQDN           : ${FQDN}
Host Port      : ${HOST_PORT}
Container Name : ${CONTAINER_NAME}
Spec Path      : ${SPEC_PATH}

🔐 TLS
Use TLS        : ${USE_TLS}
TLS Cert       : ${TLS_CERT_FILE}
TLS Key        : ${TLS_KEY_FILE}

⚙️  Flags
Detach         : ${DETACH}
Dry Run        : ${DRY_RUN}
════════════════════════════════════════════════════════════
EOF

if [[ "${USE_TLS}" == "true" ]]; then
  warn "This script assumes your Swagger UI container/image supports the TLS env and cert mounts below."
  warn "If it does not, use --http and terminate TLS with Apache/Nginx/Traefik/Caddy instead."
fi

printf '\n'
info "Removing any existing container named '${CONTAINER_NAME}'..."
printf '\n'

#------------------------------------------------------------------------------
# Build docker command
#------------------------------------------------------------------------------
docker_cmd=(docker run --rm --name "${CONTAINER_NAME}")

if [[ "${DETACH}" == "true" ]]; then
  docker_cmd+=(-d)
fi

if [[ "${USE_TLS}" == "true" ]]; then
  docker_cmd+=(
    -p "${HOST_PORT}:${CONTAINER_PORT}"
    -e "SWAGGER_JSON=/app/openapi.json"
    -e "HTTPS_PORT=${CONTAINER_PORT}"
    -e "SSL_CRT_FILE=/certs/fullchain.pem"
    -e "SSL_KEY_FILE=/certs/privkey.pem"
    -v "${SPEC_PATH}:/app/openapi.json:ro"
    -v "${TLS_CERT_FILE}:/certs/fullchain.pem:ro"
    -v "${TLS_KEY_FILE}:/certs/privkey.pem:ro"
    swaggerapi/swagger-ui
  )
else
  docker_cmd+=(
    -p "${HOST_PORT}:8080"
    -e "SWAGGER_JSON=/app/openapi.json"
    -v "${SPEC_PATH}:/app/openapi.json:ro"
    swaggerapi/swagger-ui
  )
fi

info "Resolved command:"
printf '%q ' "${docker_cmd[@]}"
printf '\n\n'

if [[ "${DRY_RUN}" == "true" ]]; then
  success "Dry run complete."
  exit 0
fi

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

info "Starting Swagger UI container..."
"${docker_cmd[@]}"

if [[ "${DETACH}" == "true" ]]; then
  success "Swagger UI started in background."

  if [[ "${USE_TLS}" == "true" ]]; then
    printf '🌐 URL: https://%s:%s\n' "${FQDN}" "${HOST_PORT}"
  else
    printf '🌐 URL: http://localhost:%s\n' "${HOST_PORT}"
  fi
fi