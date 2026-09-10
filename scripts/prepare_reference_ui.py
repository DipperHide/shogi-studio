"""Convert the supplied APK's decoded UI vectors into equivalent SVG resources."""
from pathlib import Path
import hashlib
import json
import shutil
import xml.etree.ElementTree as ET
from zipfile import ZipFile
from loguru import logger
from androguard.core.axml import ARSCParser

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / '.work/chessis-reference'
OUT = ROOT / 'godot/assets/reference-ui'
OUT.mkdir(parents=True, exist_ok=True)
A = '{http://schemas.android.com/apk/res/android}'
names = ['ic_eye', 'ic_play', 'ic_pause', 'ic_report', 'ic_quick_report', 'ic_deep_report', 'ic_settings', 'ic_arrow_forward', 'ic_arrow_drop_up', 'ic_hint_up', 'ic_stop', 'ic_close', 'ic_baseline_menu_24', 'ic_search', 'ic_flip_board', 'ic_nav_previous', 'ic_nav_next', 'ic_nav_play', 'ic_nav_pause', 'ic_nav_more']
names.append('ic_tune')
names.append('ic_undo')
names.append('ic_circle_check')
names.append('ic_remove_variation')
names.append('ic_engine_options_subtle')
names.extend(['ic_refresh', 'ic_delete', 'ic_redo', 'ic_save', 'ic_flipped_board', 'ic_non_flipped_board', 'ic_play_round'])
strength_names = ['ic_book_move', 'ic_brilliant_move', 'ic_great_move', 'ic_bestmove', 'ic_forced_move', 'ic_excellent_move', 'ic_good_move', 'ic_inaccuracy', 'ic_mistake', 'ic_blunder_icon', 'ic_missed_win']
neutral_names = ['ic_accurate_neutral', 'ic_trophy_neutral', 'ic_rating_trend_neutral']
logger.remove()
with ZipFile('C:/Users/jinda/xwechat_files/wxid_g7vifo7syngj22_7823/msg/file/2026-09/base.apk.1') as apk:
    resources = ARSCParser(apk.read('resources.arsc'))
colors_xml = resources.get_color_resources('com.chessimprovement.chessis')
(SOURCE / 'color-resources.xml').write_bytes(colors_xml)
colors = {element.get('name'): element.text for element in ET.fromstring(colors_xml)}


def color(value):
    value = {'@android:0106000D': '#00000000', '@android:0106000B': '#FFFFFF', '@android:0106000C': '#000000'}.get(value, value)
    if value.startswith('@color/'):
        return color(colors[value.split('/')[1]])
    if value == '@android:color/transparent': return '#000000', 0
    assert value.startswith('#'), value
    value = value[1:]
    if len(value) == 8: return '#' + value[2:], int(value[:2], 16) / 255
    assert len(value) == 6, value
    return '#' + value, 1


def copy_nodes(source, destination, colored):
    for node in source:
        if node.tag == 'group':
            x, y = float(node.get(A+'pivotX', '0')), float(node.get(A+'pivotY', '0'))
            tx, ty = float(node.get(A+'translateX', '0')), float(node.get(A+'translateY', '0'))
            rotation = float(node.get(A+'rotation', '0'))
            sx, sy = float(node.get(A+'scaleX', '1')), float(node.get(A+'scaleY', '1'))
            group = ET.SubElement(destination, 'g', transform=f'translate({tx+x} {ty+y}) rotate({rotation}) scale({sx} {sy}) translate({-x} {-y})')
            copy_nodes(node, group, colored)
            continue
        assert node.tag == 'path', node.tag
        fill, alpha = color(node.get(A+'fillColor', '#000000')) if colored else ('#ffffff', 1)
        attrs = {'d': node.get(A+'pathData'), 'fill': fill, 'fill-opacity': str(float(node.get(A+'fillAlpha', '1')) * alpha)}
        if not colored: attrs['fill-opacity'] = node.get(A+'fillAlpha', '1')
        if node.get(A+'fillType') in ['evenOdd', '1']: attrs['fill-rule'] = 'evenodd'
        if node.get(A+'strokeColor'):
            stroke, alpha = color(node.get(A+'strokeColor'))
            attrs.update({'stroke': stroke, 'stroke-opacity': str(alpha * float(node.get(A+'strokeAlpha', '1'))), 'stroke-width': node.get(A+'strokeWidth', '1')})
        for source_attr, svg_attr in [('strokeLineCap', 'stroke-linecap'), ('strokeLineJoin', 'stroke-linejoin')]:
            if node.get(A+source_attr): attrs[svg_attr] = {'0':'butt' if source_attr == 'strokeLineCap' else 'miter', '1':'round', '2':'square' if source_attr == 'strokeLineCap' else 'bevel'}.get(node.get(A+source_attr), node.get(A+source_attr))
        ET.SubElement(destination, 'path', attrs)


manifest = []
for name in names + strength_names + neutral_names:
    source = SOURCE / 'res/drawable' / (name + '.xml')
    vector = ET.parse(source).getroot()
    assert vector.tag == 'vector'
    svg = ET.Element('svg', xmlns='http://www.w3.org/2000/svg', width='24', height='24', viewBox=f"0 0 {vector.get(A+'viewportWidth')} {vector.get(A+'viewportHeight')}")
    copy_nodes(vector, svg, name in strength_names + neutral_names)
    ET.ElementTree(svg).write(OUT / (name + '.svg'), encoding='utf-8', xml_declaration=False)
    manifest.append({'asset': name+'.svg', 'source': 'res/drawable/'+name+'.xml', 'decoded_sha256': hashlib.sha256(source.read_bytes()).hexdigest()})
shutil.copyfile(SOURCE / 'wood_dark.png', OUT / 'wood_dark.png')
manifest.append({'asset': 'wood_dark.png', 'source': 'supplied APK wood_dark drawable', 'sha256': hashlib.sha256((OUT/'wood_dark.png').read_bytes()).hexdigest()})
(OUT / 'provenance.json').write_text(json.dumps({'apk_sha256': '14df01b58e777a130aee977c51a9b7823c8c8ada31479843b2f01b765b49f111', 'assets': manifest}, indent=2), encoding='utf-8')
print('Prepared', len(manifest), 'reference UI assets')
