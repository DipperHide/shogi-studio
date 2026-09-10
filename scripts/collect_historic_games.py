"""Retrieve public, completed tournament move records; retain source provenance.

Only game facts and moves are packaged, never broadcasts, photos or commentary.
Source HTML/KIF is cached locally to make normalization independently auditable.
"""
import concurrent.futures
import hashlib
import json
import pathlib
import re
import urllib.request
from urllib.parse import urljoin

ROOT = pathlib.Path(__file__).resolve().parents[1]
CACHE = ROOT / '.work' / 'historic-sources'
CACHE.mkdir(parents=True, exist_ok=True)

def get(url):
    path = CACHE / (hashlib.sha256(url.encode()).hexdigest()[:16] + pathlib.Path(url).suffix)
    if path.exists():
        data = path.read_bytes()
    else:
        data = urllib.request.urlopen(url, timeout=18).read()
        path.write_bytes(data)
    for encoding in ('utf-8-sig', 'cp932'):
        try:
            return data.decode(encoding), hashlib.sha256(data).hexdigest()
        except UnicodeDecodeError:
            pass
    raise ValueError('Unknown record encoding ' + url)

def discover(url):
    html, _ = get(url)
    return sorted(set(urljoin(url, x) for x in re.findall(r'href=["\']([^"\']+)["\']', html) if any(k in x for k in ['kifu/', 'back', 'archive'])))

def record(page):
    html, _ = get(page)
    match = re.search(r'KIF_FILE_NAME\s*=\s*["\']([^"\']+)', html)
    if not match:
        raise ValueError('No KIF link ' + page)
    source = urljoin(page, match[1])
    raw, digest = get(source)
    lines = raw.splitlines()
    tags = {}
    for line in lines:
        if '：' in line and not line.startswith(('*', '#')):
            key, value = line.split('：', 1)
            if key in ['先手', '後手', '開始日時', '終了日時', '棋戦', '戦型', '場所', '持ち時間', '手合割']:
                tags[key] = value.strip()
    moves = [l for l in lines if re.match(r'^\s*\d+\s+[^\s]+', l)]
    # A terminal marker distinguishes a completed record from a short example.
    if not moves or not any(w in moves[-1] for w in ['投了', '詰み', '千日手', '持将棋', '切れ負け']):
        raise ValueError('Incomplete game ' + source)
    facts = [k + '：' + v for k, v in tags.items()]
    facts += ['手数----指手---------消費時間--'] + moves
    return {'id': pathlib.Path(source).stem, 'source': page, 'kif_source': source, 'sha256': digest,
            'tags': tags, 'plies': len(moves) - 1, 'terminal': moves[-1].strip(), 'kif': '\n'.join(facts)}

if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == 'discover':
        for url in sys.argv[2:]:
            print(json.dumps({'url': url, 'links': discover(url)}, ensure_ascii=False))
    else:
        pages = json.loads((CACHE / 'pages.json').read_text(encoding='utf-8'))
        games, errors = [], []
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            jobs = {pool.submit(record, u): u for u in pages}
            for job in concurrent.futures.as_completed(jobs):
                try:
                    game = job.result()
                    games.append(game)
                    print(game['id'], game['plies'], flush=True)
                except Exception as error:
                    errors.append({'source': jobs[job], 'error': str(error)})
        games.sort(key=lambda g: g['tags'].get('開始日時', ''), reverse=True)
        output = ROOT / 'godot/assets/data/historic-games.json'
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps({'version': 1, 'retrieved': '2026-09-10', 'games': games}, ensure_ascii=False, indent=2), encoding='utf-8')
        (CACHE / 'errors.json').write_text(json.dumps(errors, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps({'games': len(games), 'errors': errors}, ensure_ascii=False), flush=True)
