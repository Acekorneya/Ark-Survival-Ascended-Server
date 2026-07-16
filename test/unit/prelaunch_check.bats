#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "prelaunch_check.sh can be sourced without executing the checks" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/prelaunch_check.sh"
    printf "main=%s\n" "$(type -t main)"
  '

  assert_success
  assert_output --partial "main=function"
}

@test "check_create_directory creates a missing directory and returns 1" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/prelaunch_check.sh"
    target_dir="$BATS_TEST_TMPDIR/new-dir"
    set +e
    check_create_directory "$target_dir"
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "exists=%s\n" "$( [ -d "$target_dir" ] && echo yes || echo no )"
  '

  assert_success
  assert_output --partial "status=1"
  assert_output --partial "exists=yes"
}

@test "repair_proton_prefix_permissions changes only entries missing minimum access" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/prelaunch_check.sh"

    prefix="$BATS_TEST_TMPDIR/prefix with spaces"
    external_target="$BATS_TEST_TMPDIR/external target"
    chmod_log="$BATS_TEST_TMPDIR/chmod.log"
    fakebin="$BATS_TEST_TMPDIR/fakebin"

    mkdir -p "$prefix/restricted directory" "$fakebin"
    printf "restricted\n" > "$prefix/restricted file"
    printf "compliant\n" > "$prefix/compliant file"
    printf "executable\n" > "$prefix/executable file"
    printf "external\n" > "$external_target"
    ln -s "$external_target" "$prefix/external symlink"

    /bin/chmod 700 "$prefix/restricted directory"
    /bin/chmod 600 "$prefix/restricted file" "$external_target"
    /bin/chmod 644 "$prefix/compliant file"
    /bin/chmod 755 "$prefix/executable file"

    cat > "$fakebin/chmod" <<\SHIM
#!/bin/bash
printf "%s\\n" "$*" >> "$CHMOD_LOG"
exec /bin/chmod "$@"
SHIM
    /bin/chmod 755 "$fakebin/chmod"
    export CHMOD_LOG="$chmod_log"
    export PATH="$fakebin:$PATH"

    repair_proton_prefix_permissions "$prefix"

    printf "directory_mode=%s\n" "$(stat -c %a "$prefix/restricted directory")"
    printf "restricted_mode=%s\n" "$(stat -c %a "$prefix/restricted file")"
    printf "executable_mode=%s\n" "$(stat -c %a "$prefix/executable file")"
    printf "symlink_target_mode=%s\n" "$(stat -c %a "$external_target")"
    printf "restricted_changed=%s\n" "$(grep -Fq "restricted file" "$chmod_log" && echo yes || echo no)"
    printf "compliant_changed=%s\n" "$(grep -Fq "compliant file" "$chmod_log" && echo yes || echo no)"
    printf "executable_changed=%s\n" "$(grep -Fq "executable file" "$chmod_log" && echo yes || echo no)"
    printf "symlink_changed=%s\n" "$(grep -Fq "external symlink" "$chmod_log" && echo yes || echo no)"
  '

  assert_success
  assert_output --partial "directory_mode=755"
  assert_output --partial "restricted_mode=644"
  assert_output --partial "executable_mode=755"
  assert_output --partial "symlink_target_mode=600"
  assert_output --partial "restricted_changed=yes"
  assert_output --partial "compliant_changed=no"
  assert_output --partial "executable_changed=no"
  assert_output --partial "symlink_changed=no"
}

@test "check_critical_file reports missing optional files without failing hard" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/prelaunch_check.sh"
    missing_file="$BATS_TEST_TMPDIR/optional.bin"
    set +e
    check_critical_file "$missing_file" true
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "NOTICE: Optional file not found"
  assert_output --partial "status=1"
}

@test "check_server_files returns pending download when the server executable is missing" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/prelaunch_check.sh"
    ASA_DIR="$BATS_TEST_TMPDIR/asa"
    API=FALSE
    mkdir -p "$ASA_DIR/ShooterGame/Binaries/Win64"
    set +e
    check_server_files
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "Server files check: PENDING DOWNLOAD"
  assert_output --partial "status=1"
}
