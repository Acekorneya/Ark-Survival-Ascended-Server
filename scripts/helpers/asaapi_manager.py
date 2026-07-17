#!/usr/bin/env python3
"""Manage the tested AsaApi release and its executable-specific cache."""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import time
import zipfile


BASE_VERSION = "2.01"
BASE_URL = "https://github.com/ArkServerApi/AsaApi/releases/download/2.01/AsaApi_2.01.zip"
BASE_SHA256 = "4cc3afdb5d272e196ee5f4293daac4ece84c86cd6c8e8302c2a6f58cd0dbc496"
DEFAULT_CACHE_URL = "https://cdn.pelayori.com/cache/"

EXIT_RETRY = 10
EXIT_INVALID = 20
EXIT_CUSTOM = 30

MAX_ARCHIVE_SIZE = 768 * 1024 * 1024
MAX_CACHE_ENTRY_SIZE = 512 * 1024 * 1024
MAX_CACHE_TOTAL_SIZE = 768 * 1024 * 1024
MAX_CACHE_KEY_SIZE = 1024 * 1024
MAX_CACHE_ENTRIES = 5_000_000

REQUIRED_RELEASE_FILES = (
    "AsaApiLoader.exe",
    "ArkApi/AsaApi.dll",
    "config.json",
)
REQUIRED_CACHE_FILES = {
    "cached_offsets.cache": 8,
    "cached_bitfields.cache": 32,
}
REQUIRED_CORE_OFFSETS = frozenset({
    "AShooterGameMode.Logout(AController*)",
})
ALLOWED_CACHE_FILES = set(REQUIRED_CACHE_FILES) | {
    "cached_offsets.txt",
    "cached_key.cache",
}


class RetryableError(RuntimeError):
    pass


class InvalidError(RuntimeError):
    pass


def log(level: str, message: str) -> None:
    print(f"[{level}] {message}", flush=True)


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


