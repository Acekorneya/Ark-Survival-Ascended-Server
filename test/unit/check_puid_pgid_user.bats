#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "_permission_print_file_owner_mismatch_guidance reuses the matching user when one exists" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/perm-match" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    getent() { echo "arkuser:x:7777:7777::/home/arkuser:/bin/bash"; }
    _permission_print_file_owner_mismatch_guidance 7777 7777 1000 1000 "-start demo"
  '

  assert_success
  assert_output --partial "⚠️ PERMISSION MISMATCH: Your files are owned by 7777:7777 but you're running as 1000:1000"
  assert_output --partial "Switch to user 'arkuser' with: su - arkuser"
  assert_output --partial "sudo ./POK-manager.sh -start demo"
}

@test "_permission_print_file_owner_mismatch_guidance shows the UID 7777 creation hint when no matching user exists" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/perm-create" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    getent() { return 0; }
    _permission_print_file_owner_mismatch_guidance 7777 7777 1000 1000 "-status demo"
  '

  assert_success
  assert_output --partial "(No user with UID 7777 was found on this system)"
  assert_output --partial "sudo groupadd -g 7777 pokuser"
  assert_output --partial "sudo ./POK-manager.sh -migrate"
}

@test "_permission_print_current_user_mismatch_guidance suggests creating the configured UID when no user exists" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/perm-current" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    getent() { return 0; }
    _permission_print_current_user_mismatch_guidance 7777 7777 demo 1000 1000 "-restart 5 demo"
  '

  assert_success
  assert_output --partial "You are not running the script as the user with the correct PUID (7777) and PGID (7777)."
  assert_output --partial "sudo useradd -u 7777 -g 7777 -m -s /bin/bash pokuser"
  assert_output --partial "NOTE: You can also create this user automatically by running: sudo ./POK-manager.sh -migrate"
}

@test "_permission_print_post_migration_guidance points to the migrated UID 7777 account" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/perm-post" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    getent() { echo "pokuser:x:7777:7777::/home/pokuser:/bin/bash"; }
    _permission_print_post_migration_guidance demo 1000 1000 "-stop -all"
  '

  assert_success
  assert_output --partial "⚠️ POST-MIGRATION PERMISSION ISSUE DETECTED ⚠️"
  assert_output --partial "sudo su - pokuser"
  assert_output --partial "cd $(pwd) && ./POK-manager.sh -stop -all"
}
