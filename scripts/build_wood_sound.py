"""Soften the user-selected sample-02 while retaining its short wooden attack.

No replacement sound, added click, pitch shift or peak re-normalization.
"""
from pathlib import Path
import hashlib, json, math, wave
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'review/app/v044'
OUT.mkdir(parents=True,exist_ok=True)
source=ROOT/'assets/audio/selected-snap-source.wav'
with wave.open(str(source),'rb') as f:
    assert f.getnchannels()==1 and f.getsampwidth()==2
    rate=f.getframerate()
    original=np.frombuffer(f.readframes(f.getnframes()),dtype='<i2').astype(float)/32768

def bell_cut(signal, frequency, db, q):
    # Causal parametric EQ: no FFT pre-ringing before the original transient.
    a=10**(db/40)
    w=2*math.pi*frequency/rate
    alpha=math.sin(w)/(2*q)
    b=np.array([1+alpha*a,-2*math.cos(w),1-alpha*a])
    denominator=np.array([1+alpha/a,-2*math.cos(w),1-alpha/a])
    b/=denominator[0]
    denominator/=denominator[0]
    out=np.zeros_like(signal)
    x1=x2=y1=y2=0.0
    for i,x in enumerate(signal):
        y=b[0]*x+b[1]*x1+b[2]*x2-denominator[1]*y1-denominator[2]*y2
        out[i]=y
        x2,x1=x1,x
        y2,y1=y1,y
    return out

duration=.095
t=np.arange(round(rate*duration))/rate
dry=original[:len(t)]
filtered=bell_cut(dry,8200,-5.0,.85)
fade=np.clip((duration-t)/(duration-.032),0,1)
envelope=fade*fade*(3-2*fade)
signal=filtered*envelope*10**(-2.5/20)
signal[0]=signal[-1]=0
pcm=np.round(signal*32767).astype('<i2')
destination=ROOT/'godot/assets/audio/wood-place.wav'
with wave.open(str(destination),'wb') as f:
    f.setnchannels(1);f.setsampwidth(2);f.setframerate(rate);f.writeframes(pcm.tobytes())
(OUT/'wood-place.wav').write_bytes(destination.read_bytes())

def stats(x):
    spectrum=abs(np.fft.rfft(x))**2
    hz=np.fft.rfftfreq(len(x),1/rate)
    bands={}
    for low,high in [(0,1000),(1000,2500),(2500,4500),(4500,7000),(7000,12000),(12000,22050)]:
        bands[f'{low}-{high}Hz']=round(float(spectrum[(hz>=low)&(hz<high)].sum()/spectrum.sum()*100),3)
    return {'peak_dbfs':round(float(20*np.log10(max(abs(x)))),3),
            'energy':float(np.sum(x*x)), 'band_energy_percent':bands}

# Compare on equal duration, so a shorter file cannot make RMS seem louder.
old=original[:round(rate*.120)].copy()
old_t=np.arange(len(old))/rate
old_fade=np.clip((.120-old_t)/.040,0,1)
old*=old_fade*old_fade*(3-2*old_fade)
baseline,new=stats(old),stats(np.pad(signal,(0,len(old)-len(signal))))
report={'duration_ms':round(len(signal)/rate*1000,2),'before':baseline,'after':new,
    'level_change_db_equal_window':round(10*math.log10(new['energy']/baseline['energy']),3),
    'clipped_samples':int(np.count_nonzero(abs(pcm.astype(np.int32))>=32767)),
    'tail_energy_after_60ms_percent':round(float(np.sum(signal[t>.060]**2)/np.sum(signal**2)*100),4),
    'source':'User-provided recording, user-selected sample-02.wav',
    'source_file':str(source.relative_to(ROOT)),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'output_sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),
    'processing':{'eq':{'type':'bell','hz':8200,'gain_db':-5.0,'q':.85},'gain_db':-2.5,'fade_ms':[32,95],'synthesis':False,'pitch_shift':False,'import':'Uncompressed 16-bit PCM'},
    'validation':'Numerical waveform/spectrum checks; no direct listening test available.'}
assert report['clipped_samples']==0
assert -8<report['level_change_db_equal_window']<-3
assert new['band_energy_percent']['7000-12000Hz']<baseline['band_energy_percent']['7000-12000Hz']
assert report['tail_energy_after_60ms_percent']<1
(OUT/'audio-checks.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
