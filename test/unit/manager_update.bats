#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "manager update uses Docker directly and stages on shared storage when sudo is disabled" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/no-sudo" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/ServerFiles/arkserver" "$BASE_DIR/config/POK-manager"
    source "$REPO_ROOT/POK-manager.sh"

    normalize_update_coordination_assignments() { :; }
    _rcon_print_running_instances() { :; }
    shared_update_policy_allows_automatic_updates() { return 0; }
    check_for_POK_updates() { :; }
    get_docker_image_tag() { echo 2_1_beta; }
    get_docker_sudo_preference() { echo false; }
    get_build_id_from_acf() { echo 100; }
    get_current_build_id() { echo 101; }
    groups() { echo users; }
    sleep() { :; }
    sudo() {
      printf "%s\n" "$*" >> "$BASE_DIR/sudo.log"
      return 99
    }
    docker() {
      printf "%s\n" "$*" >> "$BASE_DIR/docker.log"
      case "$1" in
        ps) echo fake-container ;;
        run) echo new-container ;;
      esac
      return 0
    }

    update_server_files_and_docker
    printf "sudo_calls=%s\n" "$(wc -l < "$BASE_DIR/sudo.log" 2>/dev/null || echo 0)"
    grep "TEMP_DOWNLOAD_ROOT=/home/pok/arkserver/.pok-manager/update/staging" "$BASE_DIR/docker.log"
  '

  assert_success
  assert_output --partial "Update process completed successfully"
  assert_output --partial "sudo_calls=0"
  assert_output --partial "TEMP_DOWNLOAD_ROOT=/home/pok/arkserver/.pok-manager/update/staging"
}

@test "manager update uses non-interactive sudo only when the saved preference enables it" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/with-sudo" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/ServerFiles/arkserver" "$BASE_DIR/config/POK-manager"
    source "$REPO_ROOT/POK-manager.sh"

    normalize_update_coordination_assignments() { :; }
    _rcon_print_running_instances() { :; }
    shared_update_policy_allows_automatic_updates() { return 0; }
    check_for_POK_updates() { :; }
    get_docker_image_tag() { echo 2_1_beta; }
    get_docker_sudo_preference() { echo true; }
    get_build_id_from_acf() { echo 100; }
    get_current_build_id() { echo 101; }
    sleep() { :; }
    docker() {
      printf "%s\n" "$*" >> "$BASE_DIR/docker.log"
      case "$1" in
        ps) echo fake-container ;;
        run) echo new-container ;;
      esac
      return 0
    }
    sudo() {
      printf "%s\n" "$*" >> "$BASE_DIR/sudo.log"
      if [ "$1" = "-n" ]; then shift; fi
      "$@"
    }

    update_server_files_and_docker
    grep -- "-n docker pull acekorneya/asa_server:2_1_beta" "$BASE_DIR/sudo.log"
    grep -- "-n docker run" "$BASE_DIR/sudo.log"
    grep -- "-n docker exec pok_update_temp_container /home/pok/scripts/install_server.sh" "$BASE_DIR/sudo.log"
  '

  assert_success
  assert_output --partial "Update process completed successfully"
  assert_output --partial "-n docker pull acekorneya/asa_server:2_1_beta"
}

@test "manager update returns failure after SteamCMD retries and still removes its container" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/update-failure" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/ServerFiles/arkserver" "$BASE_DIR/config/POK-manager"
    source "$REPO_ROOT/POK-manager.sh"

    normalize_update_coordination_assignments() { :; }
    _rcon_print_running_instances() { :; }
    shared_update_policy_allows_automatic_updates() { return 0; }
    check_for_POK_updates() { :; }
    get_docker_image_tag() { echo 2_1_beta; }
    get_docker_sudo_preference() { echo false; }
    get_build_id_from_acf() { echo 100; }
    get_current_build_id() { echo 101; }
    sleep() { :; }
    docker() {
      printf "%s\n" "$*" >> "$BASE_DIR/docker.log"
      case "$1" in
        ps) echo fake-container ;;
        run) echo new-container ;;
        exec)
          if [[ "$*" == *"/home/pok/scripts/install_server.sh"* ]]; then
            return 1
          fi
          ;;
      esac
      return 0
    }

    set +e
    update_server_files_and_docker
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "attempts=%s\n" "$(grep -c "/home/pok/scripts/install_server.sh" "$BASE_DIR/docker.log")"
    grep "rm -f pok_update_temp_container" "$BASE_DIR/docker.log"
  '

  assert_success
  assert_output --partial "Update process failed; review the errors above"
  assert_output --partial "status=1"
  assert_output --partial "attempts=3"
  assert_output --partial "rm -f pok_update_temp_container"
}

