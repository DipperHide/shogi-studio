"""Read a debug legacy app's save through authorized ADB; never alter device data."""
import argparse
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial', help='ADB device serial (required if several devices are attached)')
parser.add_argument('--output', type=Path, default=Path('builds/legacy-android-record.json'))
args = parser.parse_args()
toolchain = json.loads((Path.home()/'Development/toolchain.json').read_text('utf-8-sig'))
adb = [str(Path(toolchain['sdk'])/'platform-tools/adb.exe')]
if args.serial: adb += ['-s', args.serial]
result = subprocess.run(adb + ['exec-out', 'run-as', 'org.shogistudio.classic', 'cat', 'files/current-game.json'], capture_output=True)
if result.returncode:
    raise SystemExit('Cannot read the old debug app. Connect and authorize the device, keep the old app installed, and check --serial.\n'+result.stderr.decode('utf-8', errors='replace'))
try:
    data = json.loads(result.stdout)
    assert data.get('version') == 1 and isinstance(data.get('moves'), list)
except (ValueError, AssertionError, AttributeError):
    raise SystemExit('The old app did not return a supported JSON record. No file was written.')
args.output.parent.mkdir(parents=True, exist_ok=True)
if args.output.exists(): raise SystemExit('Output already exists; choose another --output path to preserve it.')
args.output.write_bytes(result.stdout)
print(f'Exported {args.output}. Import this JSON in the unified app to validate every move. The original device save was not changed.')
