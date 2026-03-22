#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "docker_smoke.sh can be sourced without running the smoke flow" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/test/integration/docker_smoke.sh"
    printf "selector=%s\n" "$(type -t docker_smoke_select_command)"
    printf "test_root=%s\n" "${TEST_ROOT:-unset}"
  '

  assert_success
  assert_output --partial "selector=function"
  assert_output --partial "test_root=unset"
}

@test "docker_smoke_select_command uses docker directly when the daemon is reachable" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/test/integration/docker_smoke.sh"
    command() {
      if [ "$1" = "-v" ] && [ "$2" = "docker" ]; then
        return 0
      fi
      builtin command "$@"
    }
    docker() { return 0; }
    docker_smoke_select_command
    printf "cmd=%s\n" "${DOCKER_SMOKE_CMD[*]}"
  '

  assert_success
  assert_output --partial "cmd=docker"
}

@test "docker_smoke_select_command falls back to sudo docker for socket permission issues" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/test/integration/docker_smoke.sh"
    command() {
      if [ "$1" = "-v" ] && [ "$2" = "docker" ]; then
        return 0
      fi
      builtin command "$@"
    }
    docker() {
      if [ "${1:-}" = "info" ]; then
        echo "permission denied while trying to connect to the docker API at unix:///var/run/docker.sock" >&2
        return 1
      fi
      return 0
    }
    sudo() {
      if [ "${1:-}" = "-n" ] && [ "${2:-}" = "docker" ] && [ "${3:-}" = "info" ]; then
        return 0
      fi
      return 1
    }
    docker_smoke_select_command
    printf "cmd=%s\n" "${DOCKER_SMOKE_CMD[*]}"
  '

  assert_success
  assert_output --partial "cmd=sudo docker"
}

@test "docker_smoke_select_command prints a clear message when docker socket access is denied" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/test/integration/docker_smoke.sh"
    command() {
      if [ "$1" = "-v" ] && [ "$2" = "docker" ]; then
        return 0
      fi
      builtin command "$@"
    }
    docker() {
      if [ "${1:-}" = "info" ]; then
        echo "permission denied while trying to connect to the docker API at unix:///var/run/docker.sock" >&2
        return 1
      fi
      return 0
    }
    sudo() { return 1; }
    set +e
    docker_smoke_select_command
    status=$?
    set -e
    echo "status=$status"
  '

  assert_success
  assert_output --partial "Docker is installed, but the current user cannot access /var/run/docker.sock."
  assert_output --partial "Add your user to the docker group or run the smoke test with sudo."
  assert_output --partial "status=1"
}
