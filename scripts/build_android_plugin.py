"""Build the resource-free Godot v2 AAR using the installed Java/Android SDKs."""
from pathlib import Path
import hashlib
import json
import subprocess
from zipfile import ZipFile, ZIP_DEFLATED
from io import BytesIO
from toolchain import load, android_template
CONFIG = load()

ROOT = Path(__file__).resolve().parents[1]
JAVA = Path(CONFIG["jdk"]) / "bin"
SDK = Path(CONFIG["sdk"])
BUILD = ROOT / "android-plugin/build"
BUILD.mkdir(parents=True, exist_ok=True)
CLASSES = BUILD / "classes"
CLASSES.mkdir(exist_ok=True)
godot_jar = ROOT / "engines/android-sdk/godot-classes.jar"
if not godot_jar.exists():
    template = android_template(CONFIG)
    with ZipFile(template) as package:
        candidates = [name for name in package.namelist() if name.endswith(".aar") and "debug" in name]
        if len(candidates) != 1:
            raise RuntimeError("Matching Godot debug library was not uniquely found")
        with ZipFile(BytesIO(package.read(candidates[0]))) as aar:
            godot_jar.parent.mkdir(parents=True, exist_ok=True)
            godot_jar.write_bytes(aar.read("classes.jar"))
classpath = str(godot_jar) + ";" + str(SDK / "platforms/android-36/android.jar")
sources = sorted((ROOT / "android-plugin/src").rglob("*.java"))
subprocess.run([str(JAVA / "javac.exe"), "-encoding", "UTF-8", "-source", "17", "-target", "17", "-classpath", classpath, "-d", str(CLASSES), *map(str, sources)], check=True)
jar = BUILD / "classes.jar"
with ZipFile(jar, "w", ZIP_DEFLATED) as archive:
    for path in CLASSES.rglob("*.class"):
        archive.write(path, path.relative_to(CLASSES).as_posix())
output = ROOT / "godot/addons/shogi_platform/ShogiPlatform.aar"
with ZipFile(output, "w", ZIP_DEFLATED) as archive:
    archive.write(jar, "classes.jar")
    archive.write(ROOT / "android-plugin/AndroidManifest.xml", "AndroidManifest.xml")
    archive.write(ROOT / "engines/yaneuraou/android/libyaneuraou.so", "jni/arm64-v8a/libyaneuraou.so")
    archive.writestr("R.txt", "")
report = {"aar": str(output), "sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "bytes": output.stat().st_size, "device_tested": False}
(BUILD / "build.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report))