@test "manager update CLI dispatch preserves the updater failure status" {
  run env REPO_ROOT="$PROJECT_ROOT" POK_MANAGER_TEST_MODE=1 bash -lc '
    source "$REPO_ROOT/POK-manager.sh"
    get_docker_compose_cmd() { :; }
    _manage_service_requires_docker_permissions() { return 1; }
    _manage_service_handle_all_instance_shortcut() { return 1; }
    update_server_files_and_docker() { return 7; }
    manage_service -update ""
  '

  assert_failure 7
}

@test "manager update rejects insufficient shared staging space before creating a container" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/low-space" POK_MANAGER_TEST_MODE=1 REQUIRED_UPDATE_FREE_MB=25360 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/ServerFiles/arkserver" "$BASE_DIR/config/POK-manager"
    source "$REPO_ROOT/POK-manager.sh"

    normalize_update_coordination_assignments() { :; }
    _rcon_print_running_instances() { :; }
    shared_update_policy_allows_automatic_updates() { return 0; }
    check_for_POK_updates() { :; }
    get_docker_image_tag() { echo 2_1_beta; }
    get_docker_sudo_preference() { echo false; }
    df() {
      printf "Filesystem 1048576-blocks Used Available Capacity Mounted on\n"
      printf "testfs 30000 29000 1000 97%% /test\n"
    }
    docker() {
      printf "%s\n" "$*" >> "$BASE_DIR/docker.log"
      return 0
    }

    set +e
    update_server_files_and_docker
    status=$?
    set -e
    printf "status=%s\n" "$status"
    if grep -q "^run " "$BASE_DIR/docker.log"; then
      echo "unexpected_container_run"
      exit 1
    fi
  '

  assert_success
  assert_output --partial "Not enough free disk space"
  assert_output --partial "status=1"
  refute_output --partial "unexpected_container_run"
}

@test "build ID lookup follows the saved no-sudo Docker preference" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/build-id" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/config/POK-manager"
    source "$REPO_ROOT/POK-manager.sh"
    get_docker_sudo_preference() { echo false; }
    sudo() {
      echo "unexpected sudo" >&2
      return 99
    }
    docker() {
      printf "%s\n" "$*" >> "$BASE_DIR/docker.log"
      cat <<EOF
"branches"
{
  "public"
  {
    "buildid" "24232019"
  }
}
EOF
    }

    printf "build=%s\n" "$(get_current_build_id existing-update-container)"
    cat "$BASE_DIR/docker.log"
  '

  assert_success
  assert_output --partial "build=24232019"
  assert_output --partial "exec existing-update-container"
  refute_output --partial "unexpected sudo"
}

@test "common runtime defaults staged downloads to shared storage and preserves overrides" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/common.sh"
    INSTANCE_NAME=test
    unset TEMP_DOWNLOAD_ROOT
    common_init
    printf "default=%s\n" "$TEMP_DOWNLOAD_ROOT"
    TEMP_DOWNLOAD_ROOT=/mnt/large-update-disk
    common_init
    printf "override=%s\n" "$TEMP_DOWNLOAD_ROOT"
  '

  assert_success
  assert_output --partial "default=/home/pok/arkserver/.pok-manager/update/staging"
  assert_output --partial "override=/mnt/large-update-disk"
}
