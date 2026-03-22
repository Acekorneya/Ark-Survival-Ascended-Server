#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "update_server.sh can be sourced without executing the update workflow" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/update_server.sh"
    printf "main=%s\n" "$(type -t main)"
  '

  assert_success
  assert_output --partial "main=function"
}

@test "server_needs_update returns 0 for dirty-flag restarts and records the current build" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/update_server.sh"
    server_needs_update_or_restart() { return 0; }
    has_dirty_flag() { return 0; }
    get_current_build_id() { echo 24680; }
    set +e
    server_needs_update
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "current=%s\n" "$current_build_id"
  '

  assert_success
  assert_output --partial "RESTART REQUIRED - Instance marked dirty by another instance"
  assert_output --partial "status=0"
  assert_output --partial "current=24680"
}

@test "server_needs_update returns 1 when no update or restart is required" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/update_server.sh"
    server_needs_update_or_restart() { return 1; }
    set +e
    server_needs_update
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "Server is up to date - no update or restart needed"
  assert_output --partial "status=1"
}

@test "notify_players_of_update emits the short countdown sequence" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/update_server.sh"
    sleep() { :; }
    send_rcon_command() {
      printf "msg=%s\n" "$1"
    }
    notify_players_of_update 1
  '

  assert_success
  assert_output --partial "msg=ServerChat Server update detected! Server will restart in 1 minutes for the update."
  assert_output --partial "msg=ServerChat Server restarting in 30 seconds for update..."
  assert_output --partial "msg=ServerChat 5..."
  assert_output --partial "msg=ServerChat Server restarting NOW!"
}
