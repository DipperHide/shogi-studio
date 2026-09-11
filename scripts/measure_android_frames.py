"""Sample Godot SurfaceView presentation times, optionally while tapping one control.

Use the same device, build, initial position and duration for comparisons. The
ADB polling itself has overhead; these are presentation gaps, not CPU timings.
"""
import argparse
import json
from pathlib import Path
import shlex
import statistics
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--serial')
    parser.add_argument('--seconds', type=float, default=10)
    parser.add_argument('--tap', nargs=2, type=int)
    parser.add_argument('--package', default='org.shogistudio.artpreview')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    adb = [args.adb] + (['-s', args.serial] if args.serial else [])

    def run(*command):
        return subprocess.run(adb + list(command), capture_output=True, check=True, timeout=15).stdout

    layers = run('shell', 'dumpsys SurfaceFlinger --list').decode().splitlines()
    layer = next(value for value in layers if value.startswith('SurfaceView[' + args.package) and '(BLAST)' in value)

    def sample():
        raw = run('shell', 'dumpsys SurfaceFlinger --latency ' + shlex.quote(layer)).decode().splitlines()
        values = []
        for line in raw[1:]:
            parts = line.split()
            if len(parts) == 3 and all(part.isdigit() for part in parts):
                row = [int(part) for part in parts]
                if 0 < row[1] < 2**63 - 1:
                    values.append(row)
        return values

    initial = sample()
    cutoff = max(row[1] for row in initial)
    rows = {}
    start = time.monotonic()
    if args.tap:
        run('shell', 'input', 'tap', *map(str, args.tap))
    while time.monotonic() - start < args.seconds:
        for row in sample():
            if row[1] > cutoff:
                rows[row[1]] = row
        time.sleep(.25)
    ordered = [rows[key] for key in sorted(rows)]
    gaps = [(right[1] - left[1]) / 1e6 for left, right in zip(ordered, ordered[1:])]
    if not gaps:
        raise RuntimeError('No new presentation timestamps; keep the application visible.')
    ordered_gaps = sorted(gaps)
    result = {'samples': len(ordered), 'requested_seconds': args.seconds,
              'elapsed_seconds': time.monotonic() - start, 'tap': args.tap,
              'observed_span_seconds': (ordered[-1][1] - ordered[0][1]) / 1e9,
              'first_gap_from_baseline_ms': (ordered[0][1] - cutoff) / 1e6,
              'median_ms': statistics.median(gaps), 'p95_ms': ordered_gaps[int(.95 * (len(gaps)-1))],
              'p99_ms': ordered_gaps[int(.99 * (len(gaps)-1))], 'max_ms': max(gaps),
              'over_25_ms': sum(value > 25 for value in gaps), 'over_50_ms': sum(value > 50 for value in gaps),
              'rows': ordered}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    args.output.with_suffix('.png').write_bytes(run('exec-out', 'screencap', '-p'))
    print(json.dumps({key: value for key, value in result.items() if key != 'rows'}, indent=2))


if __name__ == '__main__':
    main()
