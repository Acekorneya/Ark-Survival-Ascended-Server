#!/bin/bash
source /home/pok/scripts/common.sh

LOCK_HELD=false
TEMP_DOWNLOAD_DIR=""

cleanup() {
  local exit_code=$?

  if [ -n "$TEMP_DOWNLOAD_DIR" ] && [ -d "$TEMP_DOWNLOAD_DIR" ]; then
    echo "[INFO] Removing temporary download directory: $TEMP_DOWNLOAD_DIR"
    rm -rf "$TEMP_DOWNLOAD_DIR"
  fi

  if [ "$LOCK_HELD" = true ] && declare -f release_update_lock >/dev/null 2>&1; then
    release_update_lock
    LOCK_HELD=false
  fi

  exit $exit_code
}

trap cleanup EXIT INT TERM

saved_build_id=""
current_build_id=""

refresh_build_ids() {
  saved_build_id=""
  current_build_id=""

  if saved_build_id=$(get_build_id_from_acf); then
    saved_build_id=$(echo "$saved_build_id" | tr -d '[:space:]')
    echo "[INFO] Installed build ID: ${saved_build_id:-<none>}"
  else
    echo "[WARNING] Unable to read installed build ID: $saved_build_id"
    saved_build_id=""
  fi

  if current_build_id=$(get_current_build_id); then
    current_build_id=$(echo "$current_build_id" | tr -d '[:space:]')
    echo "[INFO] Available build ID: ${current_build_id:-<unknown>}"
  else
    echo "[WARNING] Unable to query current build ID: $current_build_id"
    current_build_id=""
  fi
}

install_required() {
  refresh_build_ids

  if [ -z "$current_build_id" ] || [[ "$current_build_id" == error* ]]; then
    echo "[WARNING] Current build ID unavailable; proceeding with staged download as precaution"
    return 0
  fi

  if [ -z "$saved_build_id" ] || [[ "$saved_build_id" == error* ]]; then
    echo "[INFO] No existing installation detected"
    return 0
  fi

  if [[ "$saved_build_id" =~ ^[0-9]+$ ]] && [[ "$current_build_id" =~ ^[0-9]+$ ]]; then
    if [ "$saved_build_id" = "$current_build_id" ]; then
      echo "[INFO] Server files already match the latest build"
      return 1
    fi
  else
    echo "[WARNING] Build IDs not in numeric format. Forcing staged download"
    return 0
  fi

  echo "[INFO] Installed build ($saved_build_id) differs from latest ($current_build_id). Update required"
  return 0
}

wait_for_other_install_if_needed() {
  echo "[INFO] Installation lock held by another instance; waiting for completion"
  if wait_for_update_lock; then
    echo "[INFO] Installation lock released by peer. Re-checking build state"
    if install_required; then
      echo "[INFO] Update still required after peer completed. Attempting to acquire lock again"
      if acquire_update_lock; then
        LOCK_HELD=true
        return 0
      else
        echo "[ERROR] Unable to acquire installation lock after waiting"
        return 1
      fi
    else
      echo "[INFO] Peer completed installation; nothing more to do"
      return 2
    fi
  else
    echo "[ERROR] Timed out waiting for installation lock"
    return 1
  fi
}

echo "[INFO] Starting server installation/update process"

if ! install_required; then
  echo "[INFO] Installation not required"
  exit 0
fi

echo "[INFO] Attempting to acquire installation lock"
if acquire_update_lock; then
  LOCK_HELD=true
else
  wait_for_other_install_if_needed
  case $? in
    0)
      ;; # Lock acquired, continue
    2)
      exit 0
      ;;
    *)
      exit 1
      ;;
  esac
fi

# Another instance might have finished the update while we waited for the lock
if ! install_required; then
  echo "[INFO] Update already applied by another instance. Skipping download."
  if [ "$LOCK_HELD" = true ]; then
    release_update_lock
    LOCK_HELD=false
  fi
  exit 0
fi

TEMP_DOWNLOAD_DIR=$(create_temp_download_dir) || exit 1

echo "[INFO] Temporary download directory created at $TEMP_DOWNLOAD_DIR"

if ! perform_staged_server_download "$TEMP_DOWNLOAD_DIR"; then
  echo "[ERROR] Staged installation failed"
  exit 1
fi

echo "[SUCCESS] Server files downloaded and staged successfully"

# Confirm the build ID after staging
post_install_build_id=$(get_build_id_from_acf)
if [ -n "$post_install_build_id" ]; then
  echo "[INFO] Post-install build ID: $post_install_build_id"
fi

mark_other_instances_dirty

echo "[INFO] Installation/update completed successfully"

if [ "$LOCK_HELD" = true ]; then
  release_update_lock
  LOCK_HELD=false
fi

exit 0
