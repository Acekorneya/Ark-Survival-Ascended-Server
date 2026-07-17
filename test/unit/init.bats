#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "init.sh no longer references the removed VC runtime test hook" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    if grep -q "test_vcredist.sh" "$REPO_ROOT/scripts/init.sh"; then
      echo "found=legacy-hook"
      exit 1
    fi
    echo "found=none"
  '

  assert_success
  assert_output --partial "found=none"
}

@test "init.sh cleanup_disk_space uses shared cleanup helpers" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    grep -q "rotate_log_files 5" "$REPO_ROOT/scripts/init.sh"
    grep -q "clean_temp_files" "$REPO_ROOT/scripts/init.sh"
    echo "helpers=shared"
  '

  assert_success
  assert_output --partial "helpers=shared"
}

@test "init.sh installs an interruptible verified shutdown trap" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    grep -q "trap container_signal_shutdown SIGTERM SIGINT" "$REPO_ROOT/scripts/init.sh"
    grep -q "if safe_container_stop" "$REPO_ROOT/scripts/init.sh"
    if grep -qE "^[[:space:]]*tail[[:space:]]+-f[[:space:]]+/dev/null" "$REPO_ROOT/scripts/init.sh"; then
      echo "interruptible=no"
      exit 1
    fi
    echo "interruptible=yes"
  '

  assert_success
  assert_output --partial "interruptible=yes"
}

@test "init.sh mirrors the complete server console log to container stdout" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    grep -Fq "tail -n +1 -F /home/pok/logs/server_console.log" "$REPO_ROOT/scripts/init.sh"
    grep -Fq "CONSOLE_TAIL_PID=\$!" "$REPO_ROOT/scripts/init.sh"
    echo "console-tail=complete"
  '

  assert_success
  assert_output --partial "console-tail=complete"
}
