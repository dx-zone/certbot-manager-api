# mtls-audit.sh

#!/usr/bin/env bash
set -Eeuo pipefail

################################################################################
# Script Name:  mtls-audit.sh
# Author:       Daniel Cruz
# Description:  Audit and explain the mTLS material used by the Cert Manager API
#               and related RPM repo stack.
#
# Usage:
#   ./test/mtls-audit.sh
#   ./test/mtls-audit.sh --client-name client-identity
#   ./test/mtls-audit.sh --base-dir /opt/certbot
#   ./test/mtls-audit.sh --write-clients-txt
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
readonly DEFAULT_BASE_DIR="/opt/certbot"
readonly DEFAULT_CLIENT_NAME="client-identity"

BASE_DIR="${DEFAULT_BASE_DIR}"
CLIENT_NAME="${DEFAULT_CLIENT_NAME}"
WRITE_CLIENTS_TXT="false"
DRY_RUN="false"

PKI_DIR=""
CA_CERT_FILE=""
CA_KEY_FILE=""
CLIENT_CA_FILE=""
CLIENT_CERT_FILE=""
CLIENT_KEY_FILE=""
CLIENT_CSR_FILE=""
CLIENTS_TXT_FILE="${REPO_ROOT}/clients.txt"

#------------------------------------------------------------------------------
# UI helpers
#------------------------------------------------------------------------------
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_BOLD='\033[1m'
COLOR_RESET='\033[0m'

info()    { printf "${COLOR_BLUE}ℹ️  %s${COLOR_RESET}\n" "$*"; }
success() { printf "${COLOR_GREEN}✅ %s${COLOR_RESET}\n" "$*"; }
warn()    { printf "${COLOR_YELLOW}⚠️  %s${COLOR_RESET}\n" "$*" >&2; }
error()   { printf "${COLOR_RED}❌ %s${COLOR_RESET}\n" "$*" >&2; }
die()     { error "$*"; exit 1; }

divider() {
  printf '%b\n' "${COLOR_CYAN}──────────────────────────────────────────────────────────${COLOR_RESET}"
}

usage() {
  cat <<EOF
🔎 mTLS Audit Tool

Audit the client-auth PKI material used by this project.

Usage:
  ${SCRIPT_NAME} [options]

Options:
  --base-dir <path>         External base directory
                            Default: ${BASE_DIR}
  --client-name <name>      Client identity prefix
                            Default: ${CLIENT_NAME}
  --write-clients-txt       Overwrite ${CLIENTS_TXT_FILE} with detected CN
  --dry-run                 Resolve paths only, do not audit
  -h, --help                Show this help

Examples:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --client-name client-identity
  ${SCRIPT_NAME} --write-clients-txt
EOF
}

