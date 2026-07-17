#!/bin/bash
#
# Shared multi-instance auto-update coordination helpers.
# This file is sourced by runtime entrypoints and should not execute on load.

POK_SCRIPTS_DIR="${POK_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if ! declare -f env_value_is_truthy >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${POK_SCRIPTS_DIR}/common.sh"
fi

UPDATE_COORDINATION_MAX_ATTEMPTS="${UPDATE_COORDINATION_MAX_ATTEMPTS:-3}"
UPDATE_COORDINATION_HEARTBEAT_STALE_SECONDS="${UPDATE_COORDINATION_HEARTBEAT_STALE_SECONDS:-120}"
UPDATE_COORDINATION_UPDATE_TIMEOUT_SECONDS="${UPDATE_COORDINATION_UPDATE_TIMEOUT_SECONDS:-1800}"
UPDATE_COORDINATION_STARTUP_TIMEOUT_SECONDS="${UPDATE_COORDINATION_STARTUP_TIMEOUT_SECONDS:-600}"
UPDATE_COORDINATION_COMPLETED_RETENTION_SECONDS="${UPDATE_COORDINATION_COMPLETED_RETENTION_SECONDS:-86400}"
UPDATE_COORDINATION_FOLLOWER_WAIT_FOR_MASTER_SECONDS="${UPDATE_COORDINATION_FOLLOWER_WAIT_FOR_MASTER_SECONDS:-90}"
UPDATE_COORDINATION_FOLLOWER_JITTER_MIN_SECONDS="${UPDATE_COORDINATION_FOLLOWER_JITTER_MIN_SECONDS:-5}"
UPDATE_COORDINATION_FOLLOWER_JITTER_MAX_SECONDS="${UPDATE_COORDINATION_FOLLOWER_JITTER_MAX_SECONDS:-30}"
UPDATE_COORDINATION_INSTANCE_STALE_SECONDS="${UPDATE_COORDINATION_INSTANCE_STALE_SECONDS:-90}"
UPDATE_COORDINATION_BARRIER_EXTRA_SECONDS="${UPDATE_COORDINATION_BARRIER_EXTRA_SECONDS:-300}"

UPDATE_COORDINATION_STATE_PRESENT=0
UPDATE_COORDINATION_STATE_CYCLE_ID=""
UPDATE_COORDINATION_STATE_TARGET_BUILD_ID=""
UPDATE_COORDINATION_STATE_ACTIVE_LEADER_INSTANCE=""
UPDATE_COORDINATION_STATE_ACTIVE_LEADER_PRIORITY=""
UPDATE_COORDINATION_STATE_ATTEMPT_COUNT=0
UPDATE_COORDINATION_STATE_ATTEMPTED_PRIORITIES=""
UPDATE_COORDINATION_STATE_ATTEMPTED_INSTANCES=""
UPDATE_COORDINATION_STATE_PHASE=""
UPDATE_COORDINATION_STATE_PHASE_STARTED_AT=0
UPDATE_COORDINATION_STATE_LAST_HEARTBEAT_AT=0
UPDATE_COORDINATION_STATE_FAIL_REASON=""
UPDATE_COORDINATION_HEARTBEAT_PID=""

update_coordination_enabled() {
  env_value_is_truthy "${UPDATE_SERVER:-FALSE}" || return 1

  case "${UPDATE_COORDINATION_ROLE^^}" in
  MASTER|FOLLOWER)
    ;;
  *)
    return 1
    ;;
  esac

  [[ "${UPDATE_COORDINATION_PRIORITY:-}" =~ ^[0-9]+$ ]]
}

update_coordination_is_master_role() {
  [[ "${UPDATE_COORDINATION_ROLE^^}" == "MASTER" ]]
}

update_coordination_is_follower_role() {
  [[ "${UPDATE_COORDINATION_ROLE^^}" == "FOLLOWER" ]]
}

update_coordination_root() {
  echo "${ASA_DIR}/update_coordination"
}

