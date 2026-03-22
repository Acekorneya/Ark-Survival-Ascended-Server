#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "monitor_ark_server.sh exits cleanly when UPDATE_SERVER is disabled" {
  run env \
    INSTANCE_NAME=test \
    UPDATE_SERVER=FALSE \
    RCON_PORT=27020 \
    SERVER_ADMIN_PASSWORD=secret \
    SERVER_PASSWORD='' \
    MOD_IDS='' \
    bash "$PROJECT_ROOT/scripts/monitor_ark_server.sh"

  assert_success
  assert_output --partial "UPDATE_SERVER disabled; skipping update monitor."
}

@test "handle_monitor_health_state triggers one delayed recovery restart for a long-lived degraded server" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/monitor_ark_server.sh"
    DISPLAY_POK_MONITOR_MESSAGE=TRUE
    MONITOR_DEGRADED_RECOVERY_GRACE_SECONDS=86400
    monitor_health_track_state() { return 1; }
    monitor_health_note_degraded() { return 1; }
    monitor_health_should_trigger_degraded_recovery() { return 0; }
    monitor_health_mark_degraded_recovery_attempted() { echo "mark-attempted"; }
    monitor_health_degraded_elapsed_seconds() { echo 90061; }
    monitor_health_should_log_post_recovery_degraded() { return 1; }
    monitor_health_should_log_state() { return 1; }
    display_monitor_status() { echo "display:$1"; }
    recover_server() { echo "recover-called"; }
    handle_monitor_health_state degraded "degraded: rcon connection failed"
  '

  assert_success
  assert_output --partial "mark-attempted"
  assert_output --partial "restarting once to restore local RCON"
  assert_output --partial "recover-called"
}

@test "handle_monitor_health_state logs and keeps running when degraded persists after the one automatic recovery restart" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/monitor_ark_server.sh"
    DISPLAY_POK_MONITOR_MESSAGE=TRUE
    monitor_health_track_state() { return 1; }
    monitor_health_note_degraded() { return 1; }
    monitor_health_should_trigger_degraded_recovery() { return 1; }
    monitor_health_should_log_post_recovery_degraded() { return 0; }
    monitor_health_mark_post_recovery_degraded_logged() { echo "marked-post-recovery"; }
    monitor_health_should_log_state() { return 1; }
    display_monitor_status() { echo "display:$1"; }
    recover_server() { echo "recover-called"; }
    handle_monitor_health_state degraded "degraded: rcon connection failed"
  '

  assert_success
  assert_output --partial "marked-post-recovery"
  assert_output --partial "still degraded after the automatic recovery restart"
  refute_output --partial "recover-called"
}

@test "handle_monitor_health_state clears degraded tracking once the server becomes healthy again" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/monitor_ark_server.sh"
    DISPLAY_POK_MONITOR_MESSAGE=TRUE
    MONITOR_DEGRADED_EPISODE_ACTIVE=1
    monitor_health_track_state() { return 1; }
    monitor_health_clear_degraded_state() { echo "cleared-degraded"; MONITOR_DEGRADED_EPISODE_ACTIVE=0; }
    monitor_health_should_log_state() { return 0; }
    display_monitor_status() { echo "display:$1"; }
    handle_monitor_health_state ok "ok: server ready and responding to rcon"
    echo "active=$MONITOR_DEGRADED_EPISODE_ACTIVE"
  '

  assert_success
  assert_output --partial "cleared-degraded"
  assert_output --partial "active=0"
}
