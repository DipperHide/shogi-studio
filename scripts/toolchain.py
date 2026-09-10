"""Shared local toolchain configuration; machine paths are never committed."""
import json
import os
from pathlib import Path


def load():
    path = Path(os.environ.get("SHOGI_TOOLCHAIN", Path.home() / "Development/toolchain.json"))
    return json.loads(path.read_text(encoding="utf-8-sig"))


def android_template(config):
    version = config.get("godotVersion", "4.7.2") + ".stable"
    candidates = [Path(config["godot"]).parent / "editor_data/export_templates" / version / "android_source.zip",
                  Path(os.environ.get("APPDATA", Path.home() / ".local/share")) / "Godot/export_templates" / version / "android_source.zip"]
    for path in candidates:
        if path.is_file():
            return path
    raise FileNotFoundError("Install matching Godot Android export templates: " + version)
