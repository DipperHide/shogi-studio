"""Cross-compile the official YaneuraOu V9.00 source with the Android NDK.

The PIE executable is named .so for installation into Android's read-only
nativeLibraryDir, from which modern Android permits executing packaged code.
"""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "engines" / "yaneuraou" / "vendor" / "source"
OUTPUT = ROOT / "engines" / "yaneuraou" / "android"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ndk", type=Path, default=Path("C:/Users/jinda/Development/AndroidSDK/ndk/28.1.13356709"))
    args = parser.parse_args()
    toolchain = args.ndk / "toolchains/llvm/prebuilt/windows-x86_64"
    compiler = toolchain / "bin/clang++.exe"
    OUTPUT.mkdir(parents=True, exist_ok=True)
    makefile = (SOURCE / "Makefile").read_text(encoding="utf-8-sig")
    common = makefile.split("SOURCES  = \\", 1)[1].split("CUDA_SOURCES", 1)[0]
    sources = re.findall(r"[\w/]+\.cpp", common)
    sources += ["book/makebook.cpp", "book/makebook2015.cpp", "book/makebook2025.cpp", "learn/learner.cpp", "learn/learning_tools.cpp", "learn/multi_think.cpp"]
    sources += ["eval/nnue/evaluate_nnue.cpp", "eval/nnue/evaluate_nnue_learner.cpp", "eval/nnue/nnue_test_command.cpp"]
    sources += [str(p.relative_to(SOURCE)).replace("\\", "/") for p in (SOURCE / "eval/nnue/features").glob("*.cpp")]
    sources += ["engine/yaneuraou-engine/yaneuraou-search.cpp"]
    flags = ["--target=aarch64-linux-android24", "--sysroot=" + str(toolchain / "sysroot"), "-std=c++17", "-O3", "-fno-exceptions", "-fno-rtti", "-fPIE", "-DNDEBUG", "-DNO_EXCEPTIONS", "-DYANEURAOU_ENGINE_NNUE", "-DIS_64BIT", "-DUSE_NEON", '-DTARGET_CPU="ARM64"', "-march=armv8-a", "-Wno-unused-parameter", "-I", str(SOURCE)]
    objects = []
    def compile_one(name: str) -> Path:
        source = SOURCE / name
        target = OUTPUT / (name.replace("/", "_") + ".o")
        if not target.exists() or target.stat().st_mtime < source.stat().st_mtime:
            result = subprocess.run([str(compiler), *flags, "-c", str(source), "-o", str(target)], capture_output=True, text=True, encoding="utf-8", errors="replace")
            if result.returncode:
                raise RuntimeError(name + "\n" + result.stdout + result.stderr)
        print("compiled " + name, flush=True)
        return target
    with ThreadPoolExecutor(max_workers=4) as pool:
        objects = list(pool.map(compile_one, sources))
    binary = OUTPUT / "libyaneuraou.so"
    subprocess.run([str(compiler), *flags[:2], "-pie", "-static-libstdc++", "-Wl,-z,max-page-size=16384", "-Wl,-z,common-page-size=16384", *map(str, objects), "-o", str(binary)], check=True)
    report = {"source_release": "V9.00", "architecture": "aarch64", "android_api": 24, "sha256": hashlib.sha256(binary.read_bytes()).hexdigest(), "bytes": binary.stat().st_size, "device_tested": False}
    (OUTPUT / "build.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report), flush=True)


if __name__ == "__main__":
    main()
