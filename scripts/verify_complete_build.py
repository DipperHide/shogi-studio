"""Verify the final APK contents, signing, native alignment and exact course data."""
from collections import Counter
from datetime import datetime, timezone
from io import BytesIO
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
import argparse
parser = argparse.ArgumentParser()
parser.add_argument('--report-directory', default='review/app/complete/build')
parser.add_argument('--windows-probe', default='review/app/complete/build/windows-package-probe.json')
parser.add_argument('--windows-executable', default='builds/windows/Shogi.exe')
arguments = parser.parse_args()
OUT = ROOT / arguments.report_directory
OUT.mkdir(parents=True, exist_ok=True)
toolchain = json.loads((Path.home() / "Development/toolchain.json").read_text(encoding="utf-8-sig"))
build_tools = Path(toolchain["sdk"]) / "build-tools/36.0.0"
environment = dict(os.environ, JAVA_HOME=toolchain["jdk"])
apk = ROOT / "builds/shogi-playable.apk"
failures = []
checks = []

def verify(value, label):
    checks.append(label)
    if not value:
        failures.append(label)

def command(label, args):
    completed = subprocess.run([str(arg) for arg in args], cwd=ROOT, env=environment,
                               capture_output=True, text=True, encoding="utf-8", errors="replace")
    (OUT / f"{label}.log").write_text(completed.stdout + completed.stderr, encoding="utf-8")
    verify(completed.returncode == 0, label)
    return completed.stdout

signature = command("apk-signature", [Path(toolchain["jdk"]) / "bin/java.exe", "-jar",
                    build_tools / "lib/apksigner.jar", "verify", "--verbose", "--print-certs", apk])
verify("v2 scheme (APK Signature Scheme v2): true" in signature, "APK v2 signature present")
previous_signature = (ROOT / "review/app/unified/android-signature.txt").read_text(encoding="utf-8-sig")
digest_pattern = r"certificate SHA-256 digest: ([a-f0-9]{64})"
current_signer = re.search(digest_pattern, signature)
previous_signer = re.search(digest_pattern, previous_signature)
verify(current_signer and previous_signer and current_signer[1] == previous_signer[1], "APK signer matches the existing unified app")
command("apk-alignment", [build_tools / "zipalign.exe", "-c", "-P", "16", "-v", "4", apk])
badging = command("apk-badging", [build_tools / "aapt2.exe", "dump", "badging", apk])
manifest_text = command("apk-manifest", [build_tools / "aapt2.exe", "dump", "xmltree", apk, "--file", "AndroidManifest.xml"])
presets = (ROOT / "godot/export_presets.cfg").read_text(encoding="utf-8")
version_code = int(re.search(r"version/code=(\d+)", presets)[1])
version_name = re.search(r'version/name="([^"]+)"', presets)[1]
verify("name='org.shogistudio.artpreview'" in badging, "existing main Android package retained")
verify(f"versionCode='{version_code}'" in badging and f"versionName='{version_name}'" in badging,
       "APK matches current project version")
for permission in ["INTERNET", "BLUETOOTH_SCAN", "BLUETOOTH_CONNECT", "BLUETOOTH_ADVERTISE"]:
    verify(f"android.permission.{permission}" in manifest_text, f"required permission {permission}")
for permission in ["READ_PHONE_STATE", "WRITE_EXTERNAL_STORAGE", "READ_EXTERNAL_STORAGE", "MANAGE_EXTERNAL_STORAGE"]:
    verify(f"android.permission.{permission}" not in manifest_text, f"unneeded permission absent: {permission}")
verify(bool(re.search(r'android:extractNativeLibs[^\n]*(?:0xffffffff|true)', manifest_text)), "native library extraction configured")

verify(not re.search(r'android:debuggable[^\n]*(?:0xffffffff|true)', manifest_text), "release APK is not debuggable")
verify("android:networkSecurityConfig" in manifest_text, "scoped official KIF network policy packaged")
native = []
stripped_engine = OUT / "expected-libyaneuraou.so"
strip_tool = Path(toolchain["sdk"]) / "ndk/28.1.13356709/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe"
command("engine-strip", [strip_tool, "--strip-unneeded", "-o", stripped_engine,
                        ROOT / "engines/yaneuraou/android/libyaneuraou.so"])
