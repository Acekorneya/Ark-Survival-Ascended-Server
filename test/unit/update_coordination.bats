#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "update_coordination_enabled ignores instances with UPDATE_SERVER disabled" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/update_coordination.sh"
    UPDATE_SERVER=FALSE
    UPDATE_COORDINATION_ROLE=MASTER
    UPDATE_COORDINATION_PRIORITY=1
    set +e
    update_coordination_enabled
    status=$?
    set -e
    echo "status=$status"
  '

  assert_success
  assert_output --partial "status=1"
}

@test "update_coordination_enabled ignores instances that do not define manager-written coordination envs" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/update_coordination.sh"
    UPDATE_SERVER=TRUE
    unset UPDATE_COORDINATION_ROLE
    unset UPDATE_COORDINATION_PRIORITY
    set +e
    update_coordination_enabled
    status=$?
    set -e
    echo "status=$status"
  '

  assert_success
  assert_output --partial "status=1"
}

@test "update_coordination_begin_cycle creates a pending master-led cycle" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/update_coordination.sh"
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    UPDATE_SERVER=TRUE
    UPDATE_COORDINATION_ROLE=MASTER
    UPDATE_COORDINATION_PRIORITY=1
    INSTANCE_NAME=alpha
    update_coordination_begin_cycle 12345
    update_coordination_refresh_state
    printf "leader=%s\n" "$UPDATE_COORDINATION_STATE_ACTIVE_LEADER_INSTANCE"
    printf "phase=%s\n" "$UPDATE_COORDINATION_STATE_PHASE"
    printf "attempts=%s\n" "$UPDATE_COORDINATION_STATE_ATTEMPT_COUNT"
    printf "target=%s\n" "$UPDATE_COORDINATION_STATE_TARGET_BUILD_ID"
  '

  assert_success
  assert_output --partial "leader=alpha"
  assert_output --partial "phase=pending_restart"
  assert_output --partial "attempts=1"
  assert_output --partial "target=12345"
}

@test "update_coordination_wait_for_master_cycle accepts the active cycle when no target build is provided" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/update_coordination.sh"
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    UPDATE_SERVER=TRUE
    UPDATE_COORDINATION_ROLE=FOLLOWER
    UPDATE_COORDINATION_PRIORITY=2
    update_coordination_mkdirs
    cat > "$(update_coordination_state_file)" <<EOF
CYCLE_ID=cycle-0
TARGET_BUILD_ID=12345
ACTIVE_LEADER_INSTANCE=alpha
ACTIVE_LEADER_PRIORITY=1
ATTEMPT_COUNT=1
ATTEMPTED_PRIORITIES=1
ATTEMPTED_INSTANCES=alpha
PHASE=leader_updating
PHASE_STARTED_AT=10
LAST_HEARTBEAT_AT=10
FAIL_REASON=
EOF
    set +e
    update_coordination_wait_for_master_cycle "" 1
    status=$?
    set -e
    echo "status=$status"
  '

  assert_success
  assert_output --partial "status=0"
}

@test "update_coordination waiting flag helpers persist and clear follower wait state" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/update_coordination.sh"
    UPDATE_COORDINATION_WAITING_FLAG_FILE="$BATS_TEST_TMPDIR/update-waiting.flag"
    INSTANCE_NAME=beta
    UPDATE_COORDINATION_ROLE=FOLLOWER
    UPDATE_COORDINATION_PRIORITY=2
    update_coordination_mark_waiting
    if update_coordination_is_waiting; then
      echo "waiting=yes"
    fi
    update_coordination_clear_waiting
    if update_coordination_is_waiting; then
      echo "waiting=still-present"
    else
      echo "waiting=cleared"
    fi
  '

  assert_success
  assert_output --partial "waiting=yes"
  assert_output --partial "waiting=cleared"
}

@test "update_coordination_wait_until_ready_or_promoted promotes the next follower when the leader is stale" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/update_coordination.sh"
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    UPDATE_SERVER=TRUE
    UPDATE_COORDINATION_ROLE=FOLLOWER
    UPDATE_COORDINATION_PRIORITY=2
    INSTANCE_NAME=beta
    update_coordination_epoch() { echo 1000; }
    update_coordination_mkdirs
    cat > "$(update_coordination_state_file)" <<EOF
CYCLE_ID=cycle-1
TARGET_BUILD_ID=12345
ACTIVE_LEADER_INSTANCE=alpha
ACTIVE_LEADER_PRIORITY=1
ATTEMPT_COUNT=1
ATTEMPTED_PRIORITIES=1
ATTEMPTED_INSTANCES=alpha
PHASE=leader_starting
PHASE_STARTED_AT=1
LAST_HEARTBEAT_AT=1
FAIL_REASON=
EOF
    set +e
    update_coordination_wait_until_ready_or_promoted
    status=$?
    set -e
    update_coordination_refresh_state
    printf "status=%s\n" "$status"
    printf "leader=%s\n" "$UPDATE_COORDINATION_STATE_ACTIVE_LEADER_INSTANCE"
    printf "attempts=%s\n" "$UPDATE_COORDINATION_STATE_ATTEMPT_COUNT"
    printf "phase=%s\n" "$UPDATE_COORDINATION_STATE_PHASE"
  '

  assert_success
  assert_output --partial "status=2"
  assert_output --partial "leader=beta"
  assert_output --partial "attempts=2"
  assert_output --partial "phase=leader_updating"
}

@test "update_coordination_wait_until_ready_or_promoted fails the cycle after the third total leader attempt" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/update_coordination.sh"
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    UPDATE_SERVER=TRUE
    UPDATE_COORDINATION_ROLE=FOLLOWER
    UPDATE_COORDINATION_PRIORITY=4
    INSTANCE_NAME=delta
    update_coordination_epoch() { echo 1000; }
    update_coordination_mkdirs
    mkdir -p "$ASA_DIR/ShooterGame/Saved/Logs" "$ASA_DIR/ShooterGame/Binaries/Win64/logs"
    cat > "$(update_coordination_state_file)" <<EOF
CYCLE_ID=cycle-2
TARGET_BUILD_ID=99999
ACTIVE_LEADER_INSTANCE=charlie
ACTIVE_LEADER_PRIORITY=3
ATTEMPT_COUNT=3
ATTEMPTED_PRIORITIES=1,2,3
ATTEMPTED_INSTANCES=alpha,beta,charlie
PHASE=leader_starting
PHASE_STARTED_AT=1
LAST_HEARTBEAT_AT=1
FAIL_REASON=
EOF
    set +e
    update_coordination_wait_until_ready_or_promoted
    status=$?
    set -e
    update_coordination_refresh_state
    printf "status=%s\n" "$status"
    printf "phase=%s\n" "$UPDATE_COORDINATION_STATE_PHASE"
    printf "reason=%s\n" "$UPDATE_COORDINATION_STATE_FAIL_REASON"
  '

  assert_success
  assert_output --partial "status=1"
  assert_output --partial "phase=failed"
  assert_output --partial "reason=Coordination cycle exceeded 3 total leader attempts"
}
