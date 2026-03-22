#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTANCE_NAME=""
TARGET_BRANCH_MODE="current"
ORIGINAL_BRANCH_MODE=""
STARTUP_TIMEOUT=300
PROCESS_TIMEOUT=300
HEALTH_TIMEOUT=300
SKIP_FAST=false
SKIP_SMOKE=false
LEAVE_RUNNING=false
USE_SUDO=false
STARTED_BY_VALIDATION=false
FULL_VALIDATION_DOCKER_CMD=()
FULL_VALIDATION_MANAGER_CMD=()

full_validation_usage() {
  cat <<'EOF'
Usage: bash test/run_full_local_validation.sh <instance_name> [options]

Options:
  --branch <current|beta|stable>   Temporarily switch manager branch mode for the test
  --startup-timeout <seconds>      Max wait for the container to reach running state (default: 300)
  --process-timeout <seconds>      Max wait for the ASA process to appear (default: 300)
  --health-timeout <seconds>       Max wait for Docker health and /healthz readiness (default: 300)
  --skip-fast                      Skip bash syntax checks and BATS unit tests
  --skip-smoke                     Skip the lightweight Docker smoke test
  --leave-running                  Leave the instance running after validation succeeds
  --sudo                           Run manager and Docker validation commands with sudo
  -h, --help                       Show this help text

Notes:
  - Use a dedicated test instance, not a production instance.
  - The script performs a clean stop/start cycle for the target instance.
EOF
}

full_validation_detect_branch_mode() {
  if [ -f "${REPO_ROOT}/config/POK-manager/beta_mode" ]; then
    echo "beta"
  else
    echo "stable"
  fi
}

full_validation_parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
    --branch)
      TARGET_BRANCH_MODE="${2:-}"
      shift 2
      ;;
    --startup-timeout)
      STARTUP_TIMEOUT="${2:-}"
      shift 2
      ;;
    --process-timeout)
      PROCESS_TIMEOUT="${2:-}"
      shift 2
      ;;
    --health-timeout)
      HEALTH_TIMEOUT="${2:-}"
      shift 2
      ;;
    --skip-fast)
      SKIP_FAST=true
      shift
      ;;
    --skip-smoke)
      SKIP_SMOKE=true
      shift
      ;;
    --leave-running)
      LEAVE_RUNNING=true
      shift
      ;;
    --sudo)
      USE_SUDO=true
      shift
      ;;
    -h|--help)
      full_validation_usage
      return 1
      ;;
    *)
      if [ -z "$INSTANCE_NAME" ]; then
        INSTANCE_NAME="$1"
        shift
      else
        echo "Unexpected argument: $1"
        return 1
      fi
      ;;
    esac
  done

  if [ -z "$INSTANCE_NAME" ]; then
    echo "A target instance name is required."
    return 1
  fi

  case "$TARGET_BRANCH_MODE" in
  current|beta|stable) ;;
  *)
    echo "Invalid branch mode: $TARGET_BRANCH_MODE"
    return 1
    ;;
  esac

  if ! [[ "$STARTUP_TIMEOUT" =~ ^[0-9]+$ ]] || ! [[ "$PROCESS_TIMEOUT" =~ ^[0-9]+$ ]] || ! [[ "$HEALTH_TIMEOUT" =~ ^[0-9]+$ ]]; then
    echo "Timeout values must be whole numbers in seconds."
    return 1
  fi
}

full_validation_init_manager_command() {
  FULL_VALIDATION_MANAGER_CMD=(./POK-manager.sh)

  if [ "$USE_SUDO" = "true" ]; then
    FULL_VALIDATION_MANAGER_CMD=(sudo ./POK-manager.sh)
  fi
}

full_validation_manager() {
  (cd "$REPO_ROOT" && "${FULL_VALIDATION_MANAGER_CMD[@]}" "$@")
}

full_validation_docker() {
  "${FULL_VALIDATION_DOCKER_CMD[@]}" "$@"
}