def atomic_write(path: Path, content: bytes, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
        fsync_directory(path.parent)
    finally:
        temporary.unlink(missing_ok=True)


def atomic_write_json(path: Path, value: object) -> None:
    atomic_write(path, (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8"))


@contextlib.contextmanager
def manager_lock(state_dir: Path):
    state_dir.mkdir(parents=True, exist_ok=True)
    lock_path = state_dir / "manager.lock"
    with lock_path.open("a+b") as lock_handle:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InvalidError(f"Unable to read valid JSON from {path}: {error}") from error
    if not isinstance(value, dict):
        raise InvalidError(f"Expected a JSON object in {path}")
    return value


def read_state(state_dir: Path) -> dict:
    path = state_dir / "source.json"
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def write_state(state_dir: Path, value: dict) -> None:
    atomic_write_json(state_dir / "source.json", value)


def curl_binary() -> str:
    return os.environ.get("ASAAPI_CURL_BIN", "curl")


def run_curl(arguments: list[str], *, capture: bool = False) -> subprocess.CompletedProcess:
    command = [curl_binary(), *arguments]
    try:
        return subprocess.run(
            command,
            check=False,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE,
            text=capture,
        )
    except OSError as error:
        raise RetryableError(f"Unable to execute {curl_binary()}: {error}") from error


def download_file(url: str, destination: Path, header_path: Path | None = None) -> None:
    arguments = [
        "--fail",
        "--show-error",
        "--silent",
        "--location",
        "--retry",
        "3",
        "--retry-all-errors",
        "--connect-timeout",
        "15",
        "--max-time",
        "900",
        "--max-filesize",
        str(MAX_ARCHIVE_SIZE),
    ]
    if header_path is not None:
        arguments.extend(["--dump-header", str(header_path)])
    arguments.extend(["--output", str(destination), url])
    result = run_curl(arguments)
    if result.returncode != 0:
        raise RetryableError(f"Download failed for {url} (curl exit {result.returncode})")
    try:
        size = destination.stat().st_size
    except OSError as error:
        raise RetryableError(f"Downloaded file is unavailable: {error}") from error
    if size <= 0 or size > MAX_ARCHIVE_SIZE:
        raise InvalidError(f"Downloaded archive size {size} is outside the allowed range")


def last_modified_from_headers(content: str) -> str:
    last_modified = ""
    for line in content.splitlines():
        name, separator, value = line.partition(":")
        if separator and name.strip().lower() == "last-modified":
            last_modified = value.strip()
    return last_modified


def remote_last_modified(url: str) -> str | None:
    result = run_curl(
        [
            "--fail",
            "--show-error",
            "--silent",
            "--location",
            "--head",
            "--connect-timeout",
            "10",
            "--max-time",
            "30",
            url,
        ],
        capture=True,
    )
    if result.returncode != 0:
        return None
    return last_modified_from_headers(result.stdout) or None


def safe_zip_name(name: str) -> bool:
    if not name or "\x00" in name or "\\" in name:
        return False
    path = PurePosixPath(name)
    return not path.is_absolute() and ".." not in path.parts


def zip_member_is_symlink(member: zipfile.ZipInfo) -> bool:
    mode = member.external_attr >> 16
    return bool(mode) and stat.S_ISLNK(mode)


def validate_release_archive(path: Path) -> None:
    if sha256_file(path) == "":
        raise InvalidError("Unable to hash AsaApi release archive")
    try:
        with zipfile.ZipFile(path) as archive:
            seen: set[str] = set()
            for member in archive.infolist():
                if not safe_zip_name(member.filename) or zip_member_is_symlink(member):
                    raise InvalidError(f"Unsafe AsaApi release entry: {member.filename!r}")
                normalized = member.filename.rstrip("/")
                if normalized in seen:
                    raise InvalidError(f"Duplicate AsaApi release entry: {member.filename}")
                seen.add(normalized)
            for required in REQUIRED_RELEASE_FILES:
                if required not in seen:
                    raise InvalidError(f"AsaApi release is missing {required}")
            if archive.testzip() is not None:
                raise InvalidError("AsaApi release archive failed its CRC check")
    except (OSError, zipfile.BadZipFile) as error:
        raise InvalidError(f"Invalid AsaApi release archive: {error}") from error


def ensure_base_archive(state_dir: Path, url: str, expected_sha256: str) -> Path:
    archive_path = state_dir / f"AsaApi_{BASE_VERSION}.zip"
    if archive_path.is_file() and sha256_file(archive_path) == expected_sha256:
        validate_release_archive(archive_path)
        return archive_path
    if archive_path.exists():
        log("WARNING", "Removing an invalid cached AsaApi base archive")
        archive_path.unlink(missing_ok=True)

    part_path = state_dir / f".{archive_path.name}.{os.getpid()}.part"
    part_path.unlink(missing_ok=True)
    try:
        log("INFO", f"Downloading tested AsaApi {BASE_VERSION} release")
        download_file(url, part_path)
        actual_sha256 = sha256_file(part_path)
        if actual_sha256 != expected_sha256:
            raise InvalidError(
                f"AsaApi release checksum mismatch: expected {expected_sha256}, got {actual_sha256}"
            )
        validate_release_archive(part_path)
        os.replace(part_path, archive_path)
        fsync_directory(state_dir)
        return archive_path
    finally:
        part_path.unlink(missing_ok=True)


def copy_file_atomic(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        shutil.copy2(source, temporary)
        with temporary.open("rb") as handle:
            os.fsync(handle.fileno())
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def overlay_directory(source: Path, destination: Path, *, preserve_config: bool) -> None:
    for root, directories, files in os.walk(source):
        root_path = Path(root)
        relative_root = root_path.relative_to(source)
        for directory in list(directories):
            candidate = root_path / directory
            if candidate.is_symlink():
                raise InvalidError(f"Symlinks are not allowed in AsaApi sources: {candidate}")
        for filename in files:
            candidate = root_path / filename
            relative = relative_root / filename
            if candidate.is_symlink() or not candidate.is_file():
                raise InvalidError(f"Only regular files are allowed in AsaApi sources: {candidate}")
            if preserve_config and relative.as_posix() == "config.json" and (destination / relative).is_file():
                continue
            copy_file_atomic(candidate, destination / relative)


def extract_release_to_temp(archive_path: Path, state_dir: Path) -> Path:
    temporary = Path(tempfile.mkdtemp(prefix="asaapi-release-", dir=state_dir))
    try:
        with zipfile.ZipFile(archive_path) as archive:
            for member in archive.infolist():
                if member.is_dir():
                    continue
                target = temporary / PurePosixPath(member.filename)
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(member) as source, target.open("wb") as destination:
                    shutil.copyfileobj(source, destination, 1024 * 1024)
        return temporary
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def valid_custom_source(custom_dir: Path) -> str:
    for relative in REQUIRED_RELEASE_FILES:
        path = custom_dir / relative
        if not path.is_file() or not os.access(path, os.R_OK):
            raise InvalidError(f"Custom AsaApi override is missing or cannot read {relative}")
    return sha256_file(custom_dir / "ArkApi/AsaApi.dll")


def install_source(args: argparse.Namespace) -> int:
    bin_dir = args.bin_dir.resolve()
    state_dir = args.state_dir.resolve()
    custom_dir = bin_dir / "AsaApi_Custom"

    with manager_lock(state_dir):
        state = read_state(state_dir)
        if custom_dir.exists():
            if not custom_dir.is_dir():
                raise InvalidError(f"Custom AsaApi override path is not a directory: {custom_dir}")
            custom_hash = valid_custom_source(custom_dir)
            try:
                ensure_base_archive(state_dir, args.base_url, args.base_sha256)
            except (RetryableError, InvalidError) as error:
                log("WARNING", f"Unable to pre-cache the managed rollback release: {error}")
            destination_hash = ""
            destination_dll = bin_dir / "ArkApi/AsaApi.dll"
            if destination_dll.is_file():
                destination_hash = sha256_file(destination_dll)
            if state.get("source") != "custom" or state.get("core_sha256") != custom_hash \
                    or destination_hash != custom_hash:
                log("INFO", "Installing user-provided AsaApi_Custom override")
                overlay_directory(custom_dir, bin_dir, preserve_config=False)
            write_state(state_dir, {
                "source": "custom",
                "core_sha256": custom_hash,
                "installed_at": int(time.time()),
            })
            atomic_write(bin_dir / ".asaapi_version", b"CUSTOM\n")
            log("WARNING", "Using unsupported custom AsaApi override; managed cache preparation is disabled")
            return 0

        archive_path = ensure_base_archive(state_dir, args.base_url, args.base_sha256)
        state = read_state(state_dir)
        managed_dll = bin_dir / "ArkApi/AsaApi.dll"
        expected_core_hash = state.get("core_sha256") if state.get("source") == "managed" else ""
        installed_core_hash = sha256_file(managed_dll) if managed_dll.is_file() else ""
        reinstall = (
            state.get("source") != "managed"
            or state.get("version") != args.base_version
            or not expected_core_hash
            or installed_core_hash != expected_core_hash
            or not (bin_dir / "AsaApiLoader.exe").is_file()
        )

        if reinstall:
            extracted = extract_release_to_temp(archive_path, state_dir)
            try:
                extracted_hash = sha256_file(extracted / "ArkApi/AsaApi.dll")
                preserve_config = state.get("source") != "custom"
                if not preserve_config and (bin_dir / "config.json").is_file():
                    backup = state_dir / "config.custom-backup.json"
                    copy_file_atomic(bin_dir / "config.json", backup)
                log("INFO", f"Installing tested AsaApi {args.base_version} release")
                overlay_directory(extracted, bin_dir, preserve_config=preserve_config)
                expected_core_hash = extracted_hash
            finally:
                shutil.rmtree(extracted, ignore_errors=True)

        write_state(state_dir, {
            "source": "managed",
            "version": args.base_version,
            "archive_sha256": args.base_sha256,
            "core_sha256": expected_core_hash,
            "installed_at": int(time.time()),
        })
        atomic_write(bin_dir / ".asaapi_version", f"{args.base_version}\n".encode("utf-8"))
        log("INFO", f"Tested AsaApi {args.base_version} installation is ready")
        return 0


def validate_serialized_map(
    path: Path,
    value_size: int,
    required_keys: frozenset[str] = frozenset(),
) -> None:
    try:
        file_size = path.stat().st_size
    except OSError as error:
        raise InvalidError(f"Cache map is unavailable: {path}: {error}") from error
    if file_size <= 0:
        raise InvalidError(f"Cache map is empty: {path}")

    remaining = file_size
    entry_count = 0
    keys: set[bytes] = set()
    required_bytes = {key.encode("utf-8"): key for key in required_keys}
    found_required: set[bytes] = set()
    try:
        with path.open("rb") as handle:
            while remaining:
                if remaining < 8:
                    raise InvalidError(f"Truncated cache key length in {path}")
                key_size = struct.unpack("<Q", handle.read(8))[0]
                remaining -= 8
                if key_size == 0 or key_size > MAX_CACHE_KEY_SIZE or key_size > remaining:
                    raise InvalidError(f"Invalid cache key length in {path}")
                if remaining - key_size < value_size:
                    raise InvalidError(f"Truncated cache value in {path}")
                key = handle.read(key_size)
                if len(key) != key_size or key in keys:
                    raise InvalidError(f"Unreadable or duplicate cache key in {path}")
                keys.add(key)
                if key in required_bytes:
                    found_required.add(key)
                value = handle.read(value_size)
                if len(value) != value_size:
                    raise InvalidError(f"Truncated cache value in {path}")
                remaining -= key_size + value_size
                entry_count += 1
                if entry_count > MAX_CACHE_ENTRIES:
                    raise InvalidError(f"Cache entry limit exceeded in {path}")
    except OSError as error:
        raise InvalidError(f"Unable to read cache map {path}: {error}") from error
    if entry_count == 0:
        raise InvalidError(f"Cache map contains no entries: {path}")
    missing = [required_bytes[key] for key in required_bytes.keys() - found_required]
    if missing:
        raise InvalidError(
            "Cache map is missing required AsaApi offsets: " + ", ".join(sorted(missing))
        )


def safe_generation_relative(value: str) -> bool:
    path = PurePosixPath(value)
    if path.is_absolute() or len(path.parts) != 2 or path.parts[0] != "generations":
        return False
    pieces = path.parts[1].split("-")
    return (
        len(pieces) == 4
        and len(pieces[0]) == 64
        and all(character in "0123456789abcdef" for character in pieces[0].lower())
        and all(piece.isdecimal() and piece for piece in pieces[1:])
    )


def inspect_local_cache(cache_root: Path, executable_hash: str) -> tuple[dict, Path] | None:
    metadata_path = cache_root / "cached_key.cache"
    if not metadata_path.is_file():
        return None
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(metadata, dict) or metadata.get("version") != 1 \
            or str(metadata.get("executable_hash", "")).lower() != executable_hash:
        return None
    relative = metadata.get("cache_directory", "")
    if not isinstance(relative, str) or not safe_generation_relative(relative):
        return None
    generation = cache_root / PurePosixPath(relative)
    try:
        for filename, value_size in REQUIRED_CACHE_FILES.items():
            required_keys = REQUIRED_CORE_OFFSETS if filename == "cached_offsets.cache" else frozenset()
            validate_serialized_map(generation / filename, value_size, required_keys)
    except InvalidError:
        return None
    return metadata, generation


def validate_cache_archive(archive_path: Path) -> dict[str, zipfile.ZipInfo]:
    try:
        if archive_path.stat().st_size <= 0 or archive_path.stat().st_size > MAX_ARCHIVE_SIZE:
            raise InvalidError("Cache archive compressed size is outside the allowed range")
        with zipfile.ZipFile(archive_path) as archive:
            members = archive.infolist()
            if len(members) < 2 or len(members) > 4:
                raise InvalidError("Cache archive must contain between two and four files")
            seen: dict[str, zipfile.ZipInfo] = {}
            total_size = 0
            for member in members:
                name = member.filename
                if not safe_zip_name(name) or member.is_dir() or zip_member_is_symlink(member):
                    raise InvalidError(f"Unsafe cache archive entry: {name!r}")
                if name not in ALLOWED_CACHE_FILES:
                    raise InvalidError(f"Unexpected cache archive entry: {name}")
                if name in seen:
                    raise InvalidError(f"Duplicate cache archive entry: {name}")
                if member.file_size <= 0:
                    raise InvalidError(f"Cache archive entry is empty: {name}")
                if member.file_size > MAX_CACHE_ENTRY_SIZE:
                    raise InvalidError(f"Cache archive entry is too large: {name}")
                total_size += member.file_size
                if total_size > MAX_CACHE_TOTAL_SIZE:
                    raise InvalidError("Cache archive expanded size exceeds the limit")
                seen[name] = member
            for required in REQUIRED_CACHE_FILES:
                if required not in seen or seen[required].file_size <= 0:
                    raise InvalidError(f"Cache archive is missing {required}")
            return seen
    except (OSError, zipfile.BadZipFile) as error:
        raise InvalidError(f"Invalid cache archive: {error}") from error


def extract_and_validate_cache(archive_path: Path, cache_root: Path, executable_hash: str) -> Path:
    members = validate_cache_archive(archive_path)
    generations = cache_root / "generations"
    generations.mkdir(parents=True, exist_ok=True)
    generation_name = f"{executable_hash}-{os.getpid()}-{time.monotonic_ns()}-0"
    generation = generations / generation_name
    generation.mkdir()
    try:
        with zipfile.ZipFile(archive_path) as archive:
            for filename, value_size in REQUIRED_CACHE_FILES.items():
                target = generation / filename
                with archive.open(members[filename]) as source, target.open("wb") as destination:
                    shutil.copyfileobj(source, destination, 1024 * 1024)
                    destination.flush()
                    os.fsync(destination.fileno())
                required_keys = REQUIRED_CORE_OFFSETS if filename == "cached_offsets.cache" else frozenset()
                validate_serialized_map(target, value_size, required_keys)
            if "cached_offsets.txt" in members:
                target = generation / "cached_offsets.txt"
                with archive.open(members["cached_offsets.txt"]) as source, target.open("wb") as destination:
                    shutil.copyfileobj(source, destination, 1024 * 1024)
                    destination.flush()
                    os.fsync(destination.fileno())
        fsync_directory(generation)
        fsync_directory(generations)
        return generation
    except Exception:
        shutil.rmtree(generation, ignore_errors=True)
        raise


def disable_internal_downloader(config_path: Path, cache_url: str) -> None:
    config = read_json(config_path)
    settings = config.setdefault("settings", {})
    if not isinstance(settings, dict):
        raise InvalidError("AsaApi config settings must be an object")
    automatic = settings.setdefault("AutomaticCacheDownload", {})
    if not isinstance(automatic, dict):
        raise InvalidError("AsaApi AutomaticCacheDownload setting must be an object")
    automatic["Enable"] = False
    automatic.setdefault("DownloadCacheURL", cache_url)
    atomic_write_json(config_path, config)


def cache_download_url(config_path: Path, executable_hash: str) -> tuple[str, str]:
    config = read_json(config_path)
    settings = config.get("settings", {})
    automatic = settings.get("AutomaticCacheDownload", {}) if isinstance(settings, dict) else {}
    base_url = automatic.get("DownloadCacheURL", DEFAULT_CACHE_URL) if isinstance(automatic, dict) else DEFAULT_CACHE_URL
    if not isinstance(base_url, str) or not base_url.strip():
        base_url = DEFAULT_CACHE_URL
    base_url = base_url.strip()
    if not base_url.endswith("/"):
        base_url += "/"
    return base_url, f"{base_url}{executable_hash}.zip"


def inspect_incompatible_cache(cache_root: Path, executable_hash: str) -> dict | None:
    marker_path = cache_root / "incompatible_cache.json"
    try:
        marker = json.loads(marker_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(marker, dict) or marker.get("version") != 1:
        return None
    if str(marker.get("executable_hash", "")).lower() != executable_hash:
        return None
    if not isinstance(marker.get("last_modified"), str) or not isinstance(marker.get("error"), str):
        return None
    return marker


def prepare_cache(args: argparse.Namespace) -> int:
    bin_dir = args.bin_dir.resolve()
    state_dir = args.state_dir.resolve()
    server_exe = args.server_exe.resolve()

    with manager_lock(state_dir):
        state = read_state(state_dir)
        if state.get("source") == "custom":
            log("INFO", "Custom AsaApi source selected; leaving its cache behavior unchanged")
            return EXIT_CUSTOM
        if state.get("source") != "managed" or state.get("version") != BASE_VERSION:
            raise InvalidError("Managed AsaApi 2.01 source state is not ready")
        if not server_exe.is_file():
            raise InvalidError(f"ARK server executable is missing: {server_exe}")

        executable_hash = sha256_file(server_exe)
        cache_root = bin_dir / "ArkApi/Cache"
        cache_root.mkdir(parents=True, exist_ok=True)
        config_path = bin_dir / "config.json"
        base_url, download_url = cache_download_url(config_path, executable_hash)
        local_cache = inspect_local_cache(cache_root, executable_hash)
        incompatible_cache = inspect_incompatible_cache(cache_root, executable_hash)

        if local_cache is None and incompatible_cache is not None:
            remote_timestamp = remote_last_modified(download_url)
            if not remote_timestamp or remote_timestamp == incompatible_cache["last_modified"]:
                raise InvalidError(
                    f"AsaApi cache for ARK executable {executable_hash} remains unusable: "
                    f"{incompatible_cache['error']}"
                )

        if local_cache is not None:
            metadata, _ = local_cache
            remote_timestamp = remote_last_modified(download_url)
            if remote_timestamp is None:
                log("WARNING", "Unable to check for an updated AsaApi cache; using the verified local cache")
                disable_internal_downloader(config_path, base_url)
                return 0
            if metadata.get("last_modified", "") == remote_timestamp:
                log("INFO", f"Verified AsaApi cache is current for {executable_hash}")
                disable_internal_downloader(config_path, base_url)
                return 0
        else:
            remote_timestamp = None

        archive_path = cache_root / f".{executable_hash}.{os.getpid()}.zip.part"
        header_path = cache_root / f".{executable_hash}.{os.getpid()}.headers"
        archive_path.unlink(missing_ok=True)
        header_path.unlink(missing_ok=True)
        try:
            log("INFO", f"Downloading AsaApi cache for ARK executable {executable_hash}")
            try:
                download_file(download_url, archive_path, header_path)
            except (RetryableError, InvalidError):
                if local_cache is not None:
                    log("WARNING", "Cache refresh failed; continuing with the verified local cache")
                    disable_internal_downloader(config_path, base_url)
                    return 0
                raise

            downloaded_timestamp = ""
            if header_path.is_file():
                downloaded_timestamp = last_modified_from_headers(header_path.read_text(encoding="iso-8859-1"))
            if not downloaded_timestamp:
                downloaded_timestamp = remote_timestamp or ""

            try:
                generation = extract_and_validate_cache(archive_path, cache_root, executable_hash)
            except InvalidError as error:
                atomic_write_json(cache_root / "incompatible_cache.json", {
                    "version": 1,
                    "executable_hash": executable_hash,
                    "last_modified": downloaded_timestamp,
                    "error": str(error),
                })
                raise InvalidError(
                    f"AsaApi cache for ARK executable {executable_hash} is unusable: {error}"
                ) from error
            relative_generation = generation.relative_to(cache_root).as_posix()
            metadata = {
                "version": 1,
                "executable_hash": executable_hash,
                "last_modified": downloaded_timestamp,
                "cache_directory": relative_generation,
            }
            atomic_write_json(cache_root / "cached_key.cache", metadata)
            (cache_root / "incompatible_cache.json").unlink(missing_ok=True)
            disable_internal_downloader(config_path, base_url)
            log("INFO", f"Verified AsaApi cache installed for {executable_hash}")
            return 0
        finally:
            archive_path.unlink(missing_ok=True)
            header_path.unlink(missing_ok=True)


def show_status(args: argparse.Namespace) -> int:
    state = read_state(args.state_dir.resolve())
    print(json.dumps(state, sort_keys=True))
    return 0 if state else 1


def show_cache_timestamp(args: argparse.Namespace) -> int:
    """Print the remote cache timestamp for an executable hash."""
    executable_hash = args.executable_hash.lower()
    if len(executable_hash) != 64 or any(character not in "0123456789abcdef" for character in executable_hash):
        raise InvalidError("Executable hash must be a SHA-256 value")
    _base_url, download_url = cache_download_url(args.bin_dir.resolve() / "config.json", executable_hash)
    timestamp = remote_last_modified(download_url)
    if timestamp is None:
        raise RetryableError("Unable to read the remote AsaApi cache timestamp")
    print(timestamp)
    return 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    subparsers = root.add_subparsers(dest="command", required=True)

    install = subparsers.add_parser("install", help="select and install managed or custom AsaApi files")
    install.add_argument("--bin-dir", type=Path, required=True)
    install.add_argument("--state-dir", type=Path, required=True)
    install.add_argument("--base-version", default=BASE_VERSION)
    install.add_argument("--base-url", default=BASE_URL)
    install.add_argument("--base-sha256", default=BASE_SHA256)
    install.set_defaults(handler=install_source)

    cache = subparsers.add_parser("prepare-cache", help="prepare a cache without using Windows HTTPS")
    cache.add_argument("--bin-dir", type=Path, required=True)
    cache.add_argument("--state-dir", type=Path, required=True)
    cache.add_argument("--server-exe", type=Path, required=True)
    cache.set_defaults(handler=prepare_cache)

    status = subparsers.add_parser("status", help="print the selected AsaApi source state")
    status.add_argument("--state-dir", type=Path, required=True)
    status.set_defaults(handler=show_status)

    timestamp = subparsers.add_parser("cache-timestamp", help="print remote cache Last-Modified")
    timestamp.add_argument("--bin-dir", type=Path, required=True)
    timestamp.add_argument("--executable-hash", required=True)
    timestamp.set_defaults(handler=show_cache_timestamp)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        return args.handler(args)
    except RetryableError as error:
        log("ERROR", str(error))
        return EXIT_RETRY
    except InvalidError as error:
        log("ERROR", str(error))
        return EXIT_INVALID
    except Exception as error:
        log("ERROR", f"Unexpected AsaApi manager failure: {error}")
        return EXIT_INVALID


if __name__ == "__main__":
    sys.exit(main())
