"""Install the matching Godot Gradle template without replacing an existing one."""
from pathlib import Path
from zipfile import ZipFile
import shutil
from toolchain import load, android_template
CONFIG = load()

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = android_template(CONFIG)
destination = ROOT / "godot/android/build"
if not (destination / "build.gradle").exists():
    destination.mkdir(parents=True, exist_ok=True)
    with ZipFile(TEMPLATE) as archive:
        for info in archive.infolist():
            target = (destination / info.filename).resolve()
            if not target.is_relative_to(destination.resolve()):
                raise ValueError("Template path escapes build directory")
        archive.extractall(destination)
    # Use installed, verified tools. The app contains prebuilt native libraries;
    # Gradle does not compile Godot or change the NDK used to compile our engine.
    config = destination / "config.gradle"
    contents = config.read_text(encoding="utf-8")
    contents = contents.replace("'36.1.0'", "'36.0.0'").replace("'29.0.14206865'", "'28.1.13356709'")
    config.write_text(contents, encoding="utf-8")
    # Android 10+ requires executable files to live in a read-only installed
    # directory. Extract the packaged PIE engine to nativeLibraryDir.
    build = destination / "build.gradle"
    contents = build.read_text(encoding="utf-8").replace("useLegacyPackaging shouldUseLegacyPackaging()", "useLegacyPackaging true")
    build.write_text(contents, encoding="utf-8")
(destination.parent / ".gdignore").write_text("", encoding="utf-8")
(destination.parent / ".build_version").write_text("4.7.2.stable", encoding="utf-8")
(destination / "local.properties").write_text("sdk.dir=" + Path(CONFIG["sdk"]).as_posix() + "\n", encoding="utf-8")
properties = destination / "gradle.properties"
settings = properties.read_text(encoding="utf-8")
if "org.gradle.daemon=false" not in settings:
    settings += "\norg.gradle.daemon=false\n"
# Compressing the NNUE and imported textures concurrently can exhaust Gradle's
# heap on machines with many cores. Bound workers instead of increasing memory.
if "org.gradle.workers.max=" not in settings:
    settings += "org.gradle.workers.max=2\n"
properties.write_text(settings, encoding="utf-8")
model = ROOT / "godot/assets/engine/nn.bin"
model.parent.mkdir(parents=True, exist_ok=True)
if not model.exists():
    shutil.copy2(ROOT / "engines/yaneuraou/eval/nn.bin", model)
print("Android Gradle template and bundled NNUE model prepared")
import runpy
runpy.run_path(str(ROOT / "scripts/configure_android_appearance.py"), run_name="__main__")

# Official live.shogi.or.jp currently serves its public KIF files over HTTP.
# Scope the exception to this host; other cleartext endpoints stay disabled.
network = destination / "res/xml/shogi_network_security.xml"
network.parent.mkdir(parents=True, exist_ok=True)
network.write_text("""<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
  <base-config cleartextTrafficPermitted="false" />
  <domain-config cleartextTrafficPermitted="true">
    <domain includeSubdomains="false">live.shogi.or.jp</domain>
  </domain-config>
</network-security-config>
""", encoding="utf-8")
manifest = destination / "src/main/AndroidManifest.xml"
text = manifest.read_text(encoding="utf-8")
if "android:networkSecurityConfig=" not in text:
    text = text.replace("<application", '<application android:networkSecurityConfig="@xml/shogi_network_security"', 1)
manifest.write_text(text, encoding="utf-8")
