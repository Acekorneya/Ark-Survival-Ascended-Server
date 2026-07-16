#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "install_server.sh can be sourced without executing the installer" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/install_server.sh"
    printf "main=%s\n" "$(type -t main)"
  '

  assert_success
  assert_output --partial "main=function"
}

@test "install_required returns 1 when the installed and current build IDs match" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/install_server.sh"
    get_build_id_from_acf() { echo 12345; }
    get_current_build_id() { echo 12345; }
    set +e
    install_required
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "Server files already match the latest build"
  assert_output --partial "status=1"
}

@test "install_required returns 0 when the current build ID is unavailable" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/install_server.sh"
    get_build_id_from_acf() { echo 12345; }
    get_current_build_id() { echo error-network; }
    set +e
    install_required
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "Current build ID unavailable; proceeding with staged download as precaution"
  assert_output --partial "status=0"
}

@test "install_required holds an unchanged rollback deployment" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/install_server.sh"
    get_build_id_from_acf() { echo 12345; }
    get_current_build_id() { echo 12345; }
    rollback_state_is_active() { return 0; }
    rollback_retry_is_available() { return 1; }
    set +e
    install_required
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "Rollback protection remains active"
  assert_output --partial "status=1"
}

@test "install_required forces staging when rollback retry becomes eligible" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/install_server.sh"
    get_build_id_from_acf() { echo 12345; }
    get_current_build_id() { echo 12346; }
    rollback_state_is_active() { return 0; }
    rollback_retry_is_available() { return 0; }
    install_required
  '

  assert_success
  assert_output --partial "rollback-protected candidate is eligible"
}

@test "wait_for_other_install_if_needed exits early when another instance finished the update" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/install_server.sh"
    wait_for_update_lock() { return 0; }
    install_required() { return 1; }
    set +e
    wait_for_other_install_if_needed
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "Peer completed installation; nothing more to do"
  assert_output --partial "status=2"
}

@test "wait_for_other_install_if_needed reacquires the lock when the update is still required" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/install_server.sh"
    wait_for_update_lock() { return 0; }
    install_required() { return 0; }
    acquire_update_lock() { return 0; }
    set +e
    wait_for_other_install_if_needed
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "lock_held=%s\n" "$LOCK_HELD"
  '

  assert_success
  assert_output --partial "Update still required after peer completed. Attempting to acquire lock again"
  assert_output --partial "status=0"
  assert_output --partial "lock_held=true"
}

@test "install_server_wait_for_coordination_release keeps followers on the coordination path and skips the legacy lock" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/install_server.sh"
    update_coordination_mark_waiting() { echo "mark-waiting"; }
    update_coordination_wait_for_master_cycle() { echo "wait-cycle:$1"; return 0; }
    update_coordination_wait_until_ready_or_promoted() { echo "wait-ready"; return 0; }
    update_coordination_clear_waiting() { echo "clear-waiting"; }
    update_coordination_followers_start_delay() { echo "follower-jitter"; }
    install_required() { return 1; }
    acquire_update_lock() { echo "legacy-lock"; return 0; }
    set +e
    install_server_wait_for_coordination_release 12345
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "mark-waiting"
  assert_output --partial "wait-cycle:12345"
  assert_output --partial "wait-ready"
  assert_output --partial "clear-waiting"
  assert_output --partial "follower-jitter"
  assert_output --partial "Leader already updated the shared server files. Follower can continue startup."
  assert_output --partial "status=2"
  refute_output --partial "legacy-lock"
}

@test "install_server_wait_for_coordination_release promotes the follower when the leader goes stale" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/install_server.sh"
    update_coordination_mark_waiting() { :; }
    update_coordination_wait_for_master_cycle() { return 0; }
    update_coordination_wait_until_ready_or_promoted() { return 2; }
    update_coordination_clear_waiting() { echo "clear-waiting"; }
    set +e
    install_server_wait_for_coordination_release 12345
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "leader=%s\n" "$COORDINATION_LEADER"
  '

  assert_success
  assert_output --partial "Promoted this follower to coordination leader for the current cycle"
  assert_output --partial "clear-waiting"
  assert_output --partial "status=0"
  assert_output --partial "leader=true"
}

@test "install_server_wait_for_coordination_release prints a clear operator error when a follower starts without a master cycle" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/install_server.sh"
    update_coordination_mark_waiting() { :; }
    update_coordination_wait_for_master_cycle() { return 1; }
    update_coordination_clear_waiting() { echo "clear-waiting"; }
    set +e
    install_server_wait_for_coordination_release 12345
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "configured as UPDATE_COORDINATION_ROLE=FOLLOWER"
  assert_output --partial "start through ./POK-manager.sh"
  assert_output --partial "change the intended leader instance to UPDATE_COORDINATION_ROLE=MASTER"
  assert_output --partial "clear-waiting"
  assert_output --partial "status=1"
}

@test "startup leader defers live file changes when running participants were snapshotted" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    source "$REPO_ROOT/scripts/install_server.sh"
    prepare_runtime_env() { ASA_DIR="$BATS_TEST_TMPDIR/asa"; mkdir -p "$ASA_DIR"; }
    update_coordination_clear_waiting() { :; }
    update_coordination_cleanup() { :; }
    update_coordination_stop_heartbeat() { :; }
    shared_update_policy_allows_automatic_updates() { return 0; }
    update_coordination_enabled() { return 0; }
    update_coordination_has_active_cycle() { return 1; }
    update_coordination_is_master_role() { return 0; }
    update_coordination_begin_cycle() { echo "cycle=created"; return 0; }
    update_coordination_refresh_state() { UPDATE_COORDINATION_STATE_PHASE=pending_restart; return 0; }
    update_coordination_participant_count() { echo 2; }
    install_required() { return 0; }
    perform_staged_server_download() { echo "unexpected-live-sync"; }
    main
  '

  assert_success
  assert_output --partial "cycle=created"
  assert_output --partial "Deferring the shared-file update"
  refute_output --partial "unexpected-live-sync"
}

@test "leader leaves installed files unchanged when the shutdown barrier fails" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    source "$REPO_ROOT/scripts/install_server.sh"
    prepare_runtime_env() { ASA_DIR="$BATS_TEST_TMPDIR/asa"; mkdir -p "$ASA_DIR"; }
    update_coordination_clear_waiting() { :; }
    update_coordination_cleanup() { :; }
    update_coordination_stop_heartbeat() { :; }
    update_coordination_start_heartbeat() { :; }
    shared_update_policy_allows_automatic_updates() { return 0; }
    update_coordination_enabled() { return 0; }
    update_coordination_has_active_cycle() { return 0; }
    update_coordination_is_active_leader() { return 0; }
    update_coordination_refresh_state() { UPDATE_COORDINATION_STATE_PHASE=pending_restart; return 0; }
    update_coordination_participant_count() { echo 2; }
    update_coordination_wait_for_shutdown_barrier() { echo "barrier=failed"; return 1; }
    install_required() { return 0; }
    perform_staged_server_download() { echo "unexpected-live-sync"; }
    main
  '

  assert_success
  assert_output --partial "barrier=failed"
  assert_output --partial "update aborted"
  refute_output --partial "unexpected-live-sync"
}
