#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "rollback_server.sh can be sourced without downloading or activating files" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rollback_server.sh"
    printf "main=%s stage=%s activate=%s\n" \
      "$(type -t main)" "$(type -t stage_rollback)" "$(type -t activate_rollback)"
  '

  assert_success
  assert_output --partial "main=function stage=function activate=function"
}

@test "rollback manifest validation rejects nonnumeric input" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    source "$REPO_ROOT/scripts/rollback_server.sh"
    validate_manifest "6810;rm"
  '

  assert_failure
  assert_output --partial "Depot manifest must contain only digits"
}

@test "rollback depot discovery accepts SteamCMD linux32-relative content" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rollback_server.sh"
    steamcmd_root="$BATS_TEST_TMPDIR/steamcmd"
    depot_root="$steamcmd_root/linux32/steamapps/content/app_2430930/depot_2430931"
    mkdir -p "$depot_root/ShooterGame/Binaries/Win64"
    touch "$depot_root/ShooterGame/Binaries/Win64/ArkAscendedServer.exe"
    discovered=$(find_rollback_depot_root "$steamcmd_root")
    [ "$discovered" = "$depot_root" ]
    cleanup_rollback_downloads "$steamcmd_root"
    [ ! -e "$depot_root" ]
    echo "depot-path=discovered-and-cleaned"
  '

  assert_success
  assert_output "depot-path=discovered-and-cleaned"
}

@test "rollback depot download uses authenticated Steam credentials and a one-run Guard code" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    source "$REPO_ROOT/scripts/rollback_server.sh"
    steamcmd_mock="$BATS_TEST_TMPDIR/steamcmd-mock"
    args_file="$BATS_TEST_TMPDIR/steamcmd-args"
    cat > "$steamcmd_mock" <<'"'"'EOF'"'"'
#!/bin/bash
printf "%s\0" "$@" > "$STEAMCMD_ARGS_FILE"
EOF
    chmod +x "$steamcmd_mock"
    export STEAMCMD_ARGS_FILE="$args_file"
    STEAMCMD_BIN="$steamcmd_mock"
    STEAM_USERNAME="licensed-user"
    STEAM_PASSWORD="test-password"
    STEAM_GUARD_CODE="TEST1"

    download_rollback_manifest 681058914540629286
    mapfile -d "" -t args < "$args_file"
    [ "${args[0]}" = "+@sSteamCmdForcePlatformType" ]
    [ "${args[1]}" = "windows" ]
    [ "${args[2]}" = "+login" ]
    [ "${args[3]}" = "$STEAM_USERNAME" ]
    [ "${args[4]}" = "$STEAM_PASSWORD" ]
    [ "${args[5]}" = "$STEAM_GUARD_CODE" ]
    [ "${args[6]}" = "+download_depot" ]
    [ "${args[7]}" = "2430930" ]
    [ "${args[8]}" = "2430931" ]
    [ "${args[9]}" = "681058914540629286" ]
    [ "${args[10]}" = "+quit" ]
    if printf "%s\n" "${args[@]}" | grep -qx anonymous; then
      exit 1
    fi
    echo "rollback-login=authenticated"
  '

  assert_success
  assert_output --partial "Authenticating to Steam with the supplied one-run Steam Guard code"
  assert_output --partial "rollback-login=authenticated"
  refute_output --partial "TEST1"
}

@test "rollback depot download refuses to run without Steam credentials" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    source "$REPO_ROOT/scripts/rollback_server.sh"
    STEAM_USERNAME=""
    STEAM_PASSWORD=""
    download_rollback_manifest 681058914540629286
  '

  assert_failure
  assert_output --partial "Authenticated Steam credentials are required"
}
