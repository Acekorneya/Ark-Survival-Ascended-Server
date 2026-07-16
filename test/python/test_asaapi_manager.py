#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import types
import unittest
from unittest import mock
import zipfile


PROJECT_ROOT = Path(__file__).resolve().parents[2]
HELPER_PATH = PROJECT_ROOT / "scripts/helpers/asaapi_manager.py"
SPEC = importlib.util.spec_from_file_location("asaapi_manager", HELPER_PATH)
assert SPEC is not None and SPEC.loader is not None
asaapi_manager = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(asaapi_manager)


def release_archive(path: Path, dll_content: bytes = b"managed-dll") -> str:
    config = {
        "settings": {
            "AutomaticCacheDownload": {
                "Enable": True,
                "DownloadCacheURL": "https://cdn.example.invalid/cache/",
            },
            "PreservedSetting": "yes",
        }
    }
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("AsaApiLoader.exe", b"loader")
        archive.writestr("ArkApi/AsaApi.dll", dll_content)
        archive.writestr("config.json", json.dumps(config))
        archive.writestr("ArkApi/Plugins/Permissions/Permissions.dll", b"permissions")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def serialized_map(value_size: int, entries: tuple[tuple[bytes, bytes], ...]) -> bytes:
    result = bytearray()
    for key, value in entries:
        assert len(value) == value_size
        result.extend(struct.pack("<Q", len(key)))
        result.extend(key)
        result.extend(value)
    return bytes(result)


def cache_archive(path: Path, *, extra: str | None = None) -> None:
    required = next(iter(asaapi_manager.REQUIRED_CORE_OFFSETS)).encode("utf-8")
    offsets = serialized_map(8, ((b"offset-key", b"\x01" * 8), (required, b"\x03" * 8)))
    bitfields = serialized_map(32, ((b"bitfield-key", b"\x02" * 32),))
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("cached_offsets.cache", offsets)
        archive.writestr("cached_bitfields.cache", bitfields)
        archive.writestr("cached_offsets.txt", f"offset-key\n{required.decode()}\n")
        if extra is not None:
            archive.writestr(extra, b"unexpected")


class AsaApiManagerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.bin_dir = self.root / "Win64"
        self.state_dir = self.root / "state"
        self.bin_dir.mkdir()
        self.state_dir.mkdir()
        self.release = self.root / "AsaApi_2.01.zip"
        self.release_sha = release_archive(self.release)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def install_args(self) -> types.SimpleNamespace:
        return types.SimpleNamespace(
            bin_dir=self.bin_dir,
            state_dir=self.state_dir,
            base_version="2.01",
            base_url=self.release.as_uri(),
            base_sha256=self.release_sha,
        )

    def install_managed(self) -> None:
        self.assertEqual(asaapi_manager.install_source(self.install_args()), 0)

    def prepare_args(self, server_exe: Path) -> types.SimpleNamespace:
        return types.SimpleNamespace(
            bin_dir=self.bin_dir,
            state_dir=self.state_dir,
            server_exe=server_exe,
        )

    def test_managed_install_is_pinned_persistent_and_preserves_existing_config(self) -> None:
        existing_config = {
            "settings": {
                "AutomaticCacheDownload": {
                    "Enable": True,
                    "DownloadCacheURL": "https://mirror.example/cache/",
                },
                "UserSetting": 42,
            }
        }
        (self.bin_dir / "config.json").write_text(json.dumps(existing_config), encoding="utf-8")

        self.install_managed()

        state = json.loads((self.state_dir / "source.json").read_text(encoding="utf-8"))
        installed_config = json.loads((self.bin_dir / "config.json").read_text(encoding="utf-8"))
        self.assertEqual(state["source"], "managed")
        self.assertEqual(state["version"], "2.01")
        self.assertEqual(installed_config["settings"]["UserSetting"], 42)
        self.assertEqual((self.bin_dir / ".asaapi_version").read_text().strip(), "2.01")
        self.assertEqual(
            hashlib.sha256((self.state_dir / "AsaApi_2.01.zip").read_bytes()).hexdigest(),
            self.release_sha,
        )

    def test_custom_override_takes_precedence_and_removal_restores_managed_release(self) -> None:
        self.install_managed()
        custom = self.bin_dir / "AsaApi_Custom"
        (custom / "ArkApi").mkdir(parents=True)
        (custom / "AsaApiLoader.exe").write_bytes(b"custom-loader")
        (custom / "ArkApi/AsaApi.dll").write_bytes(b"custom-dll")
        (custom / "config.json").write_text('{"settings": {"custom": true}}', encoding="utf-8")

        self.assertEqual(asaapi_manager.install_source(self.install_args()), 0)
        state = json.loads((self.state_dir / "source.json").read_text(encoding="utf-8"))
        self.assertEqual(state["source"], "custom")
        self.assertEqual((self.bin_dir / "ArkApi/AsaApi.dll").read_bytes(), b"custom-dll")

        shutil.rmtree(custom)
        self.assertEqual(asaapi_manager.install_source(self.install_args()), 0)
        state = json.loads((self.state_dir / "source.json").read_text(encoding="utf-8"))
        self.assertEqual(state["source"], "managed")
        self.assertEqual((self.bin_dir / "ArkApi/AsaApi.dll").read_bytes(), b"managed-dll")
        self.assertTrue((self.state_dir / "config.custom-backup.json").is_file())

    def test_invalid_custom_override_does_not_silently_fall_back(self) -> None:
        (self.bin_dir / "AsaApi_Custom").mkdir()
        with self.assertRaises(asaapi_manager.InvalidError):
            asaapi_manager.install_source(self.install_args())
        self.assertFalse((self.state_dir / "source.json").exists())

    def test_prepare_cache_installs_matching_generation_and_disables_windows_download(self) -> None:
        self.install_managed()
        server_exe = self.bin_dir / "ArkAscendedServer.exe"
        server_exe.write_bytes(b"server-build-one")
        executable_hash = hashlib.sha256(server_exe.read_bytes()).hexdigest()
        remote_archive = self.root / f"{executable_hash}.zip"
        cache_archive(remote_archive)

        def fake_download(_url: str, destination: Path, header_path: Path | None = None) -> None:
            shutil.copy2(remote_archive, destination)
            if header_path is not None:
                header_path.write_text("Last-Modified: fixture-v1\n", encoding="ascii")

        with mock.patch.object(asaapi_manager, "remote_last_modified", return_value="fixture-v1"), \
                mock.patch.object(asaapi_manager, "download_file", side_effect=fake_download):
            self.assertEqual(asaapi_manager.prepare_cache(self.prepare_args(server_exe)), 0)

        metadata = json.loads(
            (self.bin_dir / "ArkApi/Cache/cached_key.cache").read_text(encoding="utf-8")
        )
        generation = self.bin_dir / "ArkApi/Cache" / metadata["cache_directory"]
        config = json.loads((self.bin_dir / "config.json").read_text(encoding="utf-8"))
        self.assertEqual(metadata["executable_hash"], executable_hash)
        self.assertEqual(metadata["last_modified"], "fixture-v1")
        self.assertTrue((generation / "cached_offsets.cache").is_file())
        self.assertTrue((generation / "cached_bitfields.cache").is_file())
        self.assertTrue((generation / "cached_offsets.txt").is_file())
        self.assertFalse(config["settings"]["AutomaticCacheDownload"]["Enable"])

        with mock.patch.object(asaapi_manager, "remote_last_modified", return_value=None), \
                mock.patch.object(asaapi_manager, "download_file", side_effect=AssertionError("downloaded")):
            self.assertEqual(asaapi_manager.prepare_cache(self.prepare_args(server_exe)), 0)

    def test_cache_archive_rejects_unknown_and_traversal_entries(self) -> None:
        unknown = self.root / "unknown.zip"
        cache_archive(unknown, extra="unexpected.dll")
        with self.assertRaises(asaapi_manager.InvalidError):
            asaapi_manager.validate_cache_archive(unknown)

        traversal = self.root / "traversal.zip"
        cache_archive(traversal, extra="../cached_key.cache")
        with self.assertRaises(asaapi_manager.InvalidError):
            asaapi_manager.validate_cache_archive(traversal)

    def test_cache_missing_required_core_offset_is_rejected(self) -> None:
        archive_path = self.root / "missing-core-offset.zip"
        offsets = serialized_map(8, ((b"offset-key", b"\x01" * 8),))
        bitfields = serialized_map(32, ((b"bitfield-key", b"\x02" * 32),))
        with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("cached_offsets.cache", offsets)
            archive.writestr("cached_bitfields.cache", bitfields)
            archive.writestr("cached_offsets.txt", "offset-key\n")

        cache_root = self.bin_dir / "ArkApi/Cache"
        cache_root.mkdir(parents=True)
        with self.assertRaisesRegex(
            asaapi_manager.InvalidError,
            "AShooterGameMode.Logout",
        ):
            asaapi_manager.extract_and_validate_cache(archive_path, cache_root, "a" * 64)

    def test_incompatible_cache_is_not_downloaded_again_until_remote_changes(self) -> None:
        self.install_managed()
        server_exe = self.bin_dir / "ArkAscendedServer.exe"
        server_exe.write_bytes(b"server-build-incompatible")
        executable_hash = hashlib.sha256(server_exe.read_bytes()).hexdigest()
        bad_archive = self.root / "bad.zip"
        offsets = serialized_map(8, ((b"offset-key", b"\x01" * 8),))
        bitfields = serialized_map(32, ((b"bitfield-key", b"\x02" * 32),))
        with zipfile.ZipFile(bad_archive, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("cached_offsets.cache", offsets)
            archive.writestr("cached_bitfields.cache", bitfields)

        good_archive = self.root / "good.zip"
        cache_archive(good_archive)

        def download_bad(_url: str, destination: Path, header_path: Path | None = None) -> None:
            shutil.copy2(bad_archive, destination)
            if header_path is not None:
                header_path.write_text("Last-Modified: fixture-v1\n", encoding="ascii")

        with mock.patch.object(asaapi_manager, "remote_last_modified", return_value="fixture-v1"), \
                mock.patch.object(asaapi_manager, "download_file", side_effect=download_bad):
            with self.assertRaisesRegex(asaapi_manager.InvalidError, executable_hash):
                asaapi_manager.prepare_cache(self.prepare_args(server_exe))

        with mock.patch.object(asaapi_manager, "remote_last_modified", return_value="fixture-v1"), \
                mock.patch.object(asaapi_manager, "download_file", side_effect=AssertionError("downloaded")):
            with self.assertRaisesRegex(asaapi_manager.InvalidError, "remains unusable"):
                asaapi_manager.prepare_cache(self.prepare_args(server_exe))

        def download_good(_url: str, destination: Path, header_path: Path | None = None) -> None:
            shutil.copy2(good_archive, destination)
            if header_path is not None:
                header_path.write_text("Last-Modified: fixture-v2\n", encoding="ascii")

        with mock.patch.object(asaapi_manager, "remote_last_modified", return_value="fixture-v2"), \
                mock.patch.object(asaapi_manager, "download_file", side_effect=download_good):
            self.assertEqual(asaapi_manager.prepare_cache(self.prepare_args(server_exe)), 0)
        self.assertFalse((self.bin_dir / "ArkApi/Cache/incompatible_cache.json").exists())

    def test_serialized_cache_validation_rejects_duplicate_and_truncated_entries(self) -> None:
        duplicate = self.root / "duplicate.cache"
        duplicate.write_bytes(serialized_map(8, ((b"key", b"\x00" * 8), (b"key", b"\x01" * 8))))
        with self.assertRaises(asaapi_manager.InvalidError):
            asaapi_manager.validate_serialized_map(duplicate, 8)

        truncated = self.root / "truncated.cache"
        truncated.write_bytes(struct.pack("<Q", 20) + b"short")
        with self.assertRaises(asaapi_manager.InvalidError):
            asaapi_manager.validate_serialized_map(truncated, 8)

    def test_two_processes_share_one_cache_download(self) -> None:
        self.install_managed()
        server_exe = self.bin_dir / "ArkAscendedServer.exe"
        server_exe.write_bytes(b"server-build-concurrent")
        executable_hash = hashlib.sha256(server_exe.read_bytes()).hexdigest()
        remote_archive = self.root / f"{executable_hash}.zip"
        cache_archive(remote_archive)
        curl_count = self.root / "curl-count"
        fake_curl = self.root / "fake-curl"
        fake_curl.write_text(
            """#!/bin/bash
set -e
output=""
headers=""
head_only=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --dump-header) headers="$2"; shift 2 ;;
    --head) head_only=true; shift ;;
    *) shift ;;
  esac
done
if [ "$head_only" = true ]; then
  printf 'Last-Modified: fixture-concurrent\\n'
  exit 0
fi
printf 'GET\\n' >> "$CURL_COUNT"
cp "$REMOTE_ZIP" "$output"
if [ -n "$headers" ]; then
  printf 'Last-Modified: fixture-concurrent\\n' > "$headers"
fi
""",
            encoding="utf-8",
        )
        fake_curl.chmod(0o755)
        command = [
            "python3",
            "-B",
            str(HELPER_PATH),
            "prepare-cache",
            "--bin-dir",
            str(self.bin_dir),
            "--state-dir",
            str(self.state_dir),
            "--server-exe",
            str(server_exe),
        ]
        environment = os.environ.copy()
        environment.update({
            "ASAAPI_CURL_BIN": str(fake_curl),
            "CURL_COUNT": str(curl_count),
            "REMOTE_ZIP": str(remote_archive),
        })
        first = subprocess.Popen(command, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        second = subprocess.Popen(command, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        first_output, first_error = first.communicate(timeout=20)
        second_output, second_error = second.communicate(timeout=20)
        self.assertEqual(first.returncode, 0, first_output + first_error)
        self.assertEqual(second.returncode, 0, second_output + second_error)
        self.assertEqual(curl_count.read_text(encoding="utf-8").splitlines(), ["GET"])


if __name__ == "__main__":
    unittest.main()
