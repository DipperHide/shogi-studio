"""Install official portable development tools in the current user's directory."""
from pathlib import Path
import urllib.request, json, re, hashlib, subprocess, zipfile, concurrent.futures, time
ROOT=Path.home()/'Development'
CACHE=ROOT/'Downloads'; TOOLS=ROOT/'Tools'
SDK=ROOT/'AndroidSDK'
for p in (CACHE,TOOLS,SDK):p.mkdir(parents=True,exist_ok=True)
(TOOLS/'Godot').mkdir(exist_ok=True)
(TOOLS/'Godot/_sc_').touch()
def get(url):
    req=urllib.request.Request(url,headers={'User-Agent':'ShogiDevelopmentSetup/1.0'})
    with urllib.request.urlopen(req,timeout=90) as r:return r.read()
def js(url):return json.loads(get(url))
rels=js('https://api.github.com/repos/godotengine/godot-builds/releases?per_page=20')
godot=next(r for r in rels if r['tag_name'].startswith('4.') and not r['prerelease'])
ver=godot['tag_name'].replace('-stable','')
ga={a['name']:a for a in godot['assets']}
sums=get(ga['SHA512-SUMS.txt']['browser_download_url']).decode()
def sha_for(name,listing):
    return next(l.split()[0] for l in listing.splitlines() if l.strip().endswith(name))
blist=get('https://download.blender.org/release/Blender4.5/').decode()
bfiles=set(re.findall(r'blender-4\.5\.(\d+)-windows-x64.zip',blist))
bver='4.5.'+str(max(map(int,bfiles))); bname=f'blender-{bver}-windows-x64.zip'
bsums=get(f'https://download.blender.org/release/Blender4.5/blender-{bver}.sha256').decode()
jdk=js('https://api.adoptium.net/v3/assets/latest/17/hotspot?architecture=x64&image_type=jdk&os=windows')[0]
jpack=jdk['binary']['package']
studio=get('https://developer.android.com/studio').decode()
surl=re.search(r'https://[^"\s<>]+windows.zip',studio).group()
curl=re.search(r'https://[^"\s<>]+commandlinetools-win-\d+_latest.zip',studio).group()
def page_sha(name):
    # Table cells contain the official digest next to the package filename.
    pos=studio.find(name)
    match=re.search(r'\b[a-f0-9]{64}\b',studio[pos:pos+4000])
    return match.group() if match else None
jobs=[]
def job(key,url,dest,sha=None,algo='sha256',subset=None,strip=None):
    jobs.append(dict(key=key,url=url,dest=str(dest),sha=sha,algo=algo,subset=subset,strip=strip))
gn=f'Godot_v{ver}-stable_win64.exe.zip'; tn=f'Godot_v{ver}-stable_export_templates.tpz'
job('godot',ga[gn]['browser_download_url'],TOOLS/'Godot',sha_for(gn,sums),'sha512')
job('templates',ga[tn]['browser_download_url'],TOOLS/f'Godot/editor_data/export_templates/{ver}.stable',sha_for(tn,sums),'sha512',['android','windows','version.txt'],'templates/')
job('blender',f'https://download.blender.org/release/Blender4.5/{bname}',TOOLS,sha_for(bname,bsums))
job('jdk17',jpack['link'],TOOLS,jpack['checksum'])
job('android-studio',surl,TOOLS,page_sha(surl.rsplit('/',1)[-1]))
job('sdk-tools',curl,SDK/'cmdline-tools/latest',page_sha(curl.rsplit('/',1)[-1]),strip='cmdline-tools/')
manifest={'godotVersion':ver,'blenderVersion':bver,'sdk':str(SDK),'tools':str(TOOLS),'jobs':jobs}
(ROOT/'toolchain-install.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
def install(j):
    archive=CACHE/j['url'].rsplit('/',1)[-1]
    print(f"Downloading {j['key']}: {archive.name}",flush=True)
    cached=archive.is_file() and j['sha'] and hashlib.file_digest(archive.open('rb'),j['algo']).hexdigest().lower()==j['sha'].lower()
    if not cached:
        for attempt in range(3):
            result=subprocess.run(['curl.exe','-L','--fail','--retry','3','--connect-timeout','30','--max-time','1800','-sS','-C','-','-o',str(archive),j['url']],capture_output=True,text=True)
            if result.returncode==0:break
            print(f"Retry {j['key']}: {result.stderr[-400:]}",flush=True)
        if result.returncode:raise RuntimeError(j['key']+' download failed '+result.stderr)
    digest=hashlib.file_digest(archive.open('rb'),j['algo']).hexdigest()
    if j['sha'] and digest.lower()!=j['sha'].lower():raise RuntimeError(j['key']+' hash mismatch')
    dest=Path(j['dest']);dest.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for member in z.infolist():
            name=member.filename
            if j['strip']:
                if not name.startswith(j['strip']):continue
                name=name[len(j['strip']):]
            if j['subset'] and not any(name.startswith(s) for s in j['subset']):continue
            if not name:continue
            out=(dest/name).resolve()
            norm=lambda p:str(p).removeprefix('\\\\?\\').casefold()
            if not (norm(out)==norm(dest.resolve()) or norm(out).startswith(norm(dest.resolve())+'\\')):raise RuntimeError('Unsafe archive member '+name)
            if member.is_dir():out.mkdir(parents=True,exist_ok=True);continue
            out.parent.mkdir(parents=True,exist_ok=True)
            with z.open(member) as src,out.open('wb') as target:
                import shutil;shutil.copyfileobj(src,target)
    done={'key':j['key'],'archive':str(archive),'bytes':archive.stat().st_size,'digest':digest,'verifiedAgainstPublisher':bool(j['sha']),'destination':str(dest)}
    (ROOT/(j['key']+'-installed.json')).write_text(json.dumps(done,indent=2))
    print('Installed '+j['key']+' '+str(round(archive.stat().st_size/1048576))+' MB; publisher hash '+str(bool(j['sha'])),flush=True)
    return done
failures=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    futures={pool.submit(install,j):j for j in jobs}
    for f in concurrent.futures.as_completed(futures):
        try:f.result()
        except Exception as e:
            failures.append(str(e));print('FAILED: '+str(e),flush=True)
print('Download/install phase finished',flush=True)
if failures:raise SystemExit(1)
