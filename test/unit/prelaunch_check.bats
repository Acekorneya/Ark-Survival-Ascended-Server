#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "prelaunch_check.sh can be sourced without executing the checks" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/prelaunch_check.sh"
    printf "main=%s\n" "$(type -t main)"
  '

  assert_success
  assert_output --partial "main=function"
}

@test "check_create_directory creates a missing directory and returns 1" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/prelaunch_check.sh"
    target_dir="$BATS_TEST_TMPDIR/new-dir"
    set +e
    check_create_directory "$target_dir"
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "exists=%s\n" "$( [ -d "$target_dir" ] && echo yes || echo no )"
  '

  assert_success
  assert_output --partial "status=1"
  assert_output --partial "exists=yes"
}

@test "check_critical_file reports missing optional files without failing hard" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/prelaunch_check.sh"
    missing_file="$BATS_TEST_TMPDIR/optional.bin"
    set +e
    check_critical_file "$missing_file" true
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "NOTICE: Optional file not found"
  assert_output --partial "status=1"
}

@test "check_server_files returns pending download when the server executable is missing" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/prelaunch_check.sh"
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    API=FALSE
    mkdir -p "$ASA_DIR/ShooterGame/Binaries/Win64"
    set +e
    check_server_files
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "Server files check: PENDING DOWNLOAD"
  assert_output --partial "status=1"
}
