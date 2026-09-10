"""Execute the reference DEX's no-moment branch and I/N/p/j helpers offline.

This limited interpreter fails on unsupported opcodes; it does not run the APK,
Android, network, or arbitrary classes. Production never depends on this script.
"""
import hashlib
import json
import math
import re
import struct
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'review/app/chessis19'
DEX=ROOT/'.work/chessis-reference/dex-evidence'
public=(ROOT/'.work/chessis-reference/java/sources/com/chessimprovement/chessis/R.java').read_text('utf-8')
resources={int(value,16):name for name,value in re.findall(r'int (game_story_\w+) = (0x[0-9a-f]+);',public)}
programs={}
for name in ['c','I','N','p','j']:
    lines=(DEX/f'a2-p-{name}.txt').read_text('utf-8').splitlines()
    regs,inputs=map(int,re.findall(r'\d+',lines[1]))
    instructions={int(m[1],16):(m[2],m[3]) for line in lines[2:] if (m:=re.match(r'(\w+) +(\S+) +(.*)',line))}
    addresses=list(instructions)
    programs[name]=(regs,inputs,instructions,dict(zip(addresses,addresses[1:])))

def null(value): return value is None or isinstance(value,(int,float)) and value==0

def run(name,args=(),initial=None,start=0):
    size,inputs,code,next_pc=programs[name]
    v=[0]*size
    v[size-inputs:]=args if args else v[size-inputs:]
    for key,value in (initial or {}).items(): v[key]=value
    pc=start
    result=None
    for _ in range(20000):
        if name=='c' and pc==0x349: return v[2]
        op,out=code[pc]
        registers=[int(x) for x in re.findall(r'\bv(\d+)\b',out.split(', L')[0])]
        target=next_pc.get(pc)
        a=registers[0] if registers else 0
        if op.startswith('const-string'): v[a]=json.loads(out.split(', ',1)[1])
        elif op=='const/high16': v[a]=struct.unpack('<f',struct.pack('<I',int(out.split(', ')[1])))[0]
        elif op.startswith('const'): v[a]=int(out.split(', ')[1])
        elif op.startswith('move-result'): v[a]=result
        elif op.startswith('move'): v[a]=v[registers[1]]
        elif op.startswith('return'): return v[a]
        elif op.startswith('goto'): target=pc+int(out[:-1],16)
        elif op.startswith('if-'):
            condition=op[3:]
            left=v[a]
            right=0 if condition.endswith('z') else v[registers[1]]
            condition=condition.rstrip('z')
            eq=(null(left) and null(right)) or left==right
            take={'eq':lambda:eq,'ne':lambda:not eq,'ge':lambda:left>=right,'gt':lambda:left>right,'lt':lambda:left<right,'le':lambda:left<=right}[condition]()
            if take: target=pc+int(out.split(', ')[-1][:-1],16)
        elif op=='array-length': v[a]=len(v[registers[1]])
        elif op.startswith('aget'): v[a]=v[registers[1]][v[registers[2]]]
        elif op.startswith('aput'): v[registers[1]][v[registers[2]]]=v[a]
        elif op=='new-array': v[a]=[None]*v[registers[1]]
        elif op=='new-instance': v[a]={}
        elif op.startswith('iget'): v[a]=v[registers[1]].get(re.search(r'->(\w+) ',out)[1],0)
        elif op.startswith('iput'): v[registers[1]][re.search(r'->(\w+) ',out)[1]]=v[a]
        elif op.startswith('neg-'): v[a]=-v[registers[1]]
        elif op.startswith(('cmpl-','cmpg-')):
            left,right=v[registers[1]],v[registers[2]]
            v[a]=int(left>right)-int(left<right)
        elif op.startswith(('add-','sub-','mul-','div-')):
            if '/lit' in op: left,right=v[registers[1]],int(out.split(', ')[-1])
            elif '/2addr' in op: left,right=v[a],v[registers[1]]
            else: left,right=v[registers[1]],v[registers[2]]
            v[a]={'add':lambda:left+right,'sub':lambda:left-right,'mul':lambda:left*right,'div':lambda:left/right}[op.split('-')[0]]()
        elif op.startswith('invoke-'):
            method=re.search(r'(L[^, ]+;)->([^ (]+)',out)
            owner,method_name=method.groups()
            before=out[:method.start()].rstrip(', ')
            regs=[int(x) for x in re.findall(r'v(\d+)',before)]
            if '...' in before: regs=list(range(regs[0],regs[1]+1))
            values=[v[i] for i in regs]
            if owner=='Ljava/lang/Object;' and method_name=='<init>': result=None
            elif owner=='Ljava/lang/Math;':
                result={'abs':abs,'max':max,'min':min,'round':lambda x:math.floor(x+0.5)}[method_name](*values)
            elif owner=='La2/p;' and method_name in programs: result=run(method_name,values)
            elif owner=='La2/p;' and method_name=='x': result=next((p for p in values[0] if p['a']==values[1]),None)
            elif owner=='La2/p;' and method_name=='T': result=values[1]
            elif owner=='La2/p;' and method_name=='M': result=values[1]
            elif owner=='La2/p;' and method_name=='X': result={'reference':resources[values[1]],'arguments':values[3]}
            elif owner=='La2/p;' and method_name=='V': result=values[0][values[1]]
            elif owner=='La2/p;' and method_name=='H': result=values[0][values[1]]
            elif owner=='La2/p;' and method_name=='A': result=values[0] in [8,9,10]
            elif owner=='La2/p;' and method_name=='q': result=1 if values[0]>=300 else -1 if values[0]<=-300 else 0
            elif owner=='La2/o;' and method_name=='d': result=values[0].get({(1,8):'E',(-1,8):'F',(1,9):'G',(-1,9):'H',(1,10):'I',(-1,10):'J'}[(values[1],values[2])],0)
            elif owner=='La2/n;' and method_name=='<init>': values[0].update(c=values[1],a=values[2],b=values[3])
            elif owner=='LM5/a;' and method_name in ['a','c']: result=values[0]
            elif owner=='Lz0/a;' and method_name=='_values': result=[1,2,3]
            elif owner=='Lx/e;' and method_name=='f': result=list(range(1,values[0]+1))
            else: raise AssertionError((name,hex(pc),owner,method_name))
        else: raise AssertionError((name,hex(pc),op,out))
        pc=target
    raise AssertionError('instruction budget exceeded')

