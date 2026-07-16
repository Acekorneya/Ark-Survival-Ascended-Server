#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "rollback_server.sh can be sourced without downloading or activating files" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rollback_server.sh"
    printf "main=%s stage=%s activate=%s\n" \
      "$(type -t main)" "$(type -t stage_rollback)" "$(type -t activate_rollback)"
  '

  assert_success
  assert_output --partial "main=function stage=function activate=function"
}

@test "rollback manifest validation rejects nonnumeric input" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    source "$REPO_ROOT/scripts/rollback_server.sh"
    validate_manifest "6810;rm"
  '

  assert_failure
  assert_output --partial "Depot manifest must contain only digits"
}
