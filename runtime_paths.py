# -*- coding: utf-8 -*-

import os
import shutil
import sys
from pathlib import Path

APP_NAME = "DouyinLiveRecorder"


def is_frozen() -> bool:
    return bool(getattr(sys, "frozen", False))


def is_packaged_macos() -> bool:
    return sys.platform == "darwin" and is_frozen()


def get_executable_dir() -> Path:
    return Path(os.path.realpath(sys.argv[0])).parent


def get_bundle_resources_dir() -> Path | None:
    if not is_packaged_macos():
        return None

    executable = Path(sys.executable).resolve()
    for path in [executable.parent, *executable.parents]:
        if path.name == "Resources":
            return path
        if path.name == "Contents":
            return path / "Resources"
        if path.name == "MacOS":
            return path.parent / "Resources"
    return None


def get_resource_dir() -> Path:
    pyinstaller_dir = getattr(sys, "_MEIPASS", None)
    if pyinstaller_dir:
        return Path(pyinstaller_dir)
    return Path(__file__).resolve().parent


def get_resource_path(*parts: str) -> Path:
    return get_resource_dir().joinpath(*parts)


def get_app_data_dir() -> Path:
    override = os.environ.get("DLYR_APP_DATA_DIR")
    if override:
        return Path(override).expanduser()

    if is_packaged_macos():
        return Path.home() / "Library" / "Application Support" / APP_NAME

    return get_executable_dir()


def ensure_user_data_files() -> Path:
    data_dir = get_app_data_dir()
    data_dir.mkdir(parents=True, exist_ok=True)

    for dirname in ("backup_config", "downloads", "logs"):
        (data_dir / dirname).mkdir(parents=True, exist_ok=True)

    source_config_dir = get_resource_path("config")
    target_config_dir = data_dir / "config"
    if source_config_dir.exists():
        if not target_config_dir.exists():
            shutil.copytree(source_config_dir, target_config_dir)
        else:
            for source_file in source_config_dir.iterdir():
                target_file = target_config_dir / source_file.name
                if source_file.is_file() and not target_file.exists():
                    shutil.copy2(source_file, target_file)
    else:
        target_config_dir.mkdir(parents=True, exist_ok=True)

    return data_dir


def _candidate_runtime_paths() -> list[Path]:
    paths: list[Path] = []
    bundle_resources = get_bundle_resources_dir()
    if bundle_resources:
        paths.extend([
            bundle_resources / "runtime" / "node" / "bin",
            bundle_resources / "runtime" / "ffmpeg",
        ])

    executable_dir = get_executable_dir()
    paths.extend([
        executable_dir / "node",
        executable_dir / "node" / "bin",
        executable_dir / "ffmpeg",
    ])
    return paths


def configure_bundled_runtime() -> None:
    current_path = os.environ.get("PATH", "")
    entries = [str(path) for path in _candidate_runtime_paths() if path.exists()]
    if not entries:
        return

    existing = current_path.split(os.pathsep) if current_path else []
    deduped = []
    for entry in [*entries, *existing]:
        if entry and entry not in deduped:
            deduped.append(entry)
    os.environ["PATH"] = os.pathsep.join(deduped)
    os.environ.setdefault("EXECJS_RUNTIME", "Node")


def get_bundled_ffmpeg_dir() -> Path | None:
    bundle_resources = get_bundle_resources_dir()
    if not bundle_resources:
        return None
    ffmpeg_dir = bundle_resources / "runtime" / "ffmpeg"
    return ffmpeg_dir if ffmpeg_dir.exists() else None
