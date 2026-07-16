#!/bin/bash
# Stage and activate an explicitly selected ASA Steam depot rollback.

POK_SCRIPTS_DIR="${POK_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=/dev/null
source "${POK_SCRIPTS_DIR}/common.sh"

LOCK_HELD=false
STAGE_SUCCEEDED=false
ROLLBACK_COMMAND=""

cleanup() {
  local exit_code=$?
  if [ "$LOCK_HELD" = true ]; then
    release_update_lock || true
    LOCK_HELD=false
  fi
  if [ "$exit_code" -ne 0 ] && [ "$STAGE_SUCCEEDED" != true ] && [ "$ROLLBACK_COMMAND" = "stage" ]; then
    rm -rf "$ROLLBACK_STAGING_DIR"
    python3 -B "$DEPLOYMENT_MANAGER_PATH" abort --state-dir "$DEPLOYMENT_STATE_DIR" >/dev/null 2>&1 || true
  fi
  exit "$exit_code"
}

validate_manifest() {
  local manifest="$1"
  if ! [[ "$manifest" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] Depot manifest must contain only digits."
    return 1
  fi
}

stage_rollback() {
  local manifest="$1"
  local content_root="/opt/steamcmd/steamapps/content/app_2430930/depot_2430931"
  local staged_exe="${ROLLBACK_STAGING_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe"
  local current_exe="${ASA_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe"
  local failed_hash=""
  local failed_build_id=""
  local failed_cache_timestamp=""
  local incompatible_marker="${ASA_DIR}/ShooterGame/Binaries/Win64/ArkApi/Cache/incompatible_cache.json"

  validate_manifest "$manifest" || return 1
  [ -f "$current_exe" ] || {
    echo "[ERROR] Current ARK server executable is missing; rollback cannot establish a safe baseline."
    return 1
  }
  failed_hash=$(sha256sum "$current_exe" | awk '{print $1}')
  failed_build_id=$(get_build_id_from_acf 2>/dev/null || true)
  if [ -f "$incompatible_marker" ] && \
      [ "$(jq -r '.executable_hash // empty' "$incompatible_marker" 2>/dev/null)" = "$failed_hash" ]; then
    failed_cache_timestamp=$(jq -r '.last_modified // empty' "$incompatible_marker" 2>/dev/null)
  fi

  if ! acquire_update_lock; then
    echo "[ERROR] Another shared install, update, or rollback operation is active."
    return 1
  fi
  LOCK_HELD=true

  echo "[INFO] Staging ASA depot 2430931 manifest ${manifest} with anonymous SteamCMD access..."
  rm -rf "$content_root" "$ROLLBACK_STAGING_DIR"
  mkdir -p "$ROLLBACK_STAGING_DIR" "$DEPLOYMENT_STATE_DIR"
  if ! /opt/steamcmd/steamcmd.sh \
      +@sSteamCmdForcePlatformType windows \
      +login anonymous \
      +download_depot 2430930 2430931 "$manifest" \
      +quit; then
    echo "[ERROR] SteamCMD failed to download rollback manifest ${manifest}."
    return 1
  fi
  [ -f "${content_root}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe" ] || {
    echo "[ERROR] SteamCMD completed without the expected ARK server executable."
    return 1
  }
  cp -a "${content_root}/." "$ROLLBACK_STAGING_DIR/" || {
    echo "[ERROR] Unable to copy the downloaded depot into persistent rollback staging."
    return 1
  }
  prepare_staged_asaapi_cache "$ROLLBACK_STAGING_DIR" || return 1

  local staged_hash
  staged_hash=$(sha256sum "$staged_exe" | awk '{print $1}')
  python3 -B "$DEPLOYMENT_MANAGER_PATH" begin \
    --state-dir "$DEPLOYMENT_STATE_DIR" \
    --manifest "$manifest" \
    --executable-hash "$staged_hash" \
    --failed-build-id "$failed_build_id" \
    --failed-executable-hash "$failed_hash" \
    --failed-cache-last-modified "$failed_cache_timestamp" || return 1

  STAGE_SUCCEEDED=true
  release_update_lock
  LOCK_HELD=false
  echo "[SUCCESS] Rollback manifest ${manifest} is staged and AsaApi-compatible; live files are unchanged."
}

activate_rollback() {
  local manifest="$1"
  local staged_exe="${ROLLBACK_STAGING_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe"
  local live_exe="${ASA_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe"
  local expected_hash
  local actual_hash

  validate_manifest "$manifest" || return 1
  [ -f "$staged_exe" ] || {
    echo "[ERROR] The validated rollback staging directory is missing."
    return 1
  }
  expected_hash=$(deployment_state_field transaction executable_sha256 || true)
  actual_hash=$(sha256sum "$staged_exe" | awk '{print $1}')
  [ -n "$expected_hash" ] && [ "$actual_hash" = "$expected_hash" ] || {
    echo "[ERROR] Staged rollback files no longer match the validated transaction."
    return 1
  }

  if ! acquire_update_lock; then
    echo "[ERROR] Another shared install, update, or rollback operation is active."
    return 1
  fi
  LOCK_HELD=true
  echo "[INFO] Activating validated rollback manifest ${manifest} in the shared server files..."
  sync_temp_into_live_dir "$ROLLBACK_STAGING_DIR" "$ASA_DIR" || return 1
  ensure_server_file_permissions "$ASA_DIR"
  cleanup_steam_dlls "$ASA_DIR"
  sync

  python3 -B "$DEPLOYMENT_MANAGER_PATH" activate \
    --state-dir "$DEPLOYMENT_STATE_DIR" \
    --manifest "$manifest" \
    --server-exe "$live_exe" || return 1

  STAGE_SUCCEEDED=true
  rm -rf "$ROLLBACK_STAGING_DIR"
  release_update_lock
  LOCK_HELD=false
  echo "[SUCCESS] Shared ASA files now use rollback manifest ${manifest}."
}

main() {
  local command="${1:-}"
  local manifest="${2:-}"
  prepare_runtime_env
  ROLLBACK_COMMAND="$command"
  trap cleanup EXIT INT TERM

  case "$command" in
    select)
      local current_exe="${ASA_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe"
      local current_hash=""
      [ -f "$current_exe" ] && current_hash=$(sha256sum "$current_exe" | awk '{print $1}')
      python3 -B "$DEPLOYMENT_MANAGER_PATH" select-manifest \
        --state-dir "$DEPLOYMENT_STATE_DIR" --current-hash "$current_hash"
      STAGE_SUCCEEDED=true
      ;;
    stage)
      stage_rollback "$manifest"
      ;;
    activate)
      activate_rollback "$manifest"
      ;;
    abort)
      rm -rf "$ROLLBACK_STAGING_DIR"
      python3 -B "$DEPLOYMENT_MANAGER_PATH" abort --state-dir "$DEPLOYMENT_STATE_DIR"
      STAGE_SUCCEEDED=true
      ;;
    *)
      echo "Usage: $0 {select|stage|activate|abort} [manifest]" >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
