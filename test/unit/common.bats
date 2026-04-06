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

@test "prepare_runtime_env keeps only the EOS settings still used at runtime" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    INSTANCE_NAME="alpha"
    source "$REPO_ROOT/scripts/common.sh"
    prepare_runtime_env
    printf "deployment=%s\n" "$EOS_DEPLOYMENT_ID"
    printf "matchmaking=%s\n" "$EOS_MATCHMAKING_BASE"
    printf "client_id=%s\n" "${EOS_CLIENT_ID:-unset}"
    printf "client_secret=%s\n" "${EOS_CLIENT_SECRET:-unset}"
    printf "basic_auth=%s\n" "${EOS_BASIC_AUTH:-unset}"
  '

  assert_success
  assert_output --partial "deployment=ad9a8feffb3b4b2ca315546f038c3ae2"
  assert_output --partial "matchmaking=https://api.epicgames.dev/wildcard/matchmaking/v1"
  assert_output --partial "client_id=unset"
  assert_output --partial "client_secret=unset"
  assert_output --partial "basic_auth=unset"
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
