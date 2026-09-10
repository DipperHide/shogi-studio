"""Compare marker geometry with the original DEX branch, not decompiled Java.

Executes only 00ff..0195 arithmetic/branches from CustomLineChart.onDraw.
No Android code, network, reflection, or arbitrary DEX methods are executed.
"""
from pathlib import Path
import hashlib
import json
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis22'
source = ROOT / '.work/chessis-reference/dex-evidence/com-chessimprovement-chessis-common-abstractclasses-CustomLineChart-onDraw.txt'
instructions = {}
for line in source.read_text('utf-8').splitlines()[2:]:
    match = re.match(r'(\w+) +(\S+) +(.*)', line)
    if match: instructions[int(match[1], 16)] = (match[2], match[3])
addresses = list(instructions)
following = dict(zip(addresses, addresses[1:]))


def float32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def execute(entry, plot, previous, levels):
    side = entry['side']
    x, y = entry['point']
    _, top, _, height = plot
    v = [0] * 28
    initial = {1: top + height - 6, 2: x, 3: previous[1], 5: levels[-1], 6: levels[1],
               7: previous[-1], 9: y, 11: int(side == 1), 14: 6.0, 15: top + 6,
               16: top + 9, 17: top + height - 9, 18: 14.0, 20: 0.0}
    for index, value in initial.items(): v[index] = value
    pc, returned, connector = 0xff, None, False
    for _ in range(120):
        if pc in [0x178, 0x195]:
            connector = pc == 0x178
            break
        operation, output = instructions[pc]
        registers = [int(value) for value in re.findall(r'\bv(\d+)\b', output.split(', L')[0])]
        target = following[pc]
        a = registers[0] if registers else 0
        if operation == 'const/high16': v[a] = struct.unpack('<f', struct.pack('<I', int(output.split(', ')[1]) & 0xffffffff))[0]
        elif operation.startswith('const'): v[a] = int(output.split(', ')[1])
        elif operation.startswith('move-result'): v[a] = returned
        elif operation.startswith('move'): v[a] = v[registers[1]]
        elif operation == 'int-to-float': v[a] = float32(v[registers[1]])
        elif operation.startswith(('cmpl-', 'cmpg-')):
            left, right = v[registers[1]], v[registers[2]]
            v[a] = (left > right) - (left < right)
        elif operation.startswith('if-'):
            condition = operation[3:]
            left, right = v[a], 0 if condition.endswith('z') else v[registers[1]]
            result = {'eq': left == right, 'ne': left != right, 'ge': left >= right,
                      'gt': left > right, 'le': left <= right, 'lt': left < right}[condition.rstrip('z')]
            if result: target = pc + int(output.split(', ')[-1][:-1], 16)
        elif operation.startswith('goto'): target = pc + int(output[:-1], 16)
        elif operation.startswith(('add-', 'sub-', 'mul-')):
            left = v[a] if '/2addr' in operation else v[registers[1]]
            right = int(output.split(', ')[-1]) if '/lit8' in operation else v[registers[-1]]
            v[a] = {'add': lambda: left + right, 'sub': lambda: left - right, 'mul': lambda: left * right}[operation.split('-')[0]]()
            if '-float' in operation: v[a] = float32(v[a])
        elif operation == 'invoke-static' and 'Ljava/lang/Math;' in output:
            values = [v[index] for index in registers]
            if '->min(' in output: returned = min(values)
            elif '->max(' in output: returned = max(values)
            elif '->abs(' in output: returned = abs(values[0])
            else: raise AssertionError(output)
        else: raise AssertionError((hex(pc), operation, output))
        pc = target
    else: raise AssertionError('DEX step limit')
    levels[-1], levels[1] = v[23], v[24]
    previous[-1], previous[1] = v[7], v[13]
    return {'center': [x, v[25]], 'level': levels[side], 'connector': connector}


data = json.loads((OUT / 'chart-core.json').read_text('utf-8'))
assert not data['failures']
comparisons, failures = 0, []
for case_index, case in enumerate(data['cases']):
    previous, levels = {1: -float('inf'), -1: -float('inf')}, {1: 0, -1: 0}
    for entry, actual in zip(case['entries'], case['actual'], strict=True):
        expected = execute(entry, case['plot'], previous, levels)
        valid = abs(expected['center'][1] - actual['center'][1]) < 0.0001 and expected['level'] == actual['level'] and expected['connector'] == actual['connector']
        comparisons += 1
        if not valid: failures.append({'case': case_index, 'ply': entry['ply'], 'expected': expected, 'actual': actual})
result = {'checks': comparisons, 'failures': failures, 'dex_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'dex_range': '00ff..0195', 'cases': len(data['cases'])}
(OUT / 'chart-dex-oracle.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), 'utf-8')
print(json.dumps({'checks': comparisons, 'failures': len(failures)}))
raise SystemExit(bool(failures))
