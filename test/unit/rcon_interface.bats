#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "rcon_interface.sh can be sourced without executing the CLI wrapper" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_interface.sh"
    printf "main=%s\n" "$(type -t main)"
  '

  assert_success
  assert_output --partial "main=function"
}

@test "main dispatches -saveworld to saveWorld" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_interface.sh"
    prepare_runtime_env() { :; }
    saveWorld() { echo "saveworld-called"; }
    main -saveworld
  '

  assert_success
  assert_output --partial "saveworld-called"
}

@test "main dispatches -chat with the full message" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_interface.sh"
    prepare_runtime_env() { :; }
    sendChat() { printf "chat=%s\n" "$*"; }
    main -chat "hello survivors"
  '

  assert_success
  assert_output --partial "chat=hello survivors"
}

@test "main rejects unknown commands with usage output" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rcon_interface.sh"
    prepare_runtime_env() { :; }
    set +e
    ( main -unknown )
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "Unknown or unsupported command"
  assert_output --partial "Usage:"
  assert_output --partial "status=1"
}
