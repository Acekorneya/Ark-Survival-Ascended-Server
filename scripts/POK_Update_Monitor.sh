#!/bin/bash
#
# Lightweight update detector used by the long-running container monitor.

POK_SCRIPTS_DIR="${POK_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/common.sh"

main() {
  prepare_runtime_env

  if ! env_value_is_truthy "${UPDATE_SERVER:-FALSE}"; then
    echo "[INFO] UPDATE_SERVER disabled; skipping update check."
    exit 1
  fi

  echo "[INFO] Checking for updates using SteamCMD..."
  local saved_build_id
  local current_build_id
  saved_build_id=$(get_build_id_from_acf)
  current_build_id=$(get_current_build_id)

  if [ -z "$current_build_id" ] || [[ "$current_build_id" == error* ]]; then
    echo "[ERROR] Failed to get build ID from SteamCMD."
    exit 2
  fi

  if ! [[ "$current_build_id" =~ ^[0-9]+$ ]]; then
    echo "[WARNING] SteamCMD returned invalid build ID format: '$current_build_id'"
    exit 2
  fi

  if ! [[ "$saved_build_id" =~ ^[0-9]+$ ]]; then
    echo "[WARNING] Saved build ID has invalid format: '$saved_build_id'. Will attempt update."
    saved_build_id=""
  fi

  current_build_id=$(echo "$current_build_id" | tr -d '[:space:]')
  saved_build_id=$(echo "$saved_build_id" | tr -d '[:space:]')

  if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
    echo "===================== BUILD ID COMPARISON ====================="
    echo "🔵 SteamCMD Current Build ID: $current_build_id"
    echo "🟢 Server Installed Build ID: $saved_build_id"
    echo "=============================================================="

    if [ "${VERBOSE_DEBUG}" = "TRUE" ]; then
      echo "Detailed comparison:"
      echo "   - Current: '${current_build_id}' (length: ${#current_build_id})"
      echo "   - Saved: '${saved_build_id}' (length: ${#saved_build_id})"
      if [ "$current_build_id" = "$saved_build_id" ]; then
        echo "   - String comparison result: MATCH"
      else
        echo "   - String comparison result: DIFFERENT"
      fi
    fi
  fi

  if [ -z "$saved_build_id" ] || [ "$saved_build_id" != "$current_build_id" ]; then
    if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
      echo "[INFO] ✅ UPDATE AVAILABLE: SteamCMD has newer build ($current_build_id) than installed ($saved_build_id)"
    fi
    exit 0
  fi

  if [ "${DISPLAY_POK_MONITOR_MESSAGE}" = "TRUE" ]; then
    echo "[INFO] ✅ No updates available. Server is running latest SteamCMD build ID: $current_build_id"
  fi
  exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
