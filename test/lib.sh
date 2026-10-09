# lib.sh

#!/usr/bin/env bash
# shellcheck shell=bash

# ==============================================================================
# Shared test helpers for the Cert Manager API project
# ------------------------------------------------------------------------------
# Intended to be sourced by scripts under ./test/
#
# Example:
#   # shellcheck source=./lib.sh
#   source "${SCRIPT_DIR}/lib.sh"
# ==============================================================================

#------------------------------------------------------------------------------
# Script / repo discovery
#------------------------------------------------------------------------------
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
fi

if [[ -z "${SCRIPT_NAME:-}" ]]; then
  SCRIPT_NAME="$(basename "${BASH_SOURCE[-1]}")"
fi

#------------------------------------------------------------------------------
# Colors
#------------------------------------------------------------------------------
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_BOLD='\033[1m'
COLOR_RESET='\033[0m'

#------------------------------------------------------------------------------
# Logging helpers
#------------------------------------------------------------------------------
info() {
  printf "${COLOR_BLUE}ℹ️  %s${COLOR_RESET}\n" "$*"
}

success() {
  printf "${COLOR_GREEN}✅ %s${COLOR_RESET}\n" "$*"
}

warn() {
  printf "${COLOR_YELLOW}⚠️  %s${COLOR_RESET}\n" "$*" >&2
}

error() {
  printf "${COLOR_RED}❌ %s${COLOR_RESET}\n" "$*" >&2
}

die() {
  error "$*"
  exit 1
}

divider() {
  printf '%b\n' "${COLOR_CYAN}──────────────────────────────────────────────────────────${COLOR_RESET}"
}

section() {
  divider
  printf "${COLOR_BOLD}%s${COLOR_RESET}\n" "$*"
  divider
}

#------------------------------------------------------------------------------
# Validation helpers
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

require_dir() {
  local dir_path="$1"
  local purpose="${2:-required directory}"
  [[ -d "$dir_path" ]] || die "Missing directory: $dir_path (${purpose})"
}

require_executable_file() {
  local file_path="$1"
  local purpose="${2:-required executable}"
  [[ -x "$file_path" ]] || die "Missing executable file: $file_path (${purpose})"
}

require_nonempty() {
  local value="$1"
  local label="${2:-value}"
  [[ -n "$value" ]] || die "${label} must not be empty"
}

require_mode() {
  local mode="$1"
  case "$mode" in
    local|prodlike) ;;
    *) die "Invalid mode: ${mode}. Expected: local or prodlike." ;;
  esac
}

require_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || die "Port must be numeric: $port"
  (( port >= 1 && port <= 65535 )) || die "Port must be between 1 and 65535: $port"
}

require_choice() {
  local value="$1"
  local label="$2"
  shift 2

  local allowed
  for allowed in "$@"; do
    if [[ "$value" == "$allowed" ]]; then
      return 0
    fi
  done

  die "Invalid ${label}: ${value}. Allowed values: $*"
}

#------------------------------------------------------------------------------
# Path helpers
#------------------------------------------------------------------------------
abs_path() {
  local input_path="$1"
  if [[ -d "$input_path" ]]; then
    (cd "$input_path" && pwd)
  else
    local parent
    parent="$(cd -- "$(dirname -- "$input_path")" && pwd)"
    printf '%s/%s\n' "$parent" "$(basename -- "$input_path")"
  fi
}

repo_path() {
  local relative_path="$1"
  printf '%s/%s\n' "${REPO_ROOT}" "${relative_path}"
}

#------------------------------------------------------------------------------
# Output helpers
#------------------------------------------------------------------------------
bool_label() {
  local value="${1:-false}"
  if [[ "$value" == "true" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

print_kv() {
  local key="$1"
  local value="$2"
  printf "%-14s : %s\n" "$key" "$value"
}

print_resolved_command() {
  info "Resolved command:"
  printf '%q ' "$@"
  printf '\n'
}

#------------------------------------------------------------------------------
# Tool detection helpers
#------------------------------------------------------------------------------
find_optional_command() {
  local cmd="$1"
  command -v "$cmd" 2>/dev/null || true
}

#------------------------------------------------------------------------------
# Trap helper
#------------------------------------------------------------------------------
cleanup_files() {
  local file
  for file in "$@"; do
    [[ -n "$file" && -e "$file" ]] && rm -f -- "$file"
  done
}