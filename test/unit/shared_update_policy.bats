#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "manager aggregate policy includes stopped API instances and writes it to every compose file" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/shared-policy" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_plain" "$BASE_DIR/Instance_api"
    cat > "$BASE_DIR/Instance_plain/docker-compose-plain.yaml" <<EOF
services:
  asaserver:
    environment:
      - INSTANCE_NAME=plain
      - TZ=UTC
      - API=FALSE
      - UPDATE_SERVER=TRUE
EOF
    cat > "$BASE_DIR/Instance_api/docker-compose-api.yaml" <<EOF
services:
  asaserver:
    environment:
      - INSTANCE_NAME=api
      - TZ=UTC
      - API=TRUE
      - UPDATE_SERVER=TRUE
EOF
    source "$REPO_ROOT/POK-manager.sh"
    normalize_update_coordination_assignments
    echo "plain_policy=$(grep POK_SHARED_AUTOMATIC_UPDATES "$BASE_DIR/Instance_plain/docker-compose-plain.yaml" | sed "s/.*=//")"
    echo "api_policy=$(grep POK_SHARED_AUTOMATIC_UPDATES "$BASE_DIR/Instance_api/docker-compose-api.yaml" | sed "s/.*=//")"
    echo "blockers=$(grep POK_SHARED_BLOCKING_INSTANCES "$BASE_DIR/Instance_plain/docker-compose-plain.yaml" | sed "s/.*=//")"
  '

  assert_success
  assert_output --partial "plain_policy=FALSE"
  assert_output --partial "api_policy=FALSE"
  assert_output --partial "blockers=api:API_TRUE"
}

@test "direct manager update refuses to mutate shared files while an instance is running" {
  run env REPO_ROOT="$PROJECT_ROOT" POK_MANAGER_TEST_MODE=1 bash -lc '
    source "$REPO_ROOT/POK-manager.sh"
    normalize_update_coordination_assignments() { :; }
    _rcon_print_running_instances() { echo alpha; }
    print_shared_update_policy_warning() { :; }
    set +e
    update_server_files_and_docker
    status=$?
    set -e
    echo "status=$status"
  '

  assert_success
  assert_output --partial "Shared-file update refused while managed instances are running: alpha"
  assert_output --partial "-restart <minutes> -all"
  assert_output --partial "status=1"
  refute_output --partial "CHECKING FOR UPDATES"
}

@test "managed start snapshots already-running peers for old-image compatibility" {
  run env REPO_ROOT="$PROJECT_ROOT" BASE_DIR="$BATS_TEST_TMPDIR/running-snapshot" POK_MANAGER_TEST_MODE=1 bash -lc '
    set -e
    mkdir -p "$BASE_DIR/Instance_alpha"
    cat > "$BASE_DIR/Instance_alpha/docker-compose-alpha.yaml" <<EOF
services:
  asaserver:
    environment:
      - INSTANCE_NAME=alpha
      - TZ=UTC
      - API=FALSE
      - UPDATE_SERVER=TRUE
      - RESTART_NOTICE_MINUTES=17
EOF
    source "$REPO_ROOT/POK-manager.sh"
    list_running_instances() { echo alpha; }
    get_docker_sudo_preference() { echo false; }
    publish_running_update_participants
    source "$BASE_DIR/ServerFiles/arkserver/update_coordination/instances/alpha.env"
    echo "instance=$INSTANCE_NAME notice=$RESTART_NOTICE_MINUTES"
  '

  assert_success
  assert_output --partial "instance=alpha notice=17"
}
