#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "monitor_health_read_state classifies degraded probe output" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/monitor_health.sh"
    monitor_health_probe_command() {
      echo "degraded: rcon connection failed"
      return 0
    }
    monitor_health_read_state
  '

  assert_success
  assert_output --partial "degraded"
  assert_output --partial "degraded: rcon connection failed"
}

@test "monitor_health_track_state triggers recovery only after the threshold is reached" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/monitor_health.sh"
    MONITOR_HEALTH_FAILURE_THRESHOLD=3
    for state in unhealthy unhealthy unhealthy; do
      set +e
      monitor_health_track_state "$state"
      status=$?
      set -e
      echo "status=$status count=$MONITOR_HEALTH_FAILURE_COUNT"
    done
  '

  assert_success
  assert_output --partial "status=1 count=1"
  assert_output --partial "status=1 count=2"
  assert_output --partial "status=0 count=3"
}

@test "monitor_health_track_state resets hard failures on degraded state" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/monitor_health.sh"
    MONITOR_HEALTH_FAILURE_THRESHOLD=3
    monitor_health_track_state unhealthy || true
    monitor_health_track_state unhealthy || true
    set +e
    monitor_health_track_state degraded
    status=$?
    set -e
    echo "status=$status count=$MONITOR_HEALTH_FAILURE_COUNT"
  '

  assert_success
  assert_output --partial "status=1 count=0"
}

@test "monitor_health_should_log_state suppresses repeated degraded messages but not repeated unhealthy ones" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/monitor_health.sh"
    set +e
    monitor_health_should_log_state degraded "degraded: rcon connection failed"
    first=$?
    monitor_health_should_log_state degraded "degraded: rcon connection failed"
    second=$?
    monitor_health_should_log_state unhealthy "unhealthy: startup marker timed out"
    third=$?
    monitor_health_should_log_state unhealthy "unhealthy: startup marker timed out"
    fourth=$?
    set -e
    echo "first=$first second=$second third=$third fourth=$fourth"
  '

  assert_success
  assert_output --partial "first=0 second=1 third=0 fourth=0"
}

@test "monitor_health_note_degraded persists the degraded episode state" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/monitor_health.sh"
    ASA_DIR="$BATS_TEST_TMPDIR/arkserver"
    monitor_health_now() { echo 1700000000; }
    monitor_health_note_degraded
    monitor_health_load_state
    echo "started=$MONITOR_DEGRADED_STARTED_AT active=$MONITOR_DEGRADED_EPISODE_ACTIVE attempted=$MONITOR_DEGRADED_RECOVERY_ATTEMPTED"
  '

  assert_success
  assert_output --partial "started=1700000000 active=1 attempted=0"
}

@test "monitor_health_should_trigger_degraded_recovery returns true after 24 hours without a prior attempt" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/monitor_health.sh"
    ASA_DIR="$BATS_TEST_TMPDIR/arkserver"
    MONITOR_DEGRADED_RECOVERY_GRACE_SECONDS=86400
    MONITOR_DEGRADED_EPISODE_ACTIVE=1
    MONITOR_DEGRADED_STARTED_AT=100
    MONITOR_DEGRADED_RECOVERY_ATTEMPTED=0
    set +e
    monitor_health_should_trigger_degraded_recovery 86500
    status=$?
    set -e
    echo "status=$status"
  '

  assert_success
  assert_output --partial "status=0"
}

@test "monitor_health_mark_degraded_recovery_attempted prevents another degraded recovery in the same episode" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/monitor_health.sh"
    ASA_DIR="$BATS_TEST_TMPDIR/arkserver"
    MONITOR_DEGRADED_EPISODE_ACTIVE=1
    MONITOR_DEGRADED_STARTED_AT=100
    monitor_health_mark_degraded_recovery_attempted 90000
    set +e
    monitor_health_should_trigger_degraded_recovery 200000
    status=$?
    set -e
    echo "status=$status attempted=$MONITOR_DEGRADED_RECOVERY_ATTEMPTED attempted_at=$MONITOR_DEGRADED_RECOVERY_ATTEMPTED_AT"
  '

  assert_success
  assert_output --partial "status=1 attempted=1 attempted_at=90000"
}

@test "monitor_health_clear_degraded_state resets and removes persisted degraded recovery data" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/monitor_health.sh"
    ASA_DIR="$BATS_TEST_TMPDIR/arkserver"
    MONITOR_DEGRADED_EPISODE_ACTIVE=1
    MONITOR_DEGRADED_STARTED_AT=100
    MONITOR_DEGRADED_RECOVERY_ATTEMPTED=1
    monitor_health_save_state
    monitor_health_clear_degraded_state
    if [ -f "$(monitor_health_state_file)" ]; then
      echo "state-file-still-exists"
      exit 1
    fi
    echo "active=$MONITOR_DEGRADED_EPISODE_ACTIVE started=$MONITOR_DEGRADED_STARTED_AT attempted=$MONITOR_DEGRADED_RECOVERY_ATTEMPTED"
  '

  assert_success
  assert_output --partial "active=0 started=0 attempted=0"
}