with ZipFile(apk) as archive:
    verify(not any("membership" in name.lower() for name in archive.namelist()), "no paid-membership resources or scripts packaged")
    verify(not any("course_sources" in name or name.endswith(".epub") for name in archive.namelist()), "private source books are not bundled")
    dex = b"".join(archive.read(name) for name in archive.namelist() if name.endswith(".dex"))
    verify(b"closeOwnedSocket" in dex and b"ShogiPlatform" in dex, "updated Bluetooth socket cleanup plugin is packaged")
    verify(b"pickAnalysisRecord" in dex and b"analysis_record_imported" in dex,
           "request-scoped analysis file picker bridge is packaged")
    verify(b"AnalysisRecordText" in dex and b"windows-31j" in dex,
           "bounded UTF-8 and CP932 analysis decoder is packaged")
    verify(b"isBoardFrameReady" not in dex and b"boardReady" not in dex,
           "APK contains no obsolete board-frame splash handshake")
    # Android Gradle removes unneeded debug/symbol tables while packaging JNI.
    # Reproduce that exact transformation; compare every resulting byte.
    verify(archive.read("lib/arm64-v8a/libyaneuraou.so") == stripped_engine.read_bytes(), "packaged native engine exactly matches the compiled engine after Gradle symbol stripping")
    for name in archive.namelist():
        if not name.endswith(".so"):
            continue
        data = archive.read(name)
        is_elf = data[:6] == b"\x7fELF\x02\x01" and struct.unpack_from("<H", data, 18)[0] == 183
        verify(is_elf, f"ARM64 ELF: {name}")
        if not is_elf:
            continue
        phoff = struct.unpack_from("<Q", data, 32)[0]
        size, count = struct.unpack_from("<HH", data, 54)
        headers = [struct.unpack_from("<IIQQQQQQ", data, phoff + i * size) for i in range(count)]
        aligns = [header[7] for header in headers if header[0] == 1]
        verify(aligns and all(value >= 16384 for value in aligns), f"16 KB ELF page alignment: {name}")
        if name.endswith("libyaneuraou.so"):
            verify(struct.unpack_from("<H", data, 16)[0] == 3 and struct.unpack_from("<Q", data, 24)[0] > 0
                   and any(header[0] == 3 for header in headers), "YaneuraOu is an executable PIE with an interpreter")
        native.append({"file": name, "sha256": hashlib.sha256(data).hexdigest(), "load_segment_alignment": aligns})
    for filename in ["assets/engine/nn.bin", "assets/licenses/yaneuraou-source.zip",
                     "assets/licenses/engine-provenance.json", "assets/locales/tutorial.json",
                     "assets/data/historic-games.json", "assets/data/tournament-index.json",
                     "assets/data/cp932.txt", "config/tournaments.json", "assets/reference-ui/provenance.json",
                     "assets/reference-ui/NOTICE.md"]:
        packed = archive.read("assets/" + filename)
        local = (ROOT / "godot" / filename).read_bytes()
        verify(packed == local, "packaged resource matches source: " + filename)
    with ZipFile(BytesIO(archive.read("assets/assets/licenses/yaneuraou-source.zip"))) as source:
        verify("engines/yaneuraou/LICENSE.txt" in source.namelist()
               and "scripts/build_engine_android.py" in source.namelist()
               and any(name.endswith("source/usi.cpp") for name in source.namelist()), "corresponding engine source and build recipe included")
    course_manifest = json.loads(archive.read("assets/courses/manifest.json"))
    for book in course_manifest["books"]:
        verify(book.get("complete") is True, "every source page reviewed and incorporated: " + book["id"])
        data = archive.read("assets/courses/" + book["file"])
        verify(hashlib.sha256(data).hexdigest() == book["sha256"], "course matches packaged manifest: " + book["id"])
        verify(data == (ROOT / "godot/courses" / book["file"]).read_bytes(), "course matches final authored file: " + book["id"])
        authored = json.loads(data)
        verify(dict(Counter(page["status"] for page in authored["coverage"])) == book["coverage"], "course coverage is reported accurately: " + book["id"])

probe_path = ROOT / arguments.windows_probe
course_test = json.loads((ROOT / "review/app/tutorial/tests.json").read_text(encoding="utf-8-sig"))
course_locale = json.loads((ROOT / "review/app/complete/tutorial-localization-tests.json").read_text(encoding="utf-8-sig"))
verify(course_locale.get("failures") == [], "course and tutorial navigation glyphs are available in all interface languages")
verify(course_test.get("failures") == [] and course_test.get("source_errors") == [], "all course content and interactions pass Godot tests")
verify(course_test.get("source_steps") == sum(book["steps"] for book in course_manifest["books"])
       and course_test.get("source_simulated") == sum(book["interactive_steps"] for book in course_manifest["books"]),
       "every packaged lesson step was tested")
for book in course_manifest["books"]:
    verify(course_test.get("source_hashes", {}).get(book["id"]) == book["sha256"], "tested course revision matches final package: " + book["id"])
probe = json.loads(probe_path.read_text(encoding="utf-8-sig")) if probe_path.exists() else {}
verify(probe.get("platform") == "Windows" and probe.get("failures") == [], "final Windows executable probe passed")
verify(probe.get("courses") == course_manifest["books"], "Windows and Android contain the same course revision")
verify(probe.get("executable_sha256") == hashlib.sha256((ROOT / arguments.windows_executable).read_bytes()).hexdigest(), "Windows probe belongs to this exact executable")
artifacts = [{"file": str(path.relative_to(ROOT)), "bytes": path.stat().st_size,
              "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
             for path in [apk, ROOT / arguments.windows_executable]]
report = {"checked_utc": datetime.now(timezone.utc).isoformat(), "version": version_name,
          "checks": len(checks), "failures": failures, "artifacts": artifacts, "native": native,
          "courses": course_manifest["books"], "android_device_tested": False, "bluetooth_pair_tested": False}
(OUT / "verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"checks": len(checks), "failures": failures}, ensure_ascii=True))
raise SystemExit(bool(failures))
