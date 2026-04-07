#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER_JS="${SCRIPT_DIR}/steam_ticket.js"
DEFAULT_DELAY_MS="${STEAM_TICKET_REQUEST_DELAY_MS:-5000}"
SHOW_FULL_TICKET="${STEAM_TICKET_SHOW_FULL:-0}"
DEBUG_FLAG="${STEAM_TICKET_DEBUG:-1}"
TIMEOUT_SECONDS="${STEAM_TICKET_TIMEOUT_SECONDS:-60}"
EXCHANGE_EOS="${STEAM_TICKET_EXCHANGE_EOS:-0}"
EOS_HELPER_PY="${SCRIPT_DIR}/eos_token.py"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/helpers/test_steam_ticket.sh

Optional environment variables:
  STEAM_USERNAME                 Steam account username
  STEAM_PASSWORD                 Steam account password
  STEAM_GUARD_CODE               Current 5-digit Steam Guard mobile code
  STEAM_TICKET_REQUEST_DELAY_MS  Delay after gamesPlayed before requesting the ticket (default: 5000)
  STEAM_TICKET_TIMEOUT_SECONDS   Command timeout in seconds (default: 60)
  STEAM_TICKET_DEBUG             1 to enable helper debug logging (default: 1)
  STEAM_TICKET_SHOW_FULL         1 to print the full ticket on success
  STEAM_TICKET_EXCHANGE_EOS      1 to run eos_token.py with the generated ticket

Behavior:
  - Prompts for username/password if they are not already set in the environment.
  - Does not save the Steam Guard code.
  - Prints exit status, stderr, and ticket length in bytes.
  - Optionally tests the EOS exchange with the generated ticket.
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Error: node is not installed or not on PATH."
  exit 1
fi

if [ ! -f "${HELPER_JS}" ]; then
  echo "Error: ${HELPER_JS} was not found."
  exit 1
fi

if [ ! -d "${SCRIPT_DIR}/node_modules/steam-user" ]; then
  echo "Error: scripts/helpers/node_modules/steam-user is missing."
  echo "Run: (cd scripts/helpers && npm install)"
  exit 1
fi

if [ -z "${STEAM_USERNAME:-}" ]; then
  read -rp "Steam Username: " STEAM_USERNAME
fi

if [ -z "${STEAM_PASSWORD:-}" ]; then
  read -rsp "Steam Password: " STEAM_PASSWORD
  echo ""
fi

if [ -z "${STEAM_USERNAME:-}" ] || [ -z "${STEAM_PASSWORD:-}" ]; then
  echo "Error: Steam username and password are required."
  exit 1
fi

stdout_file="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "${stdout_file}" "${stderr_file}"' EXIT

set +e
STEAM_USERNAME="${STEAM_USERNAME}" \
STEAM_PASSWORD="${STEAM_PASSWORD}" \
STEAM_GUARD_CODE="${STEAM_GUARD_CODE:-}" \
STEAM_TICKET_DEBUG="${DEBUG_FLAG}" \
STEAM_TICKET_REQUEST_DELAY_MS="${DEFAULT_DELAY_MS}" \
timeout "${TIMEOUT_SECONDS}" \
node "${HELPER_JS}" >"${stdout_file}" 2>"${stderr_file}"
status=$?
set -e

ticket="$(tr -d '\r\n' < "${stdout_file}")"
stderr_output="$(cat "${stderr_file}")"
ticket_hex_len=${#ticket}
ticket_bytes=$((ticket_hex_len / 2))

echo "exit_status=${status}"
echo "ticket_hex_len=${ticket_hex_len}"
echo "ticket_bytes=${ticket_bytes}"

if [ -n "${stderr_output}" ]; then
  echo "--- stderr ---"
  printf '%s\n' "${stderr_output}"
fi

if [ -n "${ticket}" ]; then
  if [ "${SHOW_FULL_TICKET}" = "1" ]; then
    echo "--- ticket ---"
    printf '%s\n' "${ticket}"
  else
    echo "ticket_prefix=${ticket:0:32}"
    echo "ticket_suffix=${ticket: -32}"
  fi
fi

if [ "${EXCHANGE_EOS}" = "1" ] && [ -n "${ticket}" ]; then
  if [ ! -f "${EOS_HELPER_PY}" ]; then
    echo "Error: ${EOS_HELPER_PY} was not found."
    exit 1
  fi

  echo "--- eos exchange ---"
  set +e
  python3 "${EOS_HELPER_PY}" "${ticket}"
  eos_status=$?
  set -e
  echo "eos_exit_status=${eos_status}"
fi

exit "${status}"
