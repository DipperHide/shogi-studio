"""Read-only DEX evidence for methods with unreliable Java decompilation."""
from pathlib import Path
from zipfile import ZipFile
import argparse
import json
from loguru import logger
from androguard.core.dex import DEX

logger.remove()
ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('class_name')
parser.add_argument('methods', nargs='+')
args = parser.parse_args()
apk = Path('C:/Users/jinda/xwechat_files/wxid_g7vifo7syngj22_7823/msg/file/2026-09/base.apk.1')
out = ROOT / '.work/chessis-reference/dex-evidence'
out.mkdir(parents=True, exist_ok=True)
found = []
with ZipFile(apk) as archive:
    for entry in archive.namelist():
        if not entry.endswith('.dex'): continue
        dex = DEX(archive.read(entry))
        for cls in dex.get_classes():
            if cls.get_name() != args.class_name: continue
            for method in cls.get_methods():
                if method.get_name() not in args.methods: continue
                title = cls.get_name() + ' ' + method.get_name() + ' ' + method.get_descriptor()
                code = method.get_code()
                lines = [title, f'registers={code.get_registers_size()} inputs={code.get_ins_size()}']
                offset = 0
                for instruction in method.get_instructions():
                    lines.append(f'{offset // 2:04x} {instruction.get_name():24} {instruction.get_output()}')
                    offset += instruction.get_length()
                name = cls.get_name().strip('L;').replace('/', '-') + '-' + method.get_name() + '.txt'
                (out / name).write_text('\n'.join(lines), 'utf-8')
                found.append(name)
print(json.dumps(found))
assert len(found) >= len(args.methods), 'Requested methods missing'
