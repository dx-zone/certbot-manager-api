# test-api.sh

#!/usr/bin/env bash
set -Eeuo pipefail

################################################################################
# Script Name:  test-api.sh
# Author:       Daniel Cruz
# Description:  mTLS-aware smoke test runner for the Cert Manager API.
#
# Usage:
#   ./test/test-api.sh health
#   ./test/test-api.sh all
#   ./test/test-api.sh --mode prodlike -f repo.mydatacenter.io --port 8000 all
#   ./test/test-api.sh --dry-run list
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
readonly DEFAULT_HOST="repo.example.com"
readonly DEFAULT_PORT="8000"
readonly DEFAULT_CLIENT_NAME="client-identity"

MODE="${DEFAULT_MODE}"
BASE_DIR="${DEFAULT_BASE_DIR}"
API_HOST="${DEFAULT_HOST}"
API_PORT="${DEFAULT_PORT}"
CLIENT_NAME="${DEFAULT_CLIENT_NAME}"

DRY_RUN="false"
VERBOSE="false"
SHOW_BODY="true"

# Resolved later
BASE_URL=""
CURL_BIN=""
JQ_BIN=""
SERVER_CA_FILE=""
CLIENT_CERT_FILE=""
CLIENT_KEY_FILE=""

# Summary counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

#------------------------------------------------------------------------------
# UI helpers
#------------------------------------------------------------------------------
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_RESET='\033[0m'
COLOR_BOLD='\033[1m'

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
🧪 Cert Manager API Test Runner

Run mTLS-authenticated smoke tests against the Cert Manager API.

Usage:
  ${SCRIPT_NAME} [options] <test-name>

Test names:
  health
  list
  add
  delete
  reload
  invalid-path
  invalid-method
  all

Options:
  --mode <local|prodlike>   Path resolution mode
                            Default: ${MODE}
  -f, --host <hostname>     API hostname
                            Default: ${API_HOST}
  -p, --port <port>         API port
                            Default: ${API_PORT}
  --base-dir <path>         External base directory
                            Default: ${BASE_DIR}
  --client-name <name>      Client identity file prefix
                            Default: ${CLIENT_NAME}
  --dry-run                 Show resolved config only
  --verbose                 Use verbose curl output
  --no-body                 Suppress response body printing
  -h, --help                Show this help

Modes:
  local
    Uses PKI from:
      ${DEFAULT_BASE_DIR}/secrets/rpmrepo-secrets/pki_mtls_material/
    Good for testing your local API binary against the Ubuntu-hosted PKI.

  prodlike
    Same PKI source by default, but intended to mirror the deployed stack more
    closely in naming and usage.

Examples:
  ${SCRIPT_NAME} health
  ${SCRIPT_NAME} all
  ${SCRIPT_NAME} --host repo.mydatacenter.io --port 8000 health
  ${SCRIPT_NAME} --mode prodlike --client-name client-identity all
EOF
}

#------------------------------------------------------------------------------
# Argument parsing
#------------------------------------------------------------------------------
TEST_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || die "--mode requires a value"
      MODE="$2"
      shift 2
      ;;
    -f|--host)
      [[ $# -ge 2 ]] || die "--host requires a value"
      API_HOST="$2"
      shift 2
      ;;
    -p|--port)
      [[ $# -ge 2 ]] || die "--port requires a value"
      API_PORT="$2"
      shift 2
      ;;
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
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --verbose)
      VERBOSE="true"
      shift
      ;;
    --no-body)
      SHOW_BODY="false"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "${TEST_NAME}" ]]; then
        TEST_NAME="$1"
        shift
      else
        usage
        die "Unexpected extra argument: $1"
      fi
      ;;
  esac
done

[[ -n "${TEST_NAME}" ]] || {
  usage
  exit 1
}

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
  local pki_dir
  pki_dir="${BASE_DIR}/secrets/rpmrepo-secrets/pki_mtls_material"

  BASE_URL="https://${API_HOST}:${API_PORT}"
  SERVER_CA_FILE="${pki_dir}/client-ca.crt"
  CLIENT_CERT_FILE="${pki_dir}/${CLIENT_NAME}.crt"
  CLIENT_KEY_FILE="${pki_dir}/${CLIENT_NAME}.key"
}

#------------------------------------------------------------------------------
# Output helpers
#------------------------------------------------------------------------------
print_summary_header() {
  cat <<EOF
════════════════════════════════════════════════════════════
🧪 Cert Manager API Test Session
════════════════════════════════════════════════════════════
Mode           : ${MODE}
Repo Root      : ${REPO_ROOT}
API Host       : ${API_HOST}
API Port       : ${API_PORT}
Base URL       : ${BASE_URL}

🔐 mTLS Material
Server CA      : ${SERVER_CA_FILE}
Client Cert    : ${CLIENT_CERT_FILE}
Client Key     : ${CLIENT_KEY_FILE}

⚙️  Flags
Dry Run        : ${DRY_RUN}
Verbose Curl   : ${VERBOSE}
Show Body      : ${SHOW_BODY}
════════════════════════════════════════════════════════════
EOF
}

print_final_summary() {
  divider
  printf "${COLOR_BOLD}Test Summary${COLOR_RESET}\n"
  printf "Total  : %d\n" "${TOTAL_TESTS}"
  printf "Passed : ${COLOR_GREEN}%d${COLOR_RESET}\n" "${PASSED_TESTS}"
  printf "Failed : ${COLOR_RED}%d${COLOR_RESET}\n" "${FAILED_TESTS}"
  divider
}

