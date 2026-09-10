"""Package the corresponding engine source and build instructions with the app."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
engine = ROOT / "engines/yaneuraou"
destination = ROOT / "godot/assets/licenses"
destination.mkdir(parents=True, exist_ok=True)
output = destination / "yaneuraou-source.zip"
# A clean source checkout carries the compact corresponding-source archive.
# Restore only its engine tree; never trust archive paths outside the project.
if not (engine / "vendor/source/usi.cpp").is_file():
    with ZipFile(output) as packaged:
        for item in packaged.infolist():
            if not item.filename.startswith("engines/yaneuraou/vendor/source/"):
                continue
            target = (ROOT / item.filename).resolve()
            if not target.is_relative_to((engine / "vendor/source").resolve()):
                raise ValueError("Engine archive path escapes source directory")
            if not item.is_dir():
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(packaged.read(item))
sources = list((engine / "vendor/source").rglob("*"))
with ZipFile(output, "w", ZIP_DEFLATED) as archive:
    for path in sorted(sources):
        if path.is_file():
            archive.write(path, "engines/yaneuraou/vendor/source/" + path.relative_to(engine / "vendor/source").as_posix())
    for name in ["NOTICE.md", "LICENSE.txt", "EngineHost.cs"]:
        archive.write(engine/name, "engines/yaneuraou/"+name)
    for name in ["build_engine_android.py", "build_engine_host.ps1", "build_android_plugin.py", "toolchain.py"]:
        archive.write(ROOT/"scripts"/name, "scripts/"+name)
    # Keep the generated entry reproducible across the Android and Windows builds.
    readme_entry = ZipInfo("README.md", date_time=(1980, 1, 1, 0, 0, 0))
    readme_entry.compress_type = ZIP_DEFLATED
    archive.writestr(readme_entry, """# Corresponding YaneuraOu V9.00 source

All upstream source files from the official V9.00 release are included unchanged.

Android: Install Python 3.11+ and the Android NDK 28.1.13356709, then run:

    python scripts/build_engine_android.py --ndk C:/path/to/android-ndk

This compiles an Android API 24 arm64 PIE executable, halfKP256 NNUE, using
the compiler flags recorded in the script. No evaluation data is needed to
compile. `nn.bin` is supplied separately for running the engine.

Windows process host: from Windows PowerShell with .NET Framework installed:

    ./scripts/build_engine_host.ps1

Windows engine: use the included upstream Makefile, NNUE halfKP256 edition,
SSE42 target and tournament build. Upstream toolchain/build instructions:
https://github.com/yaneurao/YaneuraOu/wiki/やねうら王のビルド手順

The Android Godot platform bridge is a separate app component, not a change
to the YaneuraOu source. Its full source is in the game's android-plugin folder.
""")
manifest = {"engine": {"release": "V9.00", "license": "GPL-3.0-or-later", "official_release_archive_sha256": "6517997dd05ba049a2244a828216967a0ad351d975ec52a0f358e2883197dec6"}, "model": {"name": "Suisho5", "author": "Tayayan", "url": "https://github.com/yaneurao/YaneuraOu/releases/tag/suisho5", "sha256": hashlib.sha256((engine/"eval/nn.bin").read_bytes()).hexdigest(), "license_file_in_upstream_archive": False}, "source_package_sha256": hashlib.sha256(output.read_bytes()).hexdigest()}
(destination/"engine-provenance.json").write_text(json.dumps(manifest,indent=2),encoding="utf-8")
(destination/"yaneuraou-NOTICE.md").write_text((engine/"NOTICE.md").read_text(encoding="utf-8"),encoding="utf-8")
print(f"Engine corresponding source packaged: {output.stat().st_size} bytes")