update_coordination_current_dir() {
  echo "$(update_coordination_root)/current"
}

update_coordination_state_file() {
  echo "$(update_coordination_current_dir)/state.env"
}

update_coordination_claim_dir() {
  echo "$(update_coordination_current_dir)/claim.lock"
}

update_coordination_cycles_dir() {
  echo "$(update_coordination_root)/cycles"
}

update_coordination_instances_dir() {
  echo "$(update_coordination_root)/instances"
}

update_coordination_instance_presence_file() {
  echo "$(update_coordination_instances_dir)/${INSTANCE_NAME}.env"
}

update_coordination_touch_instance_presence() {
  local presence_file=""
  local tmp_file=""

  [ -n "${INSTANCE_NAME:-}" ] || return 1
  mkdir -p "$(update_coordination_instances_dir)"
  presence_file=$(update_coordination_instance_presence_file)
  tmp_file="${presence_file}.tmp.$$"
  {
    printf 'INSTANCE_NAME=%q\n' "${INSTANCE_NAME}"
    printf 'UPDATED_AT=%q\n' "$(update_coordination_epoch)"
    printf 'RESTART_NOTICE_MINUTES=%q\n' "${RESTART_NOTICE_MINUTES:-30}"
  } > "$tmp_file" || return 1
  mv "$tmp_file" "$presence_file"
}

update_coordination_remove_instance_presence() {
  [ -n "${INSTANCE_NAME:-}" ] || return 0
  rm -f "$(update_coordination_instance_presence_file)"
}

update_coordination_cycle_dir() {
  local cycle_id="${1:-${UPDATE_COORDINATION_STATE_CYCLE_ID:-}}"
  [ -n "$cycle_id" ] || return 1
  echo "$(update_coordination_cycles_dir)/${cycle_id}"
}

update_coordination_participants_file() {
  echo "$(update_coordination_cycle_dir)/participants.txt"
}