def phase(p):
    s=p['stats']; c=s['counts']
    return {'a':p['type'],'c':s['accuracy'],'d':s['has_accuracy'],'g':c.get('失误',0),'z':c.get('漏着',0),'A':c.get('错失胜机',0)}

def reference_context(data):
    stats={}
    for side in [1,-1]:
        source=data['sides'][str(side)]
        stats['y' if side==1 else 'z']=source['first_advantage']
        stats['A' if side==1 else 'B']=source['minimum_after_advantage']
        stats['C' if side==1 else 'D']=source['inaccuracies']
        for cat,field in [('失误','E' if side==1 else 'F'),('漏着','G' if side==1 else 'H'),('错失胜机','I' if side==1 else 'J')]: stats[field]=source['relevant'].get(cat,0)
    stats['r']=data['sample_count']
    return stats

checks=[]; failures=[]; results=[]
def check(value,title):
    checks.append(title)
    if not value: failures.append(title)

data=json.loads((OUT/'story-core.json').read_text('utf-8'))
for case in data['cases']:
    d=case['context']
    expected=run('c',initial={0:None,3:None,4:[phase(p) for p in d['sides']['1']['phases']],5:[phase(p) for p in d['sides']['-1']['phases']],6:case['winner'],7:2131952793,11:-100,12:reference_context(d),44:d['sides']['1']['overall']['accuracy'],45:d['sides']['-1']['overall']['accuracy'],47:not case['closed']},start=0x356)
    check(expected['reference']==case['result']['reference'],case['label']+': original DEX branch')
    results.append({'label':case['label'],'original_dex':expected,'actual':case['result']})
fixture=data['context_fixture']
codes={'定式':1,'妙手':2,'锐利':3,'最佳':4,'优秀':5,'好棋':6,'不精确':7,'失误':8,'漏着':9,'错失胜机':10}
stats=run('j',[[s/100 for s in fixture['scores']],[0]+[codes[r['category']] for r in fixture['rows']],[False]+[r['side']==1 for r in fixture['rows']],True])
actual_stats=reference_context(fixture['actual'])
for key,value in actual_stats.items(): check(value==stats.get(key,0),f'context field {key}: original DEX j')
actual=json.loads((OUT/'ui/actual-report.json').read_text('utf-8'))
scores=[]
for sample in actual['samples']:
    score=sample['score']
    if sample.get('mate',False): value=(1 if score>0 else -1 if score<0 else 0)*(100000-min(49,abs(int(sample.get('mate_distance',1)))))
    else: value=score/(600*0.00368208)
    scores.append(math.floor(abs(value)+0.5)*(1 if value>=0 else -1))
actual_context=actual['story']['phase_context']
actual_j=run('j',[[s/100 for s in scores],[0]+[codes[r['category']] for r in actual['rows']],[False]+[r['side']==1 for r in actual['rows']],True])
for key,value in reference_context(actual_context).items(): check(value==actual_j.get(key,0),f'actual 140-ply context {key}: original DEX j')
for side in [1,-1]:
    expected=run('p',[[phase(p) for p in actual_context['sides']['1']['phases']],[phase(p) for p in actual_context['sides']['-1']['phases']],side])
    check(expected==actual_context['sides'][str(side)]['better_phases'],f'actual phase advantage count side {side}: original DEX p')
result={'checks':checks,'failures':failures,'original_dex_results':results,'executed_methods':['c:0356..06e4','I','N','p','j'],'dex_sha256':{n:hashlib.sha256((DEX/f'a2-p-{n}.txt').read_bytes()).hexdigest() for n in programs}}
(OUT/'story-dex-oracle.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),'utf-8')
print(json.dumps({'checks':len(checks),'failures':failures},ensure_ascii=False))
raise SystemExit(bool(failures))