pretty_print_body() {
  local body_file="$1"

  if [[ "${SHOW_BODY}" != "true" ]]; then
    return 0
  fi

  if [[ ! -s "${body_file}" ]]; then
    info "Response body is empty."
    return 0
  fi

  if [[ -n "${JQ_BIN}" ]] && "${JQ_BIN}" empty <"${body_file}" >/dev/null 2>&1; then
    "${JQ_BIN}" . <"${body_file}"
  else
    cat "${body_file}"
  fi
}

#------------------------------------------------------------------------------
# Request runner
#------------------------------------------------------------------------------
run_test() {
  local test_name="$1"
  local method="$2"
  local endpoint="$3"
  local expected_status="$4"
  local payload="${5:-}"

  local response_file headers_file curl_args status_line actual_status
  response_file="$(mktemp)"
  headers_file="$(mktemp)"

  TOTAL_TESTS=$((TOTAL_TESTS + 1))

  divider
  printf "${COLOR_BOLD}Test:${COLOR_RESET} %s\n" "${test_name}"
  printf "${COLOR_BOLD}Request:${COLOR_RESET} %s %s\n" "${method}" "${endpoint}"
  printf "${COLOR_BOLD}Expected Status:${COLOR_RESET} %s\n" "${expected_status}"

  if [[ -n "${payload}" ]]; then
    printf "${COLOR_BOLD}Payload:${COLOR_RESET} %s\n" "${payload}"
  fi

  curl_args=(
    --silent
    --show-error
    --dump-header "${headers_file}"
    --output "${response_file}"
    --request "${method}"
    --cacert "${SERVER_CA_FILE}"
    --cert "${CLIENT_CERT_FILE}"
    --key "${CLIENT_KEY_FILE}"
    -H "Content-Type: application/json"
    "${BASE_URL}${endpoint}"
  )

  if [[ "${VERBOSE}" == "true" ]]; then
    curl_args=(--verbose "${curl_args[@]}")
  fi

  if [[ -n "${payload}" ]]; then
    curl_args=(-d "${payload}" "${curl_args[@]}")
  fi

  if ! "${CURL_BIN}" "${curl_args[@]}"; then
    error "curl request failed."
    FAILED_TESTS=$((FAILED_TESTS + 1))
    rm -f "${response_file}" "${headers_file}"
    return 1
  fi

  status_line="$(grep -E '^HTTP/' "${headers_file}" | tail -n 1 || true)"
  actual_status="$(awk '{print $2}' <<<"${status_line}")"

  printf "${COLOR_BOLD}Actual Status:${COLOR_RESET} %s\n" "${actual_status:-unknown}"
  divider
  pretty_print_body "${response_file}"

  if [[ "${actual_status}" == "${expected_status}" ]]; then
    printf '\n'
    success "PASS: ${test_name}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    printf '\n'
    error "FAIL: ${test_name} (expected ${expected_status}, got ${actual_status:-unknown})"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi

  rm -f "${response_file}" "${headers_file}"
  printf '\n'
}

#------------------------------------------------------------------------------
# Test catalog
#------------------------------------------------------------------------------
test_health()         { run_test "health"         "GET"    "/healthcheck"                     "200"; }
test_list()           { run_test "list"           "GET"    "/certs"                           "200"; }
test_add() {
  local payload
  payload='{"fqdn":"test.mydatacenter.io","dns_provider":"cloudflare","email":"admin@mydatacenter.io"}'
  run_test "add" "POST" "/certs" "200" "${payload}"
}
test_delete()         { run_test "delete"         "DELETE" "/certs?fqdn=test.mydatacenter.io" "200"; }
test_reload()         { run_test "reload"         "POST"   "/reload"                          "200"; }
test_invalid_path()   { run_test "invalid-path"   "GET"    "/this-path-does-not-exist"       "404"; }
test_invalid_method() { run_test "invalid-method" "PATCH"  "/healthcheck"                     "405"; }

run_all_tests() {
  test_health
  test_list
  test_add
  test_delete
  test_reload
  test_invalid_path
  test_invalid_method
}

#------------------------------------------------------------------------------
# Pre-flight validation
#------------------------------------------------------------------------------
require_mode
require_command curl
CURL_BIN="$(command -v curl)"
JQ_BIN="$(command -v jq || true)"
resolve_paths

require_file "${SERVER_CA_FILE}" "CA certificate used to verify API server"
require_file "${CLIENT_CERT_FILE}" "mTLS client certificate"
require_file "${CLIENT_KEY_FILE}" "mTLS client private key"

[[ "${API_PORT}" =~ ^[0-9]+$ ]] || die "Port must be numeric: ${API_PORT}"
(( API_PORT >= 1 && API_PORT <= 65535 )) || die "Port must be between 1 and 65535"

print_summary_header
printf '\n'

if [[ "${DRY_RUN}" == "true" ]]; then
  success "Dry run complete."
  exit 0
fi

#------------------------------------------------------------------------------
# Dispatch
#------------------------------------------------------------------------------
case "${TEST_NAME}" in
  health)         test_health ;;
  list)           test_list ;;
  add)            test_add ;;
  delete)         test_delete ;;
  reload)         test_reload ;;
  invalid-path)   test_invalid_path ;;
  invalid-method) test_invalid_method ;;
  all)            run_all_tests ;;
  *)
    usage
    die "Unknown test: ${TEST_NAME}"
    ;;
esac

print_final_summary

[[ "${FAILED_TESTS}" -eq 0 ]]