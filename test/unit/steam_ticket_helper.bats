#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "steam_ticket helper uses createAuthSessionTicket and returns uppercase hex" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    modules_dir="$BATS_TEST_TMPDIR/modules"
    mkdir -p "$modules_dir/steam-user" "$modules_dir/steam-totp"

    cat > "$modules_dir/steam-user/index.js" <<'"'"'EOF'"'"'
const fs = require("fs");
const {EventEmitter} = require("events");

module.exports = class SteamUser extends EventEmitter {
  logOn() {
    setImmediate(() => this.emit("loggedOn"));
  }

  gamesPlayed() {}

  getAuthSessionTicket() {
    fs.writeFileSync(process.env.TEST_MARKER, "wrong-api");
    throw new Error("getAuthSessionTicket should not be used");
  }

  createAuthSessionTicket(appId, callback) {
    fs.writeFileSync(process.env.TEST_MARKER, `create:${appId}`);
    callback(null, Buffer.alloc(64, 0xab));
  }

  logOff() {}
};
EOF

    cat > "$modules_dir/steam-totp/index.js" <<'"'"'EOF'"'"'
module.exports = {
  getTimeOffset(callback) { callback(null, 0); },
  generateAuthCode() { return "000000"; }
};
EOF

    TEST_MARKER="$BATS_TEST_TMPDIR/steam-ticket-marker"
    set +e
    output=$(NODE_PATH="$modules_dir" TEST_MARKER="$TEST_MARKER" STEAM_USERNAME="user" STEAM_PASSWORD="pass" timeout 5 node "$REPO_ROOT/scripts/helpers/steam_ticket.js")
    status=$?
    set -e
    printf "status=%s\n" "$status"
    printf "output=%s\n" "$output"
    printf "marker=%s\n" "$(cat "$TEST_MARKER")"
  '

  assert_success
  assert_output --partial "status=0"
  assert_output --partial "marker=create:2399830"
  assert_output --partial "output=ABABABAB"
}

@test "steam_ticket helper rejects unexpectedly short tickets" {
  run env REPO_ROOT="$PROJECT_ROOT" bash -lc '
    set -e
    modules_dir="$BATS_TEST_TMPDIR/modules"
    mkdir -p "$modules_dir/steam-user" "$modules_dir/steam-totp"

    cat > "$modules_dir/steam-user/index.js" <<'"'"'EOF'"'"'
const {EventEmitter} = require("events");

module.exports = class SteamUser extends EventEmitter {
  logOn() {
    setImmediate(() => this.emit("loggedOn"));
  }

  gamesPlayed() {}

  createAuthSessionTicket(appId, callback) {
    callback(null, Buffer.alloc(21, 0xcd));
  }

  logOff() {}
};
EOF

    cat > "$modules_dir/steam-totp/index.js" <<'"'"'EOF'"'"'
module.exports = {
  getTimeOffset(callback) { callback(null, 0); },
  generateAuthCode() { return "000000"; }
};
EOF

    set +e
    NODE_PATH="$modules_dir" STEAM_USERNAME="user" STEAM_PASSWORD="pass" timeout 5 node "$REPO_ROOT/scripts/helpers/steam_ticket.js"
    status=$?
    set -e
    printf "status=%s\n" "$status"
  '

  assert_success
  assert_output --partial "Failed to get auth ticket: Steam session ticket is unexpectedly short (21 bytes)"
  assert_output --partial "status=1"
}
