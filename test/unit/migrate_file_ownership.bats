#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "_migration_collect_dirs_to_change gathers managed directories and creates API_Logs folders" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/migration-dirs" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/ServerFiles" "$BASE_DIR/Instance_alpha" "$BASE_DIR/Instance_beta" "$BASE_DIR/Cluster"
    source "$REPO_ROOT/POK-manager.sh"
    _migration_collect_dirs_to_change
    printf "dirs=%s\n" "${_MIGRATION_DIRS_TO_CHANGE[*]}"
    printf "alpha_logs=%s\n" "$([ -d "$BASE_DIR/Instance_alpha/API_Logs" ] && echo present || echo missing)"
    printf "beta_logs=%s\n" "$([ -d "$BASE_DIR/Instance_beta/API_Logs" ] && echo present || echo missing)"
    printf "config_dir=%s\n" "$([ -d "$BASE_DIR/config/POK-manager" ] && echo present || echo missing)"
  '

  assert_success
  assert_output --partial "$BATS_TEST_TMPDIR/migration-dirs/ServerFiles"
  assert_output --partial "$BATS_TEST_TMPDIR/migration-dirs/Instance_alpha"
  assert_output --partial "$BATS_TEST_TMPDIR/migration-dirs/Instance_beta"
  assert_output --partial "$BATS_TEST_TMPDIR/migration-dirs/Cluster"
  assert_output --partial "$BATS_TEST_TMPDIR/migration-dirs/config/POK-manager"
  assert_output --partial "alpha_logs=present"
  assert_output --partial "beta_logs=present"
  assert_output --partial "config_dir=present"
}

@test "_migration_stop_running_instances uses compose when present and docker stop otherwise" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/migration-stop" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_alpha" "$BASE_DIR/Instance_beta"
    : > "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml"
    source "$REPO_ROOT/POK-manager.sh"
    get_docker_compose_cmd() { DOCKER_COMPOSE_CMD="echo compose"; }
    is_sudo() { return 0; }
    docker() { echo "docker:$*"; }
    _migration_stop_running_instances alpha beta
  '

  assert_success
  assert_output --partial "compose -f $BATS_TEST_TMPDIR/migration-stop/Instance_alpha/docker-compose-alpha.yaml down"
  assert_output --partial "docker:stop -t 30 asa_beta"
}

@test "_migration_update_api_logs_volume_for_instance_dir adds the API logs bind mount once" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/migration-compose" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_demo/Saved"
    cat > "$BASE_DIR/Instance_demo/docker-compose-demo.yaml" <<EOF
services:
  asaserver:
    volumes:
      - "$BASE_DIR/Instance_demo/Saved:/home/pok/arkserver/ShooterGame/Saved"
EOF
    source "$REPO_ROOT/POK-manager.sh"
    chown() { :; }
    chmod() { :; }
    _migration_update_api_logs_volume_for_instance_dir "$BASE_DIR/Instance_demo"
    printf "logs_dir=%s\n" "$([ -d "$BASE_DIR/Instance_demo/API_Logs" ] && echo present || echo missing)"
    cat "$BASE_DIR/Instance_demo/docker-compose-demo.yaml"
  '

  assert_success
  assert_output --partial "logs_dir=present"
  assert_output --partial "$BATS_TEST_TMPDIR/migration-compose/Instance_demo/API_Logs:/home/pok/arkserver/ShooterGame/Binaries/Win64/logs"
}