#------------------------------------------------------------------------------
# Argument parsing
#------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-dir)
      [[ $# -ge 2 ]] || die "--base-dir requires a value"
      BASE_DIR="$2"
      shift 2
      ;;
    --client-name)
      [[ $# -ge 2 ]] || die "--client-name requires a value"
      CLIENT_NAME="$2"
      shift 2
      ;;
    --write-clients-txt)
      WRITE_CLIENTS_TXT="true"
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
# Helpers
#------------------------------------------------------------------------------
require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found in PATH: $cmd"
}

require_file() {
  local file_path="$1"
  local purpose="${2:-required input}"
  [[ -f "$file_path" ]] || die "Missing file: $file_path (${purpose})"
}

resolve_paths() {
  PKI_DIR="${BASE_DIR}/secrets/rpmrepo-secrets/pki_mtls_material"
  CA_CERT_FILE="${PKI_DIR}/ca.crt"
  CA_KEY_FILE="${PKI_DIR}/ca.key"
  CLIENT_CA_FILE="${PKI_DIR}/client-ca.crt"
  CLIENT_CERT_FILE="${PKI_DIR}/${CLIENT_NAME}.crt"
  CLIENT_KEY_FILE="${PKI_DIR}/${CLIENT_NAME}.key"
  CLIENT_CSR_FILE="${PKI_DIR}/${CLIENT_NAME}.csr"
}

get_subject_rfc2253() {
  local cert="$1"
  openssl x509 -in "$cert" -noout -subject -nameopt RFC2253 2>/dev/null | sed 's/^subject=//'
}

get_issuer_rfc2253() {
  local cert="$1"
  openssl x509 -in "$cert" -noout -issuer -nameopt RFC2253 2>/dev/null | sed 's/^issuer=//'
}

get_cn_from_cert() {
  local cert="$1"
  openssl x509 -in "$cert" -noout -subject -nameopt RFC2253 2>/dev/null \
    | sed 's/^subject=//' \
    | sed -n 's/.*CN=\([^,]*\).*/\1/p'
}

get_start_date() {
  local cert="$1"
  openssl x509 -in "$cert" -noout -startdate 2>/dev/null | sed 's/^notBefore=//'
}

get_end_date() {
  local cert="$1"
  openssl x509 -in "$cert" -noout -enddate 2>/dev/null | sed 's/^notAfter=//'
}

get_san() {
  local cert="$1"
  openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null | tail -n +2 | sed 's/^[[:space:]]*//'
}

get_eku() {
  local cert="$1"
  openssl x509 -in "$cert" -noout -ext extendedKeyUsage 2>/dev/null | tail -n +2 | sed 's/^[[:space:]]*//'
}

sha256_fp() {
  local cert="$1"
  openssl x509 -in "$cert" -noout -fingerprint -sha256 2>/dev/null | sed 's/^sha256 Fingerprint=//'
}

cert_and_key_match() {
  local cert="$1"
  local key="$2"

  local cert_md5 key_md5
  cert_md5="$(openssl x509 -noout -modulus -in "$cert" 2>/dev/null | openssl md5 | awk '{print $2}')"
  key_md5="$(openssl rsa  -noout -modulus -in "$key" 2>/dev/null | openssl md5 | awk '{print $2}')"

  [[ -n "$cert_md5" && "$cert_md5" == "$key_md5" ]]
}

verify_cert_chain() {
  local ca_cert="$1"
  local client_cert="$2"
  openssl verify -CAfile "$ca_cert" "$client_cert" 2>/dev/null
}

compare_ca_alias() {
  if [[ ! -f "${CA_CERT_FILE}" || ! -f "${CLIENT_CA_FILE}" ]]; then
    return 1
  fi

  [[ "$(sha256_fp "${CA_CERT_FILE}")" == "$(sha256_fp "${CLIENT_CA_FILE}")" ]]
}

#------------------------------------------------------------------------------
# Pre-flight
#------------------------------------------------------------------------------
require_command openssl
resolve_paths

require_file "${CA_CERT_FILE}" "root CA certificate"
require_file "${CLIENT_CERT_FILE}" "client certificate"
require_file "${CLIENT_KEY_FILE}" "client private key"

if [[ -f "${CLIENT_CA_FILE}" ]]; then
  :
else
  warn "client-ca.crt not found. Apache/client trust alias may be missing."
fi

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
cat <<EOF
════════════════════════════════════════════════════════════
🔎 mTLS Audit
════════════════════════════════════════════════════════════
Repo Root      : ${REPO_ROOT}
Base Dir       : ${BASE_DIR}
PKI Dir        : ${PKI_DIR}
Client Name    : ${CLIENT_NAME}

📁 Files
CA Cert        : ${CA_CERT_FILE}
CA Key         : ${CA_KEY_FILE}
Client CA      : ${CLIENT_CA_FILE}
Client Cert    : ${CLIENT_CERT_FILE}
Client Key     : ${CLIENT_KEY_FILE}
Client CSR     : ${CLIENT_CSR_FILE}
clients.txt    : ${CLIENTS_TXT_FILE}

⚙️  Flags
Write clients.txt : ${WRITE_CLIENTS_TXT}
Dry Run           : ${DRY_RUN}
════════════════════════════════════════════════════════════
EOF

printf '\n'

if [[ "${DRY_RUN}" == "true" ]]; then
  success "Dry run complete."
  exit 0
fi

#------------------------------------------------------------------------------
# Audit
#------------------------------------------------------------------------------
ca_subject="$(get_subject_rfc2253 "${CA_CERT_FILE}")"
ca_issuer="$(get_issuer_rfc2253 "${CA_CERT_FILE}")"
ca_start="$(get_start_date "${CA_CERT_FILE}")"
ca_end="$(get_end_date "${CA_CERT_FILE}")"

client_subject="$(get_subject_rfc2253 "${CLIENT_CERT_FILE}")"
client_issuer="$(get_issuer_rfc2253 "${CLIENT_CERT_FILE}")"
client_cn="$(get_cn_from_cert "${CLIENT_CERT_FILE}")"
client_start="$(get_start_date "${CLIENT_CERT_FILE}")"
client_end="$(get_end_date "${CLIENT_CERT_FILE}")"
client_san="$(get_san "${CLIENT_CERT_FILE}" || true)"
client_eku="$(get_eku "${CLIENT_CERT_FILE}" || true)"

divider
printf "${COLOR_BOLD}CA Certificate${COLOR_RESET}\n"
printf "Subject      : %s\n" "${ca_subject}"
printf "Issuer       : %s\n" "${ca_issuer}"
printf "Valid From   : %s\n" "${ca_start}"
printf "Valid Until  : %s\n" "${ca_end}"

divider
printf "${COLOR_BOLD}Client Certificate${COLOR_RESET}\n"
printf "Subject      : %s\n" "${client_subject}"
printf "Issuer       : %s\n" "${client_issuer}"
printf "Detected CN  : %s\n" "${client_cn:-<not found>}"
printf "Valid From   : %s\n" "${client_start}"
printf "Valid Until  : %s\n" "${client_end}"
printf "EKU          : %s\n" "${client_eku:-<not present>}"
printf "SAN          : %s\n" "${client_san:-<not present>}"

divider
printf "${COLOR_BOLD}Validation${COLOR_RESET}\n"

if cert_and_key_match "${CLIENT_CERT_FILE}" "${CLIENT_KEY_FILE}"; then
  success "Client certificate matches client private key."
else
  error "Client certificate does NOT match client private key."
fi

chain_result="$(verify_cert_chain "${CA_CERT_FILE}" "${CLIENT_CERT_FILE}" || true)"
if grep -q ': OK$' <<<"${chain_result}"; then
  success "Client certificate verifies against ca.crt."
else
  error "Client certificate does NOT verify against ca.crt."
  printf "Result       : %s\n" "${chain_result:-<no output>}"
fi

if [[ -f "${CLIENT_CA_FILE}" ]]; then
  if compare_ca_alias; then
    success "client-ca.crt content matches ca.crt."
  else
    warn "client-ca.crt exists but does NOT match ca.crt."
  fi
fi

if grep -qi 'TLS Web Client Authentication\|clientAuth' <<<"${client_eku:-}"; then
  success "Client certificate EKU is suitable for client authentication."
else
  warn "Client certificate EKU does not clearly indicate client authentication."
fi

divider
printf "${COLOR_BOLD}Recommended Runtime Mapping${COLOR_RESET}\n"
cat <<EOF
API server should use:
  -client-ca   ${CA_CERT_FILE}
  -allowed-cns ${CLIENTS_TXT_FILE}

curl / API smoke tests should use:
  --cert   ${CLIENT_CERT_FILE}
  --key    ${CLIENT_KEY_FILE}

Suggested clients.txt entry:
  ${client_cn:-<unable to detect CN>}
EOF

if [[ "${WRITE_CLIENTS_TXT}" == "true" ]]; then
  [[ -n "${client_cn:-}" ]] || die "Cannot write clients.txt because CN could not be detected."
  printf '%s\n' "${client_cn}" > "${CLIENTS_TXT_FILE}"
  success "Wrote detected CN to ${CLIENTS_TXT_FILE}"
fi

printf '\n'
divider
printf "${COLOR_BOLD}Quick Commands${COLOR_RESET}\n"
cat <<EOF
Inspect client cert:
  openssl x509 -in "${CLIENT_CERT_FILE}" -noout -text

Verify client cert against CA:
  openssl verify -CAfile "${CA_CERT_FILE}" "${CLIENT_CERT_FILE}"

Check cert/key match:
  openssl x509 -noout -modulus -in "${CLIENT_CERT_FILE}" | openssl md5
  openssl rsa  -noout -modulus -in "${CLIENT_KEY_FILE}"  | openssl md5
EOF

printf '\n'
success "mTLS audit complete."