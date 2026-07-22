#!/bin/bash
#
# Read-only update notifier for shared installations where automatic file
# updates are intentionally disabled by the aggregate manager policy.

POK_SCRIPTS_DIR="${POK_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/common.sh"

notice_interval_seconds() {
  local interval="${CHECK_FOR_UPDATE_INTERVAL:-1}"
  local seconds=3600

  if [[ "$interval" =~ ^[0-9]+$ ]] && [ "$interval" -ge 1 ]; then
    seconds=$((interval * 3600))
  elif [[ "$interval" =~ ^0\.([0-9]+)$ ]]; then
    seconds=$((10#${BASH_REMATCH[1]} * 60))
  fi

  [ "$seconds" -ge 60 ] || seconds=60
  echo "$seconds"
}

record_pending_update() {
  local installed_build="$1"
  local available_build="$2"
  local pending_file="${ASA_DIR}/.pok-manager/pending_manual_update.env"
  local tmp_file="${pending_file}.tmp.$$"

  mkdir -p "$(dirname "$pending_file")"
  {
    printf 'INSTALLED_BUILD_ID=%q\n' "$installed_build"
    printf 'AVAILABLE_BUILD_ID=%q\n' "$available_build"
    printf 'BLOCKING_INSTANCES=%q\n' "${SHARED_POLICY_BLOCKING_INSTANCES:-}"
    printf 'DETECTED_AT=%q\n' "$(date +%s)"
  } > "$tmp_file" && mv "$tmp_file" "$pending_file"
}

notify_once_for_build() {
  local available_build="$1"
  local marker_dir="${ASA_DIR}/.pok-manager/update-notices"
  local marker_file="${marker_dir}/${INSTANCE_NAME}.${available_build}.notified"

  [ -f "$marker_file" ] && return 0
  mkdir -p "$marker_dir"

  echo "[WARNING] ARK build ${available_build} is available, but automatic shared-file updates are disabled."
  echo "[WARNING] An administrator must stop every managed instance and run ./POK-manager.sh -update."
  printf '%s\n' "$(date +%s)" > "${marker_file}.tmp.$$" && mv "${marker_file}.tmp.$$" "$marker_file"
}

check_for_blocked_update() {
  local installed_build=""
  local available_build=""

  shared_update_policy_load || true
  installed_build=$(get_build_id_from_acf)
  available_build=$(get_current_build_id)
  [[ "$installed_build" =~ ^[0-9]+$ ]] || return 1
  [[ "$available_build" =~ ^[0-9]+$ ]] || return 1
  [ "$installed_build" != "$available_build" ] || {
    rm -f "${ASA_DIR}/.pok-manager/pending_manual_update.env"
    return 0
  }

  record_pending_update "$installed_build" "$available_build"
  notify_once_for_build "$available_build"
}

main() {
  local interval_seconds=3600
  prepare_runtime_env

  if shared_update_policy_allows_automatic_updates; then
    exit 0
  fi

  interval_seconds=$(notice_interval_seconds)
  echo "[INFO] Starting read-only shared update notifier (interval: ${interval_seconds}s)."
  while true; do
    check_for_blocked_update || echo "[WARNING] Read-only update check could not obtain valid Steam build metadata."
    sleep "$interval_seconds"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