full_validation_select_docker_command() {
  local docker_info_output=""

  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is required for full local validation."
    return 1
  fi

  if [ "$USE_SUDO" = "true" ]; then
    FULL_VALIDATION_DOCKER_CMD=(sudo docker)
    return 0
  fi

  if docker info >/dev/null 2>&1; then
    FULL_VALIDATION_DOCKER_CMD=(docker)
    return 0
  fi

  docker_info_output="$(docker info 2>&1 || true)"
  if [[ "$docker_info_output" == *"permission denied"* ]]; then
    if sudo -n docker info >/dev/null 2>&1; then
      FULL_VALIDATION_DOCKER_CMD=(sudo docker)
      return 0
    fi
    echo "Docker is installed, but the current user cannot access /var/run/docker.sock."
    echo "Add your user to the docker group or rerun the full local validation with --sudo."
    return 1
  fi

  echo "Docker daemon is not available."
  return 1
}

full_validation_require_instance() {
  local compose_file="${REPO_ROOT}/Instance_${INSTANCE_NAME}/docker-compose-${INSTANCE_NAME}.yaml"

  if [ ! -f "$compose_file" ]; then
    echo "Missing compose file for instance '${INSTANCE_NAME}': ${compose_file}"
    echo "Create a dedicated test instance before running the full local validation."
    return 1
  fi
}

full_validation_switch_branch_mode() {
  ORIGINAL_BRANCH_MODE="$(full_validation_detect_branch_mode)"

  if [ "$TARGET_BRANCH_MODE" = "current" ] || [ "$TARGET_BRANCH_MODE" = "$ORIGINAL_BRANCH_MODE" ]; then
    return 0
  fi

  echo "Switching manager branch mode from ${ORIGINAL_BRANCH_MODE} to ${TARGET_BRANCH_MODE}..."
  if [ "$TARGET_BRANCH_MODE" = "beta" ]; then
    full_validation_manager -beta
  else
    full_validation_manager -stable
  fi
}

full_validation_restore_branch_mode() {
  if [ -z "$ORIGINAL_BRANCH_MODE" ] || [ "$TARGET_BRANCH_MODE" = "current" ] || [ "$TARGET_BRANCH_MODE" = "$ORIGINAL_BRANCH_MODE" ]; then
    return 0
  fi

  echo "Restoring manager branch mode to ${ORIGINAL_BRANCH_MODE}..."
  if [ "$ORIGINAL_BRANCH_MODE" = "beta" ]; then
    full_validation_manager -beta || true
  else
    full_validation_manager -stable || true
  fi
}

full_validation_container_running() {
  full_validation_docker inspect --format '{{.State.Status}}' "asa_${INSTANCE_NAME}" 2>/dev/null | grep -q '^running$'
}

full_validation_wait_for_container() {
  local elapsed=0

  while [ "$elapsed" -lt "$STARTUP_TIMEOUT" ]; do
    if full_validation_container_running; then
      echo "Container asa_${INSTANCE_NAME} is running."
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  echo "Timed out waiting for asa_${INSTANCE_NAME} to reach running state."
  return 1
}

full_validation_wait_for_asa_process() {
  local elapsed=0
  local process_output=""

  while [ "$elapsed" -lt "$PROCESS_TIMEOUT" ]; do
    if process_output="$(full_validation_docker exec "asa_${INSTANCE_NAME}" /bin/bash -lc "pgrep -fa 'AsaApiLoader.exe|ArkAscendedServer.exe'" 2>/dev/null)" && [ -n "$process_output" ]; then
      echo "Detected ASA process:"
      echo "$process_output"
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done

  echo "Timed out waiting for the ASA process to appear inside asa_${INSTANCE_NAME}."
  return 1
}

full_validation_container_health_status() {
  full_validation_docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "asa_${INSTANCE_NAME}" 2>/dev/null || true
}

full_validation_wait_for_container_health() {
  local elapsed=0
  local health_status=""

  while [ "$elapsed" -lt "$HEALTH_TIMEOUT" ]; do
    health_status="$(full_validation_container_health_status)"
    if [ "$health_status" = "healthy" ]; then
      echo "Container asa_${INSTANCE_NAME} reported healthy."
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done

  echo "Timed out waiting for asa_${INSTANCE_NAME} to report healthy."
  return 1
}

