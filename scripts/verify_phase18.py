"""Independently reconcile the phase popup with the actual engine rows."""
import json
import math
from collections import Counter
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'review/app/chessis18'
data=json.loads((OUT/'ui/actual-report.json').read_text('utf-8'))
checks=[]
failures=[]

def check(value,title):
    checks.append(title)
    if not value: failures.append(title)

def accuracy(rows,penalties):
    points=[r for r in rows if r['metrics']['weight']>0 and not r['metrics']['book']]
    if not points: return None
    weight=sum(r['metrics']['weight'] for r in points)
    value=sum(r['metrics']['accuracy']*r['metrics']['weight'] for r in points)/weight
    if len(points)>1:
        cpl=sum(r['metrics']['cpl']*r['metrics']['weight'] for r in points)/weight
        wpl=sum(r['metrics']['wpl']*r['metrics']['weight'] for r in points)/weight
        value=max(0,min(100,-1.668449*wpl-5.38865*math.log(cpl+10)+0.672122*value+48.1131))
    if penalties:
        counts=[0.0,0.0,0.0]
        for row in points:
            category='漏着' if row['category']=='错失胜机' else row['category']
            if category not in ['不精确','失误','漏着']: continue
            m=row['metrics']
            saturated=(m['before_chance']>=95 and m['after_chance']>=90) or (m['before_chance']<=5 and m['after_chance']<=10)
            counts[['不精确','失误','漏着'].index(category)]+=0.25 if saturated else 1
        value-=min(6,sum(n*a+(n-1)*b*n/2 for n,a,b in zip(counts,[0.25,0.7,1],[0.05,0.15,0.25])))
    value=max(0,min(100,value))
    rounded=math.floor(value*10+0.5)/10
    return 99.9 if value<100 and rounded>=100 else rounded

for name,side in [('sente',1),('gote',-1)]:
    model=data['phases'][name]
    rows=[r for r in data['rows'] if r['side']==side]
    check(model['overall']['accuracy']==accuracy(rows,True),f'{name}: overall uses penalized report aggregation')
    covered=[]
    for entry in model['phases']:
        segment=next(s for s in data['segments'] if s['type']==entry['type'])
        actual=[r for r in rows if segment['start']<=r['ply']<=segment['end']]
        counts=Counter(r['category'] for r in actual)
        stats=entry['stats']
        prefix=f'{name} phase {entry["type"]}'
        check(stats['count']==len(actual)>0,prefix+': player hand count')
        check(stats['counts']==counts,prefix+': all actual category counts')
        check(stats['accuracy']==accuracy(actual,False),prefix+': independent unpenalized phase aggregation')
        check(stats['evaluated']==sum(r['metrics']['weight']>0 for r in actual),prefix+': actual scored count')
        check(stats['book']==sum(r['metrics']['book'] for r in actual),prefix+': actual book count')
        expected=[{'category':c,'count':counts[c]} for c in ['错失胜机','漏着','失误','不精确'] if counts[c]>0]
        check(entry['errors']==expected,prefix+': positive error chips in original priority order')
        covered.extend(r['ply'] for r in actual)
    check(covered==[r['ply'] for r in rows],name+': each analyzed hand counted once')
forced=json.loads((OUT/'ui/forced-report.json').read_text('utf-8'))
check(forced['samples'][0]['legal_count']==1,'actual forced SFEN has a single engine input choice')
check(forced['phase']['stats']['forced']==1 and not forced['phase']['stats']['has_accuracy'],'actual forced phase has no accuracy')
check(forced['phase']['errors']==[],'unscored phase has no false error chips')
result={'checks':checks,'failures':failures,'actual_game_plies':len(data['rows']),'phase_scores':{name:[p['stats']['accuracy'] for p in data['phases'][name]['phases']] for name in ['sente','gote']}}
(OUT/'phase-oracle.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),'utf-8')
print(json.dumps({'checks':len(checks),'failures':failures},ensure_ascii=False))
raise SystemExit(bool(failures))