update_coordination_snapshot_live_participants() {
  local now=""
  local presence_file=""
  local participant=""
  local updated_at=0
  local INSTANCE_NAME=""
  local UPDATED_AT=0
  local RESTART_NOTICE_MINUTES=30
  local participants_file=""
  local tmp_file=""
  local -a participants=()

  [ -n "${UPDATE_COORDINATION_STATE_CYCLE_ID:-}" ] || return 1
  now=$(update_coordination_epoch)
  participants_file=$(update_coordination_participants_file)
  tmp_file="${participants_file}.tmp.$$"
  mkdir -p "$(dirname "$participants_file")"

  for presence_file in "$(update_coordination_instances_dir)"/*.env; do
    [ -f "$presence_file" ] || continue
    INSTANCE_NAME=""
    UPDATED_AT=0
    RESTART_NOTICE_MINUTES=30
    # shellcheck disable=SC1090
    source "$presence_file"
    participant="$INSTANCE_NAME"
    updated_at="$UPDATED_AT"
    [ -n "$participant" ] || continue
    [[ "$updated_at" =~ ^[0-9]+$ ]] || continue
    if [ $((now - updated_at)) -le "$UPDATE_COORDINATION_INSTANCE_STALE_SECONDS" ]; then
      participants+=("$participant")
    fi
  done

  if [ "${#participants[@]}" -gt 0 ]; then
    printf '%s\n' "${participants[@]}" | sort -u > "$tmp_file"
  else
    : > "$tmp_file"
  fi
  mv "$tmp_file" "$participants_file"
}

update_coordination_participant_count() {
  local participants_file=""
  participants_file=$(update_coordination_participants_file 2>/dev/null) || {
    echo 0
    return 0
  }
  [ -f "$participants_file" ] || {
    echo 0
    return 0
  }
  awk 'NF { count++ } END { print count + 0 }' "$participants_file"
}

update_coordination_instance_is_participant() {
  local participants_file=""
  update_coordination_refresh_state || return 1
  participants_file=$(update_coordination_participants_file) || return 1
  [ -f "$participants_file" ] && grep -Fxq "${INSTANCE_NAME}" "$participants_file"
}

update_coordination_mark_shutdown_ready() {
  local ready_dir=""
  local ready_file=""
  update_coordination_refresh_state || return 1
  ready_dir="$(update_coordination_cycle_dir)/shutdown-ready"
  ready_file="${ready_dir}/${INSTANCE_NAME}.ready"
  mkdir -p "$ready_dir"
  printf '%s\n' "$(update_coordination_epoch)" > "${ready_file}.tmp.$$" || return 1
  mv "${ready_file}.tmp.$$" "$ready_file"
}

update_coordination_all_participants_ready() {
  local participants_file=""
  local ready_dir=""
  local participant=""

  update_coordination_refresh_state || return 1
  participants_file=$(update_coordination_participants_file) || return 1
  ready_dir="$(update_coordination_cycle_dir)/shutdown-ready"
  [ -f "$participants_file" ] || return 1

  while IFS= read -r participant; do
    [ -n "$participant" ] || continue
    [ -f "${ready_dir}/${participant}.ready" ] || return 1
  done < "$participants_file"
  return 0
}

update_coordination_wait_for_shutdown_barrier() {
  local max_notice=0
  local timeout_seconds=0
  local elapsed=0

  shared_update_policy_load || true
  max_notice="${SHARED_POLICY_MAX_RESTART_NOTICE_MINUTES:-0}"
  [[ "$max_notice" =~ ^[0-9]+$ ]] || max_notice=30
  timeout_seconds=$((max_notice * 60 + UPDATE_COORDINATION_BARRIER_EXTRA_SECONDS))

  echo "[INFO] Waiting for every running update participant to finish its notice and verified shutdown (timeout: ${timeout_seconds}s)..."
  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    if update_coordination_all_participants_ready; then
      echo "[SUCCESS] Every snapshotted participant reached the verified shutdown barrier."
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  update_coordination_mark_failed "Timed out waiting for all running instances to complete the verified pre-update shutdown barrier" || true
  return 1
}

update_coordination_waiting_flag_file() {
  echo "${UPDATE_COORDINATION_WAITING_FLAG_FILE:-/home/pok/.update_coordination_waiting}"
}

update_coordination_epoch() {
  date +%s
}

update_coordination_mkdirs() {
  mkdir -p "$(update_coordination_current_dir)" "$(update_coordination_cycles_dir)" "$(update_coordination_instances_dir)"
}

update_coordination_reset_state() {
  UPDATE_COORDINATION_STATE_PRESENT=0
  UPDATE_COORDINATION_STATE_CYCLE_ID=""
  UPDATE_COORDINATION_STATE_TARGET_BUILD_ID=""
  UPDATE_COORDINATION_STATE_ACTIVE_LEADER_INSTANCE=""
  UPDATE_COORDINATION_STATE_ACTIVE_LEADER_PRIORITY=""
  UPDATE_COORDINATION_STATE_ATTEMPT_COUNT=0
  UPDATE_COORDINATION_STATE_ATTEMPTED_PRIORITIES=""
  UPDATE_COORDINATION_STATE_ATTEMPTED_INSTANCES=""
  UPDATE_COORDINATION_STATE_PHASE=""
  UPDATE_COORDINATION_STATE_PHASE_STARTED_AT=0
  UPDATE_COORDINATION_STATE_LAST_HEARTBEAT_AT=0
  UPDATE_COORDINATION_STATE_FAIL_REASON=""
}

update_coordination_refresh_state() {
  local state_file
  state_file="$(update_coordination_state_file)"

  update_coordination_reset_state

  if [ ! -f "$state_file" ]; then
    return 1
  fi

  # shellcheck disable=SC1090
  source "$state_file"

  UPDATE_COORDINATION_STATE_PRESENT=1
  UPDATE_COORDINATION_STATE_CYCLE_ID="${CYCLE_ID:-}"
  UPDATE_COORDINATION_STATE_TARGET_BUILD_ID="${TARGET_BUILD_ID:-}"
  UPDATE_COORDINATION_STATE_ACTIVE_LEADER_INSTANCE="${ACTIVE_LEADER_INSTANCE:-}"
  UPDATE_COORDINATION_STATE_ACTIVE_LEADER_PRIORITY="${ACTIVE_LEADER_PRIORITY:-}"
  UPDATE_COORDINATION_STATE_ATTEMPT_COUNT="${ATTEMPT_COUNT:-0}"
  UPDATE_COORDINATION_STATE_ATTEMPTED_PRIORITIES="${ATTEMPTED_PRIORITIES:-}"
  UPDATE_COORDINATION_STATE_ATTEMPTED_INSTANCES="${ATTEMPTED_INSTANCES:-}"
  UPDATE_COORDINATION_STATE_PHASE="${PHASE:-}"
  UPDATE_COORDINATION_STATE_PHASE_STARTED_AT="${PHASE_STARTED_AT:-0}"
  UPDATE_COORDINATION_STATE_LAST_HEARTBEAT_AT="${LAST_HEARTBEAT_AT:-0}"
  UPDATE_COORDINATION_STATE_FAIL_REASON="${FAIL_REASON:-}"
  return 0
}

update_coordination_save_state() {
  local state_file
  local tmp_file
  state_file="$(update_coordination_state_file)"
  tmp_file="${state_file}.tmp"

  update_coordination_mkdirs

  {
    printf 'CYCLE_ID=%q\n' "${UPDATE_COORDINATION_STATE_CYCLE_ID}"
    printf 'TARGET_BUILD_ID=%q\n' "${UPDATE_COORDINATION_STATE_TARGET_BUILD_ID}"
    printf 'ACTIVE_LEADER_INSTANCE=%q\n' "${UPDATE_COORDINATION_STATE_ACTIVE_LEADER_INSTANCE}"
    printf 'ACTIVE_LEADER_PRIORITY=%q\n' "${UPDATE_COORDINATION_STATE_ACTIVE_LEADER_PRIORITY}"
    printf 'ATTEMPT_COUNT=%q\n' "${UPDATE_COORDINATION_STATE_ATTEMPT_COUNT}"
    printf 'ATTEMPTED_PRIORITIES=%q\n' "${UPDATE_COORDINATION_STATE_ATTEMPTED_PRIORITIES}"
    printf 'ATTEMPTED_INSTANCES=%q\n' "${UPDATE_COORDINATION_STATE_ATTEMPTED_INSTANCES}"
    printf 'PHASE=%q\n' "${UPDATE_COORDINATION_STATE_PHASE}"
    printf 'PHASE_STARTED_AT=%q\n' "${UPDATE_COORDINATION_STATE_PHASE_STARTED_AT}"
    printf 'LAST_HEARTBEAT_AT=%q\n' "${UPDATE_COORDINATION_STATE_LAST_HEARTBEAT_AT}"
    printf 'FAIL_REASON=%q\n' "${UPDATE_COORDINATION_STATE_FAIL_REASON}"
  } > "$tmp_file"

  mv "$tmp_file" "$state_file"
}

update_coordination_archive_state_snapshot() {
  local cycle_dir=""

  [ -n "${UPDATE_COORDINATION_STATE_CYCLE_ID:-}" ] || return 0

  cycle_dir="$(update_coordination_cycles_dir)/${UPDATE_COORDINATION_STATE_CYCLE_ID}"
  mkdir -p "$cycle_dir"
  cp "$(update_coordination_state_file)" "$cycle_dir/state.env" 2>/dev/null || true
}

update_coordination_set_phase() {
  local phase="$1"
  UPDATE_COORDINATION_STATE_PHASE="$phase"
  UPDATE_COORDINATION_STATE_PHASE_STARTED_AT="$(update_coordination_epoch)"
  UPDATE_COORDINATION_STATE_LAST_HEARTBEAT_AT="$UPDATE_COORDINATION_STATE_PHASE_STARTED_AT"
  update_coordination_save_state
}

update_coordination_touch_heartbeat() {
  [ "${UPDATE_COORDINATION_STATE_PRESENT:-0}" -eq 1 ] || update_coordination_refresh_state || return 1
  UPDATE_COORDINATION_STATE_LAST_HEARTBEAT_AT="$(update_coordination_epoch)"
  update_coordination_save_state
}

update_coordination_start_heartbeat() {
  update_coordination_stop_heartbeat
  (
    while true; do
      sleep 10
      if ! update_coordination_refresh_state >/dev/null 2>&1; then
        exit 0
      fi
      update_coordination_touch_heartbeat >/dev/null 2>&1 || exit 0
    done
  ) &
  UPDATE_COORDINATION_HEARTBEAT_PID=$!
  export UPDATE_COORDINATION_HEARTBEAT_PID
}

update_coordination_stop_heartbeat() {
  if [ -n "${UPDATE_COORDINATION_HEARTBEAT_PID:-}" ]; then
    kill "${UPDATE_COORDINATION_HEARTBEAT_PID}" 2>/dev/null || true
    wait "${UPDATE_COORDINATION_HEARTBEAT_PID}" 2>/dev/null || true
    unset UPDATE_COORDINATION_HEARTBEAT_PID
  fi
}

update_coordination_priority_seen() {
  local priority="$1"
  case ",${UPDATE_COORDINATION_STATE_ATTEMPTED_PRIORITIES}," in
    *,"${priority}",*)
      return 0
      ;;
  esac
  return 1
}

update_coordination_append_attempt() {
  local instance_name="$1"
  local priority="$2"

  if [ -n "$UPDATE_COORDINATION_STATE_ATTEMPTED_PRIORITIES" ]; then
    UPDATE_COORDINATION_STATE_ATTEMPTED_PRIORITIES="${UPDATE_COORDINATION_STATE_ATTEMPTED_PRIORITIES},${priority}"
    UPDATE_COORDINATION_STATE_ATTEMPTED_INSTANCES="${UPDATE_COORDINATION_STATE_ATTEMPTED_INSTANCES},${instance_name}"
  else
    UPDATE_COORDINATION_STATE_ATTEMPTED_PRIORITIES="${priority}"
    UPDATE_COORDINATION_STATE_ATTEMPTED_INSTANCES="${instance_name}"
  fi
}

update_coordination_mark_waiting() {
  local waiting_file
  waiting_file="$(update_coordination_waiting_flag_file)"
  mkdir -p "$(dirname "$waiting_file")"
  {
    printf 'INSTANCE_NAME=%s\n' "${INSTANCE_NAME:-}"
    printf 'ROLE=%s\n' "${UPDATE_COORDINATION_ROLE:-}"
    printf 'PRIORITY=%s\n' "${UPDATE_COORDINATION_PRIORITY:-}"
    printf 'WAIT_STARTED_AT=%s\n' "$(update_coordination_epoch)"
  } > "$waiting_file"
}

update_coordination_clear_waiting() {
  rm -f "$(update_coordination_waiting_flag_file)"
}

update_coordination_is_waiting() {
  [ -f "$(update_coordination_waiting_flag_file)" ]
}

update_coordination_begin_cycle() {
  local target_build="$1"
  local now=""

  update_coordination_enabled || return 1
  update_coordination_is_master_role || return 1
  update_coordination_mkdirs
  update_coordination_cleanup

  if update_coordination_refresh_state; then
    case "${UPDATE_COORDINATION_STATE_PHASE}" in
      pending_restart|leader_updating|leader_starting)
        if [ "${UPDATE_COORDINATION_STATE_ACTIVE_LEADER_INSTANCE}" = "${INSTANCE_NAME}" ]; then
          return 0
        fi
        return 1
        ;;
    esac
  fi

  now="$(update_coordination_epoch)"
  UPDATE_COORDINATION_STATE_PRESENT=1
  UPDATE_COORDINATION_STATE_CYCLE_ID="${now}-${INSTANCE_NAME}"
  UPDATE_COORDINATION_STATE_TARGET_BUILD_ID="$target_build"
  UPDATE_COORDINATION_STATE_ACTIVE_LEADER_INSTANCE="${INSTANCE_NAME}"
  UPDATE_COORDINATION_STATE_ACTIVE_LEADER_PRIORITY="${UPDATE_COORDINATION_PRIORITY}"
  UPDATE_COORDINATION_STATE_ATTEMPT_COUNT=1
  UPDATE_COORDINATION_STATE_ATTEMPTED_PRIORITIES=""
  UPDATE_COORDINATION_STATE_ATTEMPTED_INSTANCES=""
  UPDATE_COORDINATION_STATE_FAIL_REASON=""
  update_coordination_append_attempt "${INSTANCE_NAME}" "${UPDATE_COORDINATION_PRIORITY}"
  update_coordination_set_phase "pending_restart"
  update_coordination_archive_state_snapshot
  update_coordination_snapshot_live_participants
}

update_coordination_has_active_cycle() {
  if ! update_coordination_refresh_state; then
    return 1
  fi

  case "${UPDATE_COORDINATION_STATE_PHASE}" in
    pending_restart|leader_updating|leader_starting)
      return 0
      ;;
  esac

  return 1
}

update_coordination_build_matches() {
  local target_build="$1"

  if [ -z "$target_build" ] || [ -z "${UPDATE_COORDINATION_STATE_TARGET_BUILD_ID:-}" ]; then
    return 0
  fi

  [ "${UPDATE_COORDINATION_STATE_TARGET_BUILD_ID:-}" = "$target_build" ]
}

update_coordination_wait_for_master_cycle() {
  local target_build="$1"
  local timeout_seconds="${2:-$UPDATE_COORDINATION_FOLLOWER_WAIT_FOR_MASTER_SECONDS}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    if update_coordination_has_active_cycle && update_coordination_build_matches "$target_build"; then
      return 0
    fi

    sleep 5
    elapsed=$((elapsed + 5))
  done

  return 1
}

update_coordination_leader_stale() {
  local now heartbeat_age phase_age phase_timeout

  update_coordination_refresh_state || return 1
  now="$(update_coordination_epoch)"
  heartbeat_age=$((now - ${UPDATE_COORDINATION_STATE_LAST_HEARTBEAT_AT:-0}))
  phase_age=$((now - ${UPDATE_COORDINATION_STATE_PHASE_STARTED_AT:-0}))

  case "${UPDATE_COORDINATION_STATE_PHASE}" in
    leader_updating)
      phase_timeout="$UPDATE_COORDINATION_UPDATE_TIMEOUT_SECONDS"
      ;;
    leader_starting|pending_restart)
      phase_timeout="$UPDATE_COORDINATION_STARTUP_TIMEOUT_SECONDS"
      ;;
    *)
      return 1
      ;;
  esac

  [ "$heartbeat_age" -ge "$UPDATE_COORDINATION_HEARTBEAT_STALE_SECONDS" ] || [ "$phase_age" -ge "$phase_timeout" ]
}

update_coordination_should_promote_self() {
  local self_priority="${UPDATE_COORDINATION_PRIORITY}"
  local lower_priority=1

  update_coordination_enabled || return 1
  update_coordination_is_follower_role || return 1
  update_coordination_refresh_state || return 1

  [ "${UPDATE_COORDINATION_STATE_ATTEMPT_COUNT}" -lt "$UPDATE_COORDINATION_MAX_ATTEMPTS" ] || return 1
  update_coordination_leader_stale || return 1
  update_coordination_priority_seen "$self_priority" && return 1

  while [ "$lower_priority" -lt "$self_priority" ]; do
    if ! update_coordination_priority_seen "$lower_priority"; then
      return 1
    fi
    lower_priority=$((lower_priority + 1))
  done

  return 0
}

update_coordination_take_claim_lock() {
  mkdir "$(update_coordination_claim_dir)" 2>/dev/null
}

update_coordination_release_claim_lock() {
  rmdir "$(update_coordination_claim_dir)" 2>/dev/null || true
}

update_coordination_promote_self() {
  update_coordination_should_promote_self || return 1
  update_coordination_take_claim_lock || return 1

  update_coordination_refresh_state || {
    update_coordination_release_claim_lock
    return 1
  }

  if ! update_coordination_should_promote_self; then
    update_coordination_release_claim_lock
    return 1
  fi

  UPDATE_COORDINATION_STATE_ACTIVE_LEADER_INSTANCE="${INSTANCE_NAME}"
  UPDATE_COORDINATION_STATE_ACTIVE_LEADER_PRIORITY="${UPDATE_COORDINATION_PRIORITY}"
  UPDATE_COORDINATION_STATE_ATTEMPT_COUNT=$((UPDATE_COORDINATION_STATE_ATTEMPT_COUNT + 1))
  update_coordination_append_attempt "${INSTANCE_NAME}" "${UPDATE_COORDINATION_PRIORITY}"
  UPDATE_COORDINATION_STATE_FAIL_REASON=""
  update_coordination_set_phase "leader_updating"
  update_coordination_archive_state_snapshot
  update_coordination_release_claim_lock
  return 0
}

update_coordination_followers_start_delay() {
  local min_delay="${UPDATE_COORDINATION_FOLLOWER_JITTER_MIN_SECONDS}"
  local max_delay="${UPDATE_COORDINATION_FOLLOWER_JITTER_MAX_SECONDS}"
  local delta=0

  if [ "$max_delay" -le "$min_delay" ]; then
    sleep "$min_delay"
    return 0
  fi

  delta=$((max_delay - min_delay + 1))
  sleep $((min_delay + (RANDOM % delta)))
}

update_coordination_is_active_leader() {
  update_coordination_refresh_state || return 1
  [ "${UPDATE_COORDINATION_STATE_ACTIVE_LEADER_INSTANCE}" = "${INSTANCE_NAME}" ]
}

update_coordination_write_failure_report() {
  local reason="$1"
  local cycle_dir=""
  local report_file=""
  local api_log

  update_coordination_refresh_state || return 1
  [ -n "${UPDATE_COORDINATION_STATE_CYCLE_ID:-}" ] || return 1

  cycle_dir="$(update_coordination_cycles_dir)/${UPDATE_COORDINATION_STATE_CYCLE_ID}"
  report_file="${cycle_dir}/failure_report.txt"
  mkdir -p "$cycle_dir"

  {
    echo "Cycle ID: ${UPDATE_COORDINATION_STATE_CYCLE_ID}"
    echo "Target Build ID: ${UPDATE_COORDINATION_STATE_TARGET_BUILD_ID}"
    echo "Failed Phase: ${UPDATE_COORDINATION_STATE_PHASE}"
    echo "Attempt Count: ${UPDATE_COORDINATION_STATE_ATTEMPT_COUNT}"
    echo "Attempted Priorities: ${UPDATE_COORDINATION_STATE_ATTEMPTED_PRIORITIES}"
    echo "Attempted Instances: ${UPDATE_COORDINATION_STATE_ATTEMPTED_INSTANCES}"
    echo "Active Leader Instance: ${UPDATE_COORDINATION_STATE_ACTIVE_LEADER_INSTANCE}"
    echo "Active Leader Priority: ${UPDATE_COORDINATION_STATE_ACTIVE_LEADER_PRIORITY}"
    echo "Failure Reason: ${reason}"
    echo ""
    echo "===== ShooterGame.log ====="
    tail -n 200 "${ASA_DIR}/ShooterGame/Saved/Logs/ShooterGame.log" 2>/dev/null || true
    echo ""
    echo "===== API Logs ====="
    for api_log in "${ASA_DIR}"/ShooterGame/Binaries/Win64/logs/*.log; do
      [ -f "$api_log" ] || continue
      echo "--- $(basename "$api_log") ---"
      tail -n 200 "$api_log" 2>/dev/null || true
    done
    echo ""
    echo "===== CrashCallStack.txt ====="
    tail -n 200 "${ASA_DIR}/ShooterGame/Saved/Logs/CrashCallStack.txt" 2>/dev/null || true
    echo ""
    echo "===== Crash Artifacts ====="
    find "${ASA_DIR}" -maxdepth 6 \( -name "CrashCallStack.txt" -o -name "CrashContext.runtime-xml" -o -path "*/Saved/Crashes/*" \) 2>/dev/null || true
  } > "$report_file"

  update_coordination_archive_state_snapshot
}

update_coordination_mark_failed() {
  local reason="$1"

  update_coordination_refresh_state || return 1
  UPDATE_COORDINATION_STATE_PHASE="failed"
  UPDATE_COORDINATION_STATE_PHASE_STARTED_AT="$(update_coordination_epoch)"
  UPDATE_COORDINATION_STATE_LAST_HEARTBEAT_AT="$UPDATE_COORDINATION_STATE_PHASE_STARTED_AT"
  UPDATE_COORDINATION_STATE_FAIL_REASON="$reason"
  update_coordination_save_state
  update_coordination_write_failure_report "$reason"
}

update_coordination_mark_ready() {
  update_coordination_refresh_state || return 1
  UPDATE_COORDINATION_STATE_FAIL_REASON=""
  update_coordination_set_phase "ready"
  update_coordination_archive_state_snapshot
}

update_coordination_mark_leader_starting() {
  update_coordination_refresh_state || return 1
  update_coordination_set_phase "leader_starting"
  update_coordination_archive_state_snapshot
}

update_coordination_wait_until_ready_or_promoted() {
  local reason=""

  while true; do
    if ! update_coordination_refresh_state; then
      return 1
    fi

    case "${UPDATE_COORDINATION_STATE_PHASE}" in
      ready)
        return 0
        ;;
      failed)
        return 3
        ;;
      pending_restart|leader_updating|leader_starting)
        if update_coordination_leader_stale; then
          if [ "${UPDATE_COORDINATION_STATE_ATTEMPT_COUNT}" -ge "$UPDATE_COORDINATION_MAX_ATTEMPTS" ]; then
            reason="Coordination cycle exceeded ${UPDATE_COORDINATION_MAX_ATTEMPTS} total leader attempts"
            update_coordination_mark_failed "$reason"
            return 1
          fi

          if update_coordination_promote_self; then
            return 2
          fi
        fi
        ;;
    esac

    sleep 5
  done
}

update_coordination_cleanup() {
  local root current_dir state_file now phase_age
  root="$(update_coordination_root)"
  current_dir="$(update_coordination_current_dir)"
  state_file="$(update_coordination_state_file)"
  now="$(update_coordination_epoch)"

  mkdir -p "$(update_coordination_cycles_dir)"

  find "$(update_coordination_cycles_dir)" -mindepth 1 -maxdepth 1 -type d \
    -mmin +$((UPDATE_COORDINATION_COMPLETED_RETENTION_SECONDS / 60)) -exec rm -rf {} + 2>/dev/null || true

  if [ -f "$state_file" ] && update_coordination_refresh_state; then
    phase_age=$((now - ${UPDATE_COORDINATION_STATE_PHASE_STARTED_AT:-0}))
    case "${UPDATE_COORDINATION_STATE_PHASE}" in
      ready|failed)
        if [ "$phase_age" -ge "$UPDATE_COORDINATION_COMPLETED_RETENTION_SECONDS" ]; then
          rm -f "$state_file"
          update_coordination_release_claim_lock
        fi
        ;;
      pending_restart|leader_updating|leader_starting)
        if [ "$phase_age" -ge "$UPDATE_COORDINATION_COMPLETED_RETENTION_SECONDS" ]; then
          update_coordination_mark_failed "Abandoned coordination cycle cleaned up after retention threshold"
        fi
        ;;
    esac
  fi

  [ -d "$current_dir" ] || mkdir -p "$current_dir"
}
