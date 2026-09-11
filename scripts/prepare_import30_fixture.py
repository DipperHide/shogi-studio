"""Encode the Godot-generated KIF fixture exactly as a legacy Japanese export."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / 'review/app/chessis30/source.kif'
source.with_name('source-cp932.kif').write_bytes(source.read_text('utf-8').encode('cp932'))
