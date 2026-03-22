#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DOCKER_SMOKE_CMD=()
TEST_ROOT=""
BASE_DIR=""
INSTANCE_NAME="smoke"
CONTAINER_NAME="asa_smoke"
COMPOSE_FILE=""

docker_smoke_cmd() {
  "${DOCKER_SMOKE_CMD[@]}" "$@"
}

docker_smoke_select_command() {
  local docker_info_output=""

  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is required for integration smoke tests."
    return 1
  fi

  if docker info >/dev/null 2>&1; then
    DOCKER_SMOKE_CMD=(docker)
    return 0
  fi

  docker_info_output="$(docker info 2>&1 || true)"
  if [[ "$docker_info_output" == *"permission denied"* ]]; then
    if sudo -n docker info >/dev/null 2>&1; then
      DOCKER_SMOKE_CMD=(sudo docker)
      return 0
    fi
    echo "Docker is installed, but the current user cannot access /var/run/docker.sock."
    echo "Add your user to the docker group or run the smoke test with sudo."
    return 1
  fi

  echo "Docker daemon is not available."
  return 1
}

docker_smoke_setup_paths() {
  TEST_ROOT="$(mktemp -d /tmp/pok-manager-docker-smoke.XXXXXX)"
  BASE_DIR="${TEST_ROOT}/workspace"
  COMPOSE_FILE="${BASE_DIR}/Instance_${INSTANCE_NAME}/docker-compose-${INSTANCE_NAME}.yaml"

  mkdir -p "${BASE_DIR}/Instance_${INSTANCE_NAME}"
  mkdir -p "${BASE_DIR}/config/POK-manager"
}

docker_smoke_write_compose_file() {
cat > "${COMPOSE_FILE}" <<'EOF'
services:
  asaserver:
    image: busybox:1.36
    container_name: "asa_smoke"
    command: ["sh", "-c", "sleep 300"]
    environment:
      - INSTANCE_NAME=smoke
      - API=FALSE
EOF
}

docker_smoke_cleanup() {
  if [ -n "${COMPOSE_FILE:-}" ] && [ -f "${COMPOSE_FILE:-}" ] && [ ${#DOCKER_SMOKE_CMD[@]} -gt 0 ]; then
    docker_smoke_cmd compose -f "${COMPOSE_FILE}" down -v >/dev/null 2>&1 || true
  fi

  if [ -n "${TEST_ROOT:-}" ] && [ -d "${TEST_ROOT:-}" ]; then
    rm -rf "${TEST_ROOT}"
  fi
}

docker_smoke_source_manager() {
  export REPO_ROOT
  export BASE_DIR
  export POK_MANAGER_TEST_MODE=1

  source "${REPO_ROOT}/POK-manager.sh"

  check_volume_paths() { :; }
  _start_instance_validate_start_prerequisites() { return 0; }
  _start_instance_sync_api_logs_volume() { :; }
  _start_instance_handle_api_compatibility() { :; }
  _start_instance_validate_image_permissions() { :; }
  _start_instance_warn_on_local_permission_mismatch() { :; }
  update_docker_compose_image_tag() { :; }
  get_docker_sudo_preference() { echo false; }
  get_docker_compose_cmd() { DOCKER_COMPOSE_CMD="${DOCKER_SMOKE_CMD[*]} compose"; }
  _stop_instance_attempt_quick_save() { :; }
  _start_instance_launch_container() {
    local instance_name="$1"
    local docker_compose_file="$2"

    get_docker_compose_cmd
    echo "Launching smoke container for ${instance_name}"
    ${DOCKER_COMPOSE_CMD} -f "${docker_compose_file}" up -d
  }
}

docker_smoke_run() {
  docker_smoke_select_command || return 1
  docker_smoke_setup_paths
  trap docker_smoke_cleanup EXIT

  docker_smoke_write_compose_file
  docker_smoke_source_manager

  start_instance "${INSTANCE_NAME}"

  if ! docker_smoke_cmd inspect --format '{{.State.Status}}' "${CONTAINER_NAME}" | grep -q '^running$'; then
    echo "Smoke container did not reach running state."
    return 1
  fi

  stop_instance "${INSTANCE_NAME}"

  if docker_smoke_cmd ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
    echo "Smoke container still exists after stop."
    return 1
  fi

  echo "Docker smoke test passed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  docker_smoke_run "$@"
fi
