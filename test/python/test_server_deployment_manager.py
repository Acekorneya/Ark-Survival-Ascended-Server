#!/usr/bin/env python3

from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import types
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
HELPER_PATH = PROJECT_ROOT / "scripts/helpers/server_deployment_manager.py"
SPEC = importlib.util.spec_from_file_location("server_deployment_manager", HELPER_PATH)
assert SPEC is not None and SPEC.loader is not None
deployment = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(deployment)


class ServerDeploymentManagerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.state_dir = self.root / "state"
        self.state_dir.mkdir()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_parses_build_and_depot_manifest_from_acf(self) -> None:
        content = '''"AppState"
{
  "buildid" "24226775"
  "InstalledDepots"
  {
    "2430931" { "manifest" "681058914540629286" "size" "123" }
  }
}
'''
        self.assertEqual(deployment.acf_value(content, "buildid"), "24226775")
        self.assertEqual(deployment.acf_depot_manifest(content), "681058914540629286")

    def test_selects_newest_distinct_known_good_then_bootstrap_fallback(self) -> None:
        current_hash = "a" * 64
        history = {
            "version": 1,
            "deployments": [
                {"depot_manifest": "111", "executable_sha256": current_hash},
                {"depot_manifest": "222", "executable_sha256": "b" * 64},
            ],
        }
        (self.state_dir / "known_good.json").write_text(json.dumps(history), encoding="utf-8")
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = deployment.select_manifest(types.SimpleNamespace(
                state_dir=self.state_dir, current_hash=current_hash
            ))
        self.assertEqual(result, 0)
        self.assertEqual(output.getvalue().strip(), "222")

        (self.state_dir / "known_good.json").unlink()
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            deployment.select_manifest(types.SimpleNamespace(
                state_dir=self.state_dir, current_hash=current_hash
            ))
        self.assertEqual(output.getvalue().strip(), deployment.FALLBACK_MANIFEST)

    def test_transaction_activation_verifies_the_live_executable(self) -> None:
        server_exe = self.root / "ArkAscendedServer.exe"
        server_exe.write_bytes(b"rollback-server")
        executable_hash = hashlib.sha256(server_exe.read_bytes()).hexdigest()
        begin_args = types.SimpleNamespace(
            state_dir=self.state_dir,
            manifest="681058914540629286",
            executable_hash=executable_hash,
            failed_build_id="24226775",
            failed_executable_hash="c" * 64,
            failed_cache_last_modified="failed-v1",
        )
        self.assertEqual(deployment.begin(begin_args), 0)
        self.assertEqual(deployment.activate(types.SimpleNamespace(
            state_dir=self.state_dir,
            manifest="681058914540629286",
            server_exe=server_exe,
        )), 0)
        active = json.loads((self.state_dir / "active_rollback.json").read_text(encoding="utf-8"))
        self.assertEqual(active["status"], "active")
        self.assertEqual(active["failed_build_id"], "24226775")
        self.assertFalse((self.state_dir / "rollback_transaction.json").exists())

        self.assertEqual(deployment.update_failure(types.SimpleNamespace(
            state_dir=self.state_dir,
            failed_build_id="24230000",
            executable_hash="d" * 64,
            failed_cache_last_modified="failed-v2",
        )), 0)
        updated = json.loads((self.state_dir / "active_rollback.json").read_text(encoding="utf-8"))
        self.assertEqual(updated["failed_build_id"], "24230000")
        self.assertEqual(updated["failed_cache_last_modified"], "failed-v2")

    def test_record_success_uses_active_manifest_and_bounds_history(self) -> None:
        server_exe = self.root / "ArkAscendedServer.exe"
        server_exe.write_bytes(b"known-good")
        executable_hash = hashlib.sha256(server_exe.read_bytes()).hexdigest()
        source = self.root / "source.json"
        cache = self.root / "cached_key.cache"
        appmanifest = self.root / "appmanifest.acf"
        source.write_text(json.dumps({
            "source": "managed", "version": "2.01", "core_sha256": "api-hash"
        }), encoding="utf-8")
        cache.write_text(json.dumps({
            "executable_hash": executable_hash, "last_modified": "cache-v1"
        }), encoding="utf-8")
        appmanifest.write_text('"buildid" "24226775"', encoding="utf-8")
        (self.state_dir / "active_rollback.json").write_text(json.dumps({
            "version": 1,
            "depot_manifest": "681058914540629286",
            "executable_sha256": executable_hash,
        }), encoding="utf-8")
        (self.state_dir / "known_good.json").write_text(json.dumps({
            "version": 1,
            "deployments": [
                {"depot_manifest": str(index), "executable_sha256": f"{index:064x}"}
                for index in range(10, 16)
            ],
        }), encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(deployment.record_success(types.SimpleNamespace(
                state_dir=self.state_dir,
                server_exe=server_exe,
                api_source=source,
                cache_metadata=cache,
                appmanifest=appmanifest,
                instance_name="alpha",
            )), 0)
        history = json.loads((self.state_dir / "known_good.json").read_text(encoding="utf-8"))
        self.assertEqual(len(history["deployments"]), 5)
        self.assertEqual(history["deployments"][0]["depot_manifest"], "681058914540629286")

    def test_custom_api_cannot_be_recorded_as_known_good(self) -> None:
        server_exe = self.root / "ArkAscendedServer.exe"
        server_exe.write_bytes(b"server")
        source = self.root / "source.json"
        cache = self.root / "cache.json"
        appmanifest = self.root / "acf"
        source.write_text('{"source":"custom"}', encoding="utf-8")
        cache.write_text("{}", encoding="utf-8")
        appmanifest.write_text("", encoding="utf-8")
        with self.assertRaises(deployment.DeploymentError):
            deployment.record_success(types.SimpleNamespace(
                state_dir=self.state_dir,
                server_exe=server_exe,
                api_source=source,
                cache_metadata=cache,
                appmanifest=appmanifest,
                instance_name="alpha",
            ))


if __name__ == "__main__":
    unittest.main()
