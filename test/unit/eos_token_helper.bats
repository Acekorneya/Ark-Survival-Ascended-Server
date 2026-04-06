#!/usr/bin/env bats

load '../test_helper/bats-support/load.bash'
load '../test_helper/bats-assert/load.bash'
load '../test_helper/project.bash'

@test "eos_token helper matches asa_server_list exchange semantics" {
  run env REPO_ROOT="$PROJECT_ROOT" python3 - <<'PY'
import importlib.util
import os
import pathlib
import re
import urllib.parse

repo = pathlib.Path(os.environ["REPO_ROOT"])
asa_source = (repo / "asa_server_list.py").read_text(encoding="utf-8")

def extract_constant(name: str) -> str:
    match = re.search(rf"^{name}\s*=\s*\"([^\"]+)\"", asa_source, re.MULTILINE)
    assert match, f"missing {name}"
    return match.group(1)

asa_basic_auth = extract_constant("EOS_BASIC_AUTH")
asa_deployment_id = extract_constant("EOS_DEPLOYMENT_ID")

helper_path = repo / "scripts" / "helpers" / "eos_token.py"
spec = importlib.util.spec_from_file_location("eos_token_helper", helper_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

captured = {}

class DummyResponse:
    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def read(self):
        return b'{"access_token":"helper-token","expires_in":60}'

def fake_urlopen(req, timeout=0):
    captured["url"] = req.full_url
    captured["headers"] = {key.lower(): value for key, value in req.header_items()}
    captured["body"] = urllib.parse.parse_qs(req.data.decode("utf-8"))
    return DummyResponse()

module.urllib.request.urlopen = fake_urlopen
exit_code = module.exchange("deadbeef")
assert exit_code == 0, exit_code
assert module.EOS_BASIC_AUTH == asa_basic_auth
assert module.EOS_DEPLOYMENT_ID == asa_deployment_id
assert captured["url"] == "https://api.epicgames.dev/auth/v1/oauth/token"
assert captured["headers"]["authorization"] == asa_basic_auth
assert captured["headers"]["content-type"] == "application/x-www-form-urlencoded"
assert captured["headers"]["accept"] == "application/json"
assert captured["body"]["grant_type"] == ["external_auth"]
assert captured["body"]["external_auth_type"] == ["steam_session_ticket"]
assert captured["body"]["external_auth_token"] == ["DEADBEEF"]
assert captured["body"]["deployment_id"] == [asa_deployment_id]
assert captured["body"]["nonce"] and captured["body"]["nonce"][0]
print("auth=match")
print("ticket=DEADBEEF")
print("external_auth_type=steam_session_ticket")
PY

  assert_success
  assert_output --partial "auth=match"
  assert_output --partial "ticket=DEADBEEF"
  assert_output --partial "external_auth_type=steam_session_ticket"
}
