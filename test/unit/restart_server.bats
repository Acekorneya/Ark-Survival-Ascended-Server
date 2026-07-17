#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "restart_server.sh can be sourced without executing the restart flow" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/restart_server.sh"
    printf "main=%s\n" "$(type -t main)"
  '

  assert_success
  assert_output --partial "main=function"
}

@test "initialize_restart_context applies the restart mode and current environment defaults" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/restart_server.sh"
    RESTART_NOTICE_MINUTES=7
    EXIT_ON_API_RESTART=FALSE
    SHOW_ANIMATED_COUNTDOWN=TRUE
    UPDATE_RESTART=FALSE
    initialize_restart_context scheduled
    printf "mode=%s\n" "$RESTART_MODE"
    printf "notice=%s\n" "$RESTART_NOTICE_MINUTES"
    printf "exit_on_api_restart=%s\n" "$EXIT_ON_API_RESTART"
    printf "animated=%s\n" "$SHOW_ANIMATED_COUNTDOWN"
    printf "update_restart=%s\n" "$UPDATE_RESTART"
  '

  assert_success
  assert_output --partial "mode=scheduled"
  assert_output --partial "notice=7"
  assert_output --partial "exit_on_api_restart=FALSE"
  assert_output --partial "animated=TRUE"
  assert_output --partial "update_restart=FALSE"
}

@test "wait_for_shutdown_completion returns success when the shutdown flag appears" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/restart_server.sh"
    SHUTDOWN_COMPLETE_FLAG="$BATS_TEST_TMPDIR/shutdown_complete.flag"
    sleep() {
      touch "$SHUTDOWN_COMPLETE_FLAG"
    }
    wait_for_shutdown_completion
  '

  assert_success
  assert_output --partial "Shutdown complete signal received."
}

@test "restart flow delegates the verified PID 1 handoff" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    if grep -qE "kill[[:space:]]+-9[[:space:]]+1|killall[[:space:]]+-9" "$REPO_ROOT/scripts/restart_server.sh"; then
      echo "sigkill=present"
      exit 1
    fi
    grep -q "request_verified_container_restart" "$REPO_ROOT/scripts/restart_server.sh"
    echo "handoff=verified-helper"
  '

  assert_success
  assert_output --partial "handoff=verified-helper"
}
