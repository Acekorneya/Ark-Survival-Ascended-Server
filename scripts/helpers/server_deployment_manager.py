#!/usr/bin/env python3
"""Track verified ASA deployments and rollback transactions."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import time


APP_ID = "2430930"
DEPOT_ID = "2430931"
FALLBACK_MANIFEST = "681058914540629286"
MAX_HISTORY = 5


class DeploymentError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def fsync_directory(path: Path) -> None:
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    except OSError:
        return
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def atomic_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
        fsync_directory(path.parent)
    finally:
        temporary.unlink(missing_ok=True)


def read_object(path: Path, *, required: bool = False) -> dict:
    if not path.is_file():
        if required:
            raise DeploymentError(f"Required deployment state is missing: {path}")
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise DeploymentError(f"Invalid deployment state {path}: {error}") from error
    if not isinstance(value, dict):
        raise DeploymentError(f"Deployment state must be a JSON object: {path}")
    return value


def require_digits(label: str, value: str) -> str:
    if not value or not value.isdecimal():
        raise DeploymentError(f"{label} must contain only digits")
    return value


def acf_value(content: str, key: str) -> str:
    match = re.search(rf'"{re.escape(key)}"\s+"([^"]+)"', content, re.IGNORECASE)
    return match.group(1) if match else ""


def acf_depot_manifest(content: str, depot_id: str = DEPOT_ID) -> str:
    block = re.search(rf'"{re.escape(depot_id)}"\s*\{{([^{{}}]*)\}}', content, re.DOTALL)
    if not block:
        return ""
    return acf_value(block.group(1), "manifest")


def active_state(state_dir: Path) -> dict:
    value = read_object(state_dir / "active_rollback.json")
    if value.get("version") != 1:
        return {}
    return value


def select_manifest(args: argparse.Namespace) -> int:
    current_hash = args.current_hash.lower()
    history = read_object(args.state_dir / "known_good.json").get("deployments", [])
    if isinstance(history, list):
        for entry in history:
            if not isinstance(entry, dict):
                continue
            manifest = str(entry.get("depot_manifest", ""))
            executable_hash = str(entry.get("executable_sha256", "")).lower()
            if manifest.isdecimal() and executable_hash and executable_hash != current_hash:
                print(manifest)
                return 0
    print(FALLBACK_MANIFEST)
    return 0


def begin(args: argparse.Namespace) -> int:
    manifest = require_digits("Depot manifest", args.manifest)
    executable_hash = args.executable_hash.lower()
    if not re.fullmatch(r"[0-9a-f]{64}", executable_hash):
        raise DeploymentError("Staged executable SHA-256 is invalid")
    value = {
        "version": 1,
        "app_id": APP_ID,
        "depot_id": DEPOT_ID,
        "depot_manifest": manifest,
        "executable_sha256": executable_hash,
        "failed_build_id": args.failed_build_id if args.failed_build_id.isdecimal() else "",
        "failed_executable_sha256": args.failed_executable_hash.lower(),
        "failed_cache_last_modified": args.failed_cache_last_modified,
        "started_at": int(time.time()),
        "status": "staged",
    }
    atomic_json(args.state_dir / "rollback_transaction.json", value)
    return 0


def activate(args: argparse.Namespace) -> int:
    transaction_path = args.state_dir / "rollback_transaction.json"
    transaction = read_object(transaction_path, required=True)
    manifest = require_digits("Depot manifest", args.manifest)
    if transaction.get("status") != "staged" or transaction.get("depot_manifest") != manifest:
        raise DeploymentError("Rollback transaction does not match the requested manifest")
    if not args.server_exe.is_file():
        raise DeploymentError(f"Activated server executable is missing: {args.server_exe}")
    actual_hash = sha256_file(args.server_exe)
    if actual_hash != transaction.get("executable_sha256"):
        raise DeploymentError("Activated server executable does not match the staged transaction")
    transaction["status"] = "active"
    transaction["activated_at"] = int(time.time())
    atomic_json(args.state_dir / "active_rollback.json", transaction)
    transaction_path.unlink(missing_ok=True)
    fsync_directory(args.state_dir)
    return 0


def abort(args: argparse.Namespace) -> int:
    (args.state_dir / "rollback_transaction.json").unlink(missing_ok=True)
    fsync_directory(args.state_dir)
    return 0


def clear_active(args: argparse.Namespace) -> int:
    (args.state_dir / "active_rollback.json").unlink(missing_ok=True)
    fsync_directory(args.state_dir)
    return 0


def update_failure(args: argparse.Namespace) -> int:
    path = args.state_dir / "active_rollback.json"
    value = active_state(args.state_dir)
    if not value:
        raise DeploymentError("No active rollback state exists")
    executable_hash = args.executable_hash.lower()
    if not re.fullmatch(r"[0-9a-f]{64}", executable_hash):
        raise DeploymentError("Failed candidate executable SHA-256 is invalid")
    value["failed_build_id"] = args.failed_build_id if args.failed_build_id.isdecimal() else ""
    value["failed_executable_sha256"] = executable_hash
    value["failed_cache_last_modified"] = args.failed_cache_last_modified
    value["last_failed_preflight_at"] = int(time.time())
    atomic_json(path, value)
    return 0


def field(args: argparse.Namespace) -> int:
    source = active_state(args.state_dir) if args.source == "active" else read_object(
        args.state_dir / "rollback_transaction.json"
    )
    value = source.get(args.name, "")
    if isinstance(value, (str, int)):
        print(value)
        return 0 if str(value) else 1
    return 1


def record_success(args: argparse.Namespace) -> int:
    if not args.server_exe.is_file():
        raise DeploymentError(f"Server executable is missing: {args.server_exe}")
    source = read_object(args.api_source, required=True)
    if source.get("source") != "managed":
        raise DeploymentError("Only managed AsaApi deployments can be recorded as known-good")
    cache = read_object(args.cache_metadata, required=True)
    executable_hash = sha256_file(args.server_exe)
    if str(cache.get("executable_hash", "")).lower() != executable_hash:
        raise DeploymentError("AsaApi cache metadata does not match the running server executable")

    build_id = ""
    manifest = ""
    if args.appmanifest.is_file():
        content = args.appmanifest.read_text(encoding="utf-8", errors="replace")
        build_id = acf_value(content, "buildid")
        manifest = acf_depot_manifest(content)
    active = active_state(args.state_dir)
    if active and active.get("executable_sha256") == executable_hash:
        manifest = str(active.get("depot_manifest", ""))
    if not manifest.isdecimal():
        raise DeploymentError("The running deployment has no attributable Steam depot manifest")

    entry = {
        "app_id": APP_ID,
        "depot_id": DEPOT_ID,
        "depot_manifest": manifest,
        "steam_build_id": build_id if build_id.isdecimal() else "",
        "executable_sha256": executable_hash,
        "asaapi_version": str(source.get("version", "")),
        "asaapi_core_sha256": str(source.get("core_sha256", "")),
        "cache_last_modified": str(cache.get("last_modified", "")),
        "instance_name": args.instance_name,
        "recorded_at": int(time.time()),
    }
    history_path = args.state_dir / "known_good.json"
    history = read_object(history_path).get("deployments", [])
    if not isinstance(history, list):
        history = []
    kept = [
        value for value in history
        if isinstance(value, dict)
        and value.get("depot_manifest") != manifest
        and value.get("executable_sha256") != executable_hash
    ]
    atomic_json(history_path, {"version": 1, "deployments": [entry, *kept][:MAX_HISTORY]})
    print(manifest)
    return 0


def status(args: argparse.Namespace) -> int:
    value = active_state(args.state_dir)
    print(json.dumps(value, sort_keys=True))
    return 0 if value else 1


def build_parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)

    select = commands.add_parser("select-manifest")
    select.add_argument("--state-dir", type=Path, required=True)
    select.add_argument("--current-hash", default="")
    select.set_defaults(handler=select_manifest)

    begin_parser = commands.add_parser("begin")
    begin_parser.add_argument("--state-dir", type=Path, required=True)
    begin_parser.add_argument("--manifest", required=True)
    begin_parser.add_argument("--executable-hash", required=True)
    begin_parser.add_argument("--failed-build-id", default="")
    begin_parser.add_argument("--failed-executable-hash", default="")
    begin_parser.add_argument("--failed-cache-last-modified", default="")
    begin_parser.set_defaults(handler=begin)

    activate_parser = commands.add_parser("activate")
    activate_parser.add_argument("--state-dir", type=Path, required=True)
    activate_parser.add_argument("--manifest", required=True)
    activate_parser.add_argument("--server-exe", type=Path, required=True)
    activate_parser.set_defaults(handler=activate)

    for name, handler in (("abort", abort), ("clear-active", clear_active), ("status", status)):
        command = commands.add_parser(name)
        command.add_argument("--state-dir", type=Path, required=True)
        command.set_defaults(handler=handler)

    failure = commands.add_parser("update-failure")
    failure.add_argument("--state-dir", type=Path, required=True)
    failure.add_argument("--failed-build-id", default="")
    failure.add_argument("--executable-hash", required=True)
    failure.add_argument("--failed-cache-last-modified", default="")
    failure.set_defaults(handler=update_failure)

    field_parser = commands.add_parser("field")
    field_parser.add_argument("--state-dir", type=Path, required=True)
    field_parser.add_argument("--source", choices=("active", "transaction"), required=True)
    field_parser.add_argument("--name", required=True)
    field_parser.set_defaults(handler=field)

    record = commands.add_parser("record-success")
    record.add_argument("--state-dir", type=Path, required=True)
    record.add_argument("--server-exe", type=Path, required=True)
    record.add_argument("--appmanifest", type=Path, required=True)
    record.add_argument("--api-source", type=Path, required=True)
    record.add_argument("--cache-metadata", type=Path, required=True)
    record.add_argument("--instance-name", required=True)
    record.set_defaults(handler=record_success)
    return root


def main() -> int:
    args = build_parser().parse_args()
    try:
        return args.handler(args)
    except DeploymentError as error:
        print(f"[ERROR] {error}", file=os.sys.stderr)
        return 20


if __name__ == "__main__":
    raise SystemExit(main())
