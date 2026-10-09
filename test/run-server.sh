# run-server.sh

#!/usr/bin/env bash
set -Eeuo pipefail

################################################################################
# Script Name:  run-server.sh
# Author:       Daniel Cruz
# Description:  Build and run the Cert Manager API in either:
#               - local mode    -> use files from this repo when possible
#               - prodlike mode -> use files from /opt/certbot
#
# Usage:
#   ./test/run-server.sh
#   ./test/run-server.sh --mode local
#   ./test/run-server.sh --mode prodlike -f repo.mydatacenter.io
#   ./test/run-server.sh --dry-run
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
readonly APP_NAME="cert-manager-api"
readonly DEFAULT_BASE_DIR="/opt/certbot"
readonly DEFAULT_FQDN="repo.example.com"
readonly DEFAULT_MODE="local"
readonly DEFAULT_LISTEN_ADDR=":8000"
readonly DEFAULT_IP_POLICY="allow"

MODE="${DEFAULT_MODE}"
FQDN="${DEFAULT_FQDN}"
BASE_DIR="${DEFAULT_BASE_DIR}"
LISTEN_ADDR="${DEFAULT_LISTEN_ADDR}"
IP_POLICY="${DEFAULT_IP_POLICY}"
DRY_RUN="false"
SKIP_BUILD="false"

# Resolved later
APP_PATH=""
TLS_CERT_FILE=""
TLS_KEY_FILE=""
CLIENT_CA_FILE=""
ALLOWED_CNS_FILE=""
IP_LIST_FILE=""
CSV_PATH=""

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
🚀 Cert Manager API Launcher

Build and run the Cert Manager API using:
- server TLS certificate and key
- mTLS client CA validation
- allowed client CNs
- IP access policy
- certificate CSV inventory

Usage:
  ${SCRIPT_NAME} [options]

Options:
  --mode <local|prodlike>   Path resolution mode
                            Default: ${MODE}
  -f <fqdn>                 Domain used to locate Let's Encrypt live directory
                            Default: ${FQDN}
  --base-dir <path>         Override external base directory
                            Default: ${BASE_DIR}
  --listen <addr>           Listen address
                            Default: ${LISTEN_ADDR}
  --ip-policy <allow|deny>  IP policy
                            Default: ${IP_POLICY}
  --dry-run                 Show resolved config and command, do not execute
  --no-build                Skip 'go build'
  -h, --help                Show this help message

Modes:
  local
    Uses repo-local files when available:
      ${REPO_ROOT}/clients.txt
      ${REPO_ROOT}/ips.txt
      ${REPO_ROOT}/certificates.csv

    Still uses external TLS/mTLS PKI by default:
      ${DEFAULT_BASE_DIR}/datastore/certbot-data/letsencrypt/live/<fqdn>/
      ${DEFAULT_BASE_DIR}/secrets/rpmrepo-secrets/pki_mtls_material/

  prodlike
    Uses /opt/certbot-hosted files for CSV + PKI, while building/running the
    API binary from this repo.