full_validation_wait_for_health_endpoint() {
  local elapsed=0
  local probe_output=""

  while [ "$elapsed" -lt "$HEALTH_TIMEOUT" ]; do
    if probe_output="$(full_validation_docker exec "asa_${INSTANCE_NAME}" /bin/bash -lc "curl -fsS http://127.0.0.1:8080/healthz" 2>/dev/null)" && [ -n "$probe_output" ]; then
      echo "Health endpoint returned: ${probe_output}"
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done

  echo "Timed out waiting for /healthz to report healthy inside asa_${INSTANCE_NAME}."
  return 1
}

full_validation_show_failure_context() {
  echo ""
  echo "===== Failure Context ====="
  full_validation_docker ps -a --filter "name=asa_${INSTANCE_NAME}" || true
  echo ""
  echo "===== Container Logs ====="
  full_validation_docker logs --tail 200 "asa_${INSTANCE_NAME}" || true
  echo ""
  echo "===== Container Health ====="
  full_validation_docker inspect --format '{{json .State.Health}}' "asa_${INSTANCE_NAME}" 2>/dev/null || true
  echo ""
  echo "===== ShooterGame.log ====="
  full_validation_docker exec "asa_${INSTANCE_NAME}" /bin/bash -lc "tail -n 200 /home/pok/arkserver/ShooterGame/Saved/Logs/ShooterGame.log 2>/dev/null || true" || true
  echo ""
  echo "===== AsaApi Logs ====="
  full_validation_docker exec "asa_${INSTANCE_NAME}" /bin/bash -lc "tail -n 200 /home/pok/arkserver/ShooterGame/Binaries/Win64/logs/*.log 2>/dev/null || true" || true
  echo ""
  echo "===== /healthz ====="
  full_validation_docker exec "asa_${INSTANCE_NAME}" /bin/bash -lc "curl -i -s http://127.0.0.1:8080/healthz 2>/dev/null || true" || true
}

full_validation_cleanup() {
  local exit_code="$1"

  if [ "$STARTED_BY_VALIDATION" = "true" ] && [ "$LEAVE_RUNNING" = "false" ]; then
    echo "Stopping validation instance ${INSTANCE_NAME}..."
    full_validation_manager -stop "$INSTANCE_NAME" || true
  fi

  full_validation_restore_branch_mode

  if [ "$exit_code" -ne 0 ]; then
    exit "$exit_code"
  fi
}

full_validation_run() {
  full_validation_parse_args "$@" || {
    full_validation_usage
    return 1
  }
  full_validation_init_manager_command

  trap 'full_validation_cleanup $?' EXIT

  cd "$REPO_ROOT"

  if [ "$SKIP_FAST" = "false" ]; then
    bash test/run_ci_checks.sh
  fi

  if [ "$SKIP_SMOKE" = "false" ]; then
    bash test/run_integration_checks.sh
  fi

  full_validation_select_docker_command
  full_validation_require_instance
  full_validation_switch_branch_mode

  if full_validation_container_running; then
    echo "Stopping existing instance ${INSTANCE_NAME} for a clean validation run..."
    full_validation_manager -stop "$INSTANCE_NAME" || true
    sleep 10
  fi

  echo "Starting full local validation for instance ${INSTANCE_NAME}..."
  full_validation_manager -start "$INSTANCE_NAME"
  STARTED_BY_VALIDATION=true

  full_validation_wait_for_container || {
    full_validation_show_failure_context
    return 1
  }

  full_validation_wait_for_asa_process || {
    full_validation_show_failure_context
    return 1
  }

  full_validation_wait_for_health_endpoint || {
    full_validation_show_failure_context
    return 1
  }

  full_validation_wait_for_container_health || {
    full_validation_show_failure_context
    return 1
  }

  echo "Running status check..."
  full_validation_manager -status "$INSTANCE_NAME" || true

  echo "Full local validation passed for ${INSTANCE_NAME}."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  full_validation_run "$@"
fi
