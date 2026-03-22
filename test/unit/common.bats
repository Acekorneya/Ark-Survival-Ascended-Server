#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "common.sh source does not auto-clean MOD_IDS or validate password" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    MOD_IDS="123, 456"
    SERVER_PASSWORD="bad!pass"
    source "$REPO_ROOT/scripts/common.sh"
    printf "mod_ids=%s\n" "$MOD_IDS"
    printf "validator=%s\n" "$(type -t validate_server_password)"
  '

  assert_success
  assert_output --partial "mod_ids=123, 456"
  assert_output --partial "validator=function"
}

@test "prepare_runtime_env applies cleanup only when called" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    MOD_IDS="123, 456"
    SERVER_PASSWORD="goodpass"
    INSTANCE_NAME="alpha"
    source "$REPO_ROOT/scripts/common.sh"
    prepare_runtime_env
    printf "mod_ids=%s\n" "$MOD_IDS"
    printf "pid_file=%s\n" "$PID_FILE"
  '

  assert_success
  assert_output --partial "mod_ids=123,456"
  assert_output --partial "pid_file=/home/pok/alpha_ark_server.pid"
}

@test "env_value_is_truthy recognizes supported true values" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/common.sh"
    for value in TRUE true YES yes 1; do
      env_value_is_truthy "$value"
    done
    echo "all=true"
  '

  assert_success
  assert_output --partial "all=true"
}
