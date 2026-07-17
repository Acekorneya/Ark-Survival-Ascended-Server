#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "POK-manager can be sourced without initializing runtime state" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/pok-source" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    if [ -d "$BASE_DIR/config/POK-manager" ]; then
      echo "config_dir=created"
    else
      echo "config_dir=absent"
    fi
    printf "validate=%s\n" "$(type -t validate_boolean)"
  '

  assert_success
  assert_output --partial "config_dir=absent"
  assert_output --partial "validate=function"
}

@test "POK-manager init runs only when explicitly requested" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/pok-init" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    _init
    if [ -d "$BASE_DIR/config/POK-manager" ]; then
      echo "config_dir=created"
    else
      echo "config_dir=absent"
    fi
    printf "path_config=%s\n" "$PATH_CONFIG_FILE"
  '

  assert_success
  assert_output --partial "config_dir=created"
  assert_output --partial "path_config=$BATS_TEST_TMPDIR/pok-init/config/POK-manager/path_preferences.txt"
}

@test "main handles -api-recovery through normal command dispatch" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/pok-api" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    check_script_permissions() { return 0; }
    check_for_POK_updates() { :; }
    display_logo() { :; }
    check_volume_paths() { :; }
    show_patch_notes_if_updated() { :; }
    check_for_rollback() { :; }
    check_post_migration_permissions() { :; }
    check_puid_pgid_user() { :; }
    check_beta_mode() { :; }
    handle_api_recovery() { echo "api-recovery-dispatched"; return 0; }
    main -api-recovery
  '

  assert_success
  assert_output --partial "api-recovery-dispatched"
}

@test "main normalizes restart timer arguments before dispatching to manage_service" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/pok-restart" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    check_script_permissions() { return 0; }
    check_for_POK_updates() { :; }
    display_logo() { :; }
    check_volume_paths() { :; }
    show_patch_notes_if_updated() { :; }
    check_for_rollback() { :; }
    check_post_migration_permissions() { :; }
    check_puid_pgid_user() { :; }
    check_beta_mode() { :; }
    manage_service() { echo "dispatch:$1:$2:$3"; }
    main -restart 5 demo
  '

  assert_success
  assert_output --partial "dispatch:-restart:demo:5"
}

@test "main parses trailing --force without including it in the timer or target" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/pok-force" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    check_script_permissions() { return 0; }
    check_for_POK_updates() { :; }
    display_logo() { :; }
    check_volume_paths() { :; }
    show_patch_notes_if_updated() { :; }
    check_for_rollback() { :; }
    check_post_migration_permissions() { :; }
    check_puid_pgid_user() { :; }
    check_beta_mode() { :; }
    manage_service() { echo "dispatch:$1:$2:$3:force=$_MAIN_FORCE_MODE"; }
    main -shutdown 2 -all --force
  '

  assert_success
  assert_output --partial "dispatch:-shutdown:-all:2:force=true"
}

@test "main rejects invalid actions before dispatching" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/pok-invalid" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    check_script_permissions() { return 0; }
    check_for_POK_updates() { :; }
    display_logo() { :; }
    check_volume_paths() { :; }
    show_patch_notes_if_updated() { :; }
    check_for_rollback() { :; }
    check_post_migration_permissions() { :; }
    check_puid_pgid_user() { :; }
    check_beta_mode() { :; }
    display_usage() { echo "usage-called"; }
    set +e
    main -not-a-real-action
    status=$?
    set -e
    echo "status=$status"
  '

  assert_success
  assert_output --partial "Invalid action '-not-a-real-action'."
  assert_output --partial "usage-called"
  assert_output --partial "status=1"
}

@test "main routes version requests through the meta action handler" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/pok-version" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    source "$REPO_ROOT/POK-manager.sh"
    check_script_permissions() { return 0; }
    check_for_POK_updates() { :; }
    display_logo() { :; }
    check_volume_paths() { :; }
    show_patch_notes_if_updated() { :; }
    check_for_rollback() { :; }
    check_post_migration_permissions() { :; }
    check_puid_pgid_user() { :; }
    check_beta_mode() { :; }
    display_version() { echo "version-called"; }
    manage_service() { echo "unexpected-dispatch"; }
    main -version
  '

  assert_success
  assert_output --partial "version-called"
  refute_output --partial "unexpected-dispatch"
}
