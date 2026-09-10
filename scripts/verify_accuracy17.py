"""Independent numerical check of the new chart and its default impact highlight."""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/chessis17'
data = json.loads((OUT / 'ui/actual-report.json').read_text('utf-8'))
checks = []
failures = []


def check(value, title):
    checks.append(title)
    if not value:
        failures.append(title)


def rounded(value):
    value = max(0.0, min(100.0, value))
    result = math.floor(value * 10 + 0.5) / 10
    return 99.9 if value < 100 and result >= 100 else result


def score(rows, penalty):
    points = [r for r in rows if not r['metrics']['book'] and r['metrics']['weight'] > 0]
    if not points:
        return None
    weight = sum(r['metrics']['weight'] for r in points)
    accuracy = sum(r['metrics']['accuracy'] * r['metrics']['weight'] for r in points) / weight
    if len(points) > 1:
        cpl = sum(r['metrics']['cpl'] * r['metrics']['weight'] for r in points) / weight
        wpl = sum(r['metrics']['wpl'] * r['metrics']['weight'] for r in points) / weight
        accuracy = max(0, min(100, -1.668449 * wpl - 5.38865 * math.log(cpl + 10) + 0.672122 * accuracy + 48.1131))
    if penalty:
        counts = [0.0, 0.0, 0.0]
        for r in points:
            cat = '漏着' if r['category'] == '错失胜机' else r['category']
            if cat not in ['不精确', '失误', '漏着']:
                continue
            m = r['metrics']
            saturated = (m['before_chance'] >= 95 and m['after_chance'] >= 90) or (m['before_chance'] <= 5 and m['after_chance'] <= 10)
            counts[['不精确', '失误', '漏着'].index(cat)] += 0.25 if saturated else 1
        adjustment = sum(n * a + (n - 1) * b * n / 2 for n, a, b in zip(counts, [0.25, 0.7, 1], [0.05, 0.15, 0.25]))
        accuracy -= min(6, adjustment)
    return rounded(accuracy)


impacts = {}
for name, side in [('sente', 1), ('gote', -1)]:
    model = data['insights'][name]
    rows = [r for r in data['rows'] if r['side'] == side]
    scored = [r for r in rows if not r['metrics']['book'] and r['metrics']['weight'] > 0]
    overall = score(rows, True)
    check(overall == model['overall']['accuracy'], f'{name}: independent overall aggregation')
    check([p['ply'] for p in model['points']] == [r['ply'] for r in scored], f'{name}: original scored ply indices')
    for point, row in zip(model['points'], scored):
        check(abs(point['accuracy'] - row['metrics']['accuracy']) < 1e-7, f'{name}: actual point accuracy at {point["ply"]}')
        check(point['category'] == row['category'] and point['label'] == row['label'], f'{name}: point identity at {point["ply"]}')
        check(point['before'] == data['samples'][point['ply'] - 1] and point['after'] == data['samples'][point['ply']], f'{name}: exact adjacent evaluations at {point["ply"]}')
    candidates = []
    for i, row in enumerate(scored):
        remaining = scored[:i] + scored[i+1:]
        without = score(remaining, False)
        if without is None:
            continue
        gain = math.floor(max(0, without - overall) * 10 + 0.5) / 10
        candidates.append({'ply':row['ply'], 'accuracy':row['metrics']['accuracy'], 'without':without, 'gain':gain})
    candidates.sort(key=lambda c: (-c['gain'], c['accuracy'], c['ply']))
    expected = candidates[0] if candidates and candidates[0]['gain'] >= 0.5 else {}
    check(model['impact'] == expected, f'{name}: leave-one-out default highlight and all tie breakers')
    impacts[name] = expected
result = {'checks':checks, 'failures':failures, 'independent_impact_results':impacts, 'actual_game_plies':len(data['rows'])}
(OUT / 'accuracy-oracle.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), 'utf-8')
print(json.dumps({'checks':len(checks),'failures':failures,'impact':impacts}, ensure_ascii=False))
raise SystemExit(bool(failures))
