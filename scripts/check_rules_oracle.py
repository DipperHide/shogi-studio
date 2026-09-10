"""Compare the GDScript generator with the independent python-shogi 1.1.1 library."""
import json
import argparse
from pathlib import Path
import shogi

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--fixtures',type=Path,default=ROOT/'review/app/rule-fixtures.json')
parser.add_argument('--report',type=Path,default=ROOT/'review/app/oracle-tests.json')
args = parser.parse_args()
fixtures = json.loads(args.fixtures.read_text(encoding='utf-8'))
symbols = ['', 'P', 'L', 'N', 'S', 'G', 'B', 'R', 'K', '+P', '+L', '+N', '+S', '', '+B', '+R']

def sfen(fixture):
    ranks = []
    for row in range(9):
        text, gap = '', 0
        for value in fixture['board'][row*9:row*9+9]:
            if value == 0:
                gap += 1
                continue
            if gap:
                text += str(gap)
                gap = 0
            piece = symbols[abs(value)]
            text += piece if value > 0 else piece.lower()
        if gap:
            text += str(gap)
        ranks.append(text)
    hand = ''
    for key in ['sente_hand', 'gote_hand']:
        for kind in [7, 6, 5, 4, 3, 2, 1]:
            count = fixture[key][kind]
            if count:
                piece = symbols[kind]
                if key == 'gote_hand':
                    piece = piece.lower()
                hand += (str(count) if count > 1 else '') + piece
    return '/'.join(ranks) + (' b ' if fixture['turn'] == 1 else ' w ') + (hand or '-') + ' 1'

def square(index):
    return str(9-index%9) + chr(ord('a')+index//9)

def usi(move):
    if move['drop']:
        return symbols[move['drop']] + '*' + square(move['to'])
    return square(move['from']) + square(move['to']) + ('+' if move['promote'] else '')

failures = []
total = 0
for index, fixture in enumerate(fixtures):
    board = shogi.Board(sfen(fixture))
    expected = {move.usi() for move in board.legal_moves}
    actual = {usi(move) for move in fixture['moves']}
    total += len(actual)
    if expected != actual:
        failures.append({'index': index, 'sfen': sfen(fixture), 'missing': sorted(expected-actual), 'extra': sorted(actual-expected)})
report = {'library': 'python-shogi 1.1.1', 'positions': len(fixtures), 'legal_moves_compared': total, 'failures': failures}
args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False))
raise SystemExit(bool(failures))
