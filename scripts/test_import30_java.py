"""Exercise the Android record decoder on the host JVM; not a device UI test."""
from pathlib import Path
import json
import os
import subprocess
from toolchain import load

root = Path(__file__).resolve().parents[1]
java = Path(os.environ.get('JAVA_HOME') or load()['jdk']) / 'bin'
suffix = '.exe' if os.name == 'nt' else ''
out = root / 'review/app/chessis30'
classes = root / '.work/import30-java'
classes.mkdir(parents=True, exist_ok=True)
out.mkdir(parents=True, exist_ok=True)
subprocess.run([str(java / ('javac' + suffix)), '-encoding', 'UTF-8', '-d', str(classes),
                str(root / 'android-plugin/src/org/shogistudio/platform/AnalysisRecordText.java'),
                str(root / 'android-plugin/tests/AnalysisRecordTextTest.java')], check=True)
result = subprocess.run([str(java / ('java' + suffix)), '-cp', str(classes), 'AnalysisRecordTextTest'], check=True, capture_output=True, text=True, encoding='utf-8')
data = json.loads(result.stdout)
assert not data['failures'] and data['checks'] == 14
data['android_device_tested'] = False
(out / 'java-decoder.json').write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
print(result.stdout.strip())
