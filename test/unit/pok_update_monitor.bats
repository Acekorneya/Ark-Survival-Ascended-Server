#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "POK_Update_Monitor.sh can be sourced without running the build check" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/POK_Update_Monitor.sh"
    printf "main=%s\n" "$(type -t main)"
  '

  assert_success
  assert_output --partial "main=function"
}

@test "POK_Update_Monitor main exits 1 when updates are disabled" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/POK_Update_Monitor.sh"
    prepare_runtime_env() { :; }
    UPDATE_SERVER=FALSE
    set +e
    ( main )
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "UPDATE_SERVER disabled; skipping update check."
  assert_output --partial "status=1"
}

@test "POK_Update_Monitor main exits 0 when a newer build is available" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/POK_Update_Monitor.sh"
    prepare_runtime_env() { :; }
    UPDATE_SERVER=TRUE
    DISPLAY_POK_MONITOR_MESSAGE=TRUE
    get_build_id_from_acf() { echo 11111; }
    get_current_build_id() { echo 22222; }
    set +e
    ( main )
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "UPDATE AVAILABLE"
  assert_output --partial "status=0"
}

@test "POK_Update_Monitor main exits 1 when the installed build is current" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/POK_Update_Monitor.sh"
    prepare_runtime_env() { :; }
    UPDATE_SERVER=TRUE
    DISPLAY_POK_MONITOR_MESSAGE=TRUE
    get_build_id_from_acf() { echo 22222; }
    get_current_build_id() { echo 22222; }
    set +e
    ( main )
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "No updates available"
  assert_output --partial "status=1"
}
