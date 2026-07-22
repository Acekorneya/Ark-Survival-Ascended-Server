#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "update_notice_monitor.sh can be sourced without starting its polling loop" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/update_notice_monitor.sh"
    printf "main=%s\n" "$(type -t main)"
    printf "check=%s\n" "$(type -t check_for_blocked_update)"
  '

  assert_success
  assert_output --partial "main=function"
  assert_output --partial "check=function"
}

@test "blocked update notifier records state and sends only one notice per build" {
  run env REPO_ROOT="$PROJECT_ROOT" BATS_TMP="$BATS_TEST_TMPDIR/blocked-notice" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/update_notice_monitor.sh"
    ASA_DIR="$BATS_TMP/server"
    INSTANCE_NAME=alpha
    SHARED_POLICY_BLOCKING_INSTANCES="api:API_TRUE"
    mkdir -p "$ASA_DIR"
    get_build_id_from_acf() { echo 100; }
    get_current_build_id() { echo 101; }
    check_for_blocked_update
    check_for_blocked_update
    source "$ASA_DIR/.pok-manager/pending_manual_update.env"
    echo "installed=$INSTALLED_BUILD_ID available=$AVAILABLE_BUILD_ID"
  '

  assert_success
  assert_output --partial "installed=100 available=101"
  assert_output --partial "[WARNING] ARK build 101 is available, but automatic shared-file updates are disabled."
  run grep -c "\[WARNING\] ARK build 101 is available" <<< "$output"
  assert_output "1"
}
