#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "_manage_service_handle_delete removes instance files and preserves backups" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/delete-single" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo/Saved" "$BASE_DIR/config/POK-manager" "$BASE_DIR/backups/demo"
    printf "compose" > "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
    printf "compose" > "$BASE_DIR/docker-compose-demo.yaml"
    printf "backup_cfg" > "$BASE_DIR/config/POK-manager/backup_demo.conf"
    printf "archive" > "$BASE_DIR/backups/demo/demo_backup.tar.gz"

    source "$REPO_ROOT/POK-manager.sh"
    is_sudo() { return 0; }
    _manage_service_delete_confirm_single() { echo "confirmed:$1"; return 0; }
    _manage_service_delete_instance_is_running() { return 1; }

    _manage_service_handle_delete demo

    [ -d "$BASE_DIR/Instance_demo" ] && echo "instance_dir=present" || echo "instance_dir=removed"
    [ -f "$BASE_DIR/docker-compose-demo.yaml" ] && echo "top_compose=present" || echo "top_compose=removed"
    [ -f "$BASE_DIR/config/POK-manager/backup_demo.conf" ] && echo "backup_config=present" || echo "backup_config=removed"
    [ -d "$BASE_DIR/backups/demo" ] && echo "backup_dir=preserved" || echo "backup_dir=missing"
  '

  assert_success
  assert_output --partial "confirmed:demo"
  assert_output --partial "Deleted instance 'demo'."
  assert_output --partial "instance_dir=removed"
  assert_output --partial "top_compose=removed"
  assert_output --partial "backup_config=removed"
  assert_output --partial "backup_dir=preserved"
}

@test "_manage_service_handle_delete stops a running instance before deletion" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/delete-running" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo"
    printf "compose" > "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"

    source "$REPO_ROOT/POK-manager.sh"
    is_sudo() { return 0; }
    _manage_service_delete_confirm_single() { return 0; }
    _manage_service_delete_instance_is_running() { return 0; }
    stop_instance() { echo "stopped:$1"; }

    _manage_service_handle_delete demo
  '

  assert_success
  assert_output --partial "currently running and will be stopped before deletion"
  assert_output --partial "stopped:demo"
  assert_output --partial "Deleted instance 'demo'."
}

@test "_manage_service_handle_delete removes all instances after confirmation" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/delete-all" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_alpha" "$BASE_DIR/Instance_beta"
    printf "compose" > "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml"
    printf "compose" > "$BASE_DIR/Instance_beta/docker-compose-beta.yaml"

    source "$REPO_ROOT/POK-manager.sh"
    is_sudo() { return 0; }
    _manage_service_delete_confirm_all() { echo "confirmed:all"; return 0; }
    _manage_service_delete_confirm_single() { return 0; }
    _manage_service_delete_instance_is_running() { return 1; }

    _manage_service_handle_delete -all

    [ -d "$BASE_DIR/Instance_alpha" ] && echo "alpha=present" || echo "alpha=removed"
    [ -d "$BASE_DIR/Instance_beta" ] && echo "beta=present" || echo "beta=removed"
  '

  assert_success
  assert_output --partial "confirmed:all"
  assert_output --partial "Deleted instance 'alpha'."
  assert_output --partial "Deleted instance 'beta'."
  assert_output --partial "alpha=removed"
  assert_output --partial "beta=removed"
}