Examples:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --mode local -f repo.mydatacenter.io
  ${SCRIPT_NAME} --mode prodlike -f repo.mydatacenter.io --dry-run
  ${SCRIPT_NAME} --mode local --no-build
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
    --base-dir)
      [[ $# -ge 2 ]] || die "--base-dir requires a value"
      BASE_DIR="$2"
      shift 2
      ;;
    --listen)
      [[ $# -ge 2 ]] || die "--listen requires a value"
      LISTEN_ADDR="$2"
      shift 2
      ;;
    --ip-policy)
      [[ $# -ge 2 ]] || die "--ip-policy requires a value"
      IP_POLICY="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --no-build)
      SKIP_BUILD="true"
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
  local live_dir pki_dir

  live_dir="${BASE_DIR}/datastore/certbot-data/letsencrypt/live/${FQDN}"
  pki_dir="${BASE_DIR}/secrets/rpmrepo-secrets/pki_mtls_material"

  APP_PATH="${REPO_ROOT}/${APP_NAME}"
  TLS_CERT_FILE="${live_dir}/fullchain.pem"
  TLS_KEY_FILE="${live_dir}/privkey.pem"
  CLIENT_CA_FILE="${pki_dir}/ca.crt"

  case "$MODE" in
    local)
      ALLOWED_CNS_FILE="${REPO_ROOT}/clients.txt"
      IP_LIST_FILE="${REPO_ROOT}/ips.txt"
      CSV_PATH="${REPO_ROOT}/certificates.csv"
      ;;
    prodlike)
      ALLOWED_CNS_FILE="${REPO_ROOT}/clients.txt"
      IP_LIST_FILE="${REPO_ROOT}/ips.txt"
      CSV_PATH="${BASE_DIR}/datastore/certbot-data/letsencrypt/certificates.csv"
      ;;
  esac
}

#------------------------------------------------------------------------------
# Pre-flight validation
#------------------------------------------------------------------------------
require_mode
require_command go
require_command sudo
resolve_paths

require_file "${TLS_CERT_FILE}" "server TLS certificate"
require_file "${TLS_KEY_FILE}" "server TLS private key"
require_file "${CLIENT_CA_FILE}" "mTLS client CA certificate"
require_file "${ALLOWED_CNS_FILE}" "allowed client CN list"
require_file "${IP_LIST_FILE}" "IP allow/deny list"
require_file "${CSV_PATH}" "certificate inventory CSV"

[[ "${IP_POLICY}" =~ ^(allow|deny)$ ]] || die "Invalid IP policy: ${IP_POLICY}"

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
cat <<EOF
════════════════════════════════════════════════════════════
🛠️  Cert Manager API Build & Run
════════════════════════════════════════════════════════════
Mode           : ${MODE}
Repo Root      : ${REPO_ROOT}
Application    : ${APP_NAME}
Binary Path    : ${APP_PATH}
FQDN           : ${FQDN}
Listen Address : ${LISTEN_ADDR}

🔐 Server TLS
TLS Cert       : ${TLS_CERT_FILE}
TLS Key        : ${TLS_KEY_FILE}

🛡️  mTLS / Access Control
Client CA      : ${CLIENT_CA_FILE}
Allowed CNs    : ${ALLOWED_CNS_FILE}
IP List        : ${IP_LIST_FILE}
IP Policy      : ${IP_POLICY}

📄 Inventory
Cert CSV       : ${CSV_PATH}

⚙️  Flags
Dry Run        : ${DRY_RUN}
Skip Build     : ${SKIP_BUILD}
════════════════════════════════════════════════════════════
EOF

printf '\n'
info "Resolved command:"
printf '%q ' sudo "${APP_PATH}" \
  -listen "${LISTEN_ADDR}" \
  -tls-cert "${TLS_CERT_FILE}" \
  -tls-key "${TLS_KEY_FILE}" \
  -client-ca "${CLIENT_CA_FILE}" \
  -allowed-cns "${ALLOWED_CNS_FILE}" \
  -ip-list "${IP_LIST_FILE}" \
  -ip-policy "${IP_POLICY}" \
  -cert-csv "${CSV_PATH}"
printf '\n\n'

if [[ "${DRY_RUN}" == "true" ]]; then
  success "Dry run complete."
  exit 0
fi

#------------------------------------------------------------------------------
# Build
#------------------------------------------------------------------------------
if [[ "${SKIP_BUILD}" == "false" ]]; then
  info "Building ${APP_NAME}..."
  (
    cd "${REPO_ROOT}"
    go build -o "${APP_NAME}" .
  )
  success "Build completed."
else
  warn "Skipping build as requested."
fi

#------------------------------------------------------------------------------
# Run
#------------------------------------------------------------------------------
info "Starting ${APP_NAME}..."
exec sudo "${APP_PATH}" \
  -listen "${LISTEN_ADDR}" \
  -tls-cert "${TLS_CERT_FILE}" \
  -tls-key "${TLS_KEY_FILE}" \
  -client-ca "${CLIENT_CA_FILE}" \
  -allowed-cns "${ALLOWED_CNS_FILE}" \
  -ip-list "${IP_LIST_FILE}" \
  -ip-policy "${IP_POLICY}" \
  -cert-csv "${CSV_PATH}"