"""Visually verified chapter 3 transcriptions; the user's EPUB remains private.

Every image on EPUB pages 206--219 was inspected, including all 24 boards and
attacker hands. Defence receives ALL remaining non-king material, as p.207
requires. python-shogi independently verifies mate and every printed refutation.
No OCR or diagram recognizer guesses are admitted as verified positions.
"""
from __future__ import annotations
import json
from collections import Counter
from pathlib import Path
import shogi

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/complete/tutorial-intro-tsume-supplement.json'
STOCK = Counter(P=18, L=4, N=4, S=4, G=4, B=2, R=2)
NAMES = {'P': '步', 'L': '香', 'N': '桂', 'S': '银', 'G': '金', 'B': '角', 'R': '飞', 'K': '玉', '+P': 'と', '+L': '成香', '+N': '成桂', '+S': '成银', '+B': '马', '+R': '龙'}
RANKS = '一二三四五六七八九'

def position(pieces: dict[str, str], hand: str = '') -> str:
    remaining = STOCK.copy()
    for piece in pieces.values():
        base = piece.upper().lstrip('+')
        if base != 'K': remaining[base] -= 1
    for piece in hand: remaining[piece] -= 1
    assert min(remaining.values()) >= 0
    rows = []
    for rank in 'abcdefghi':
        row, empty = '', 0
        for file in range(9, 0, -1):
            piece = pieces.get(f'{file}{rank}')
            if piece:
                row += (str(empty) if empty else '') + piece
                empty = 0
            else:
                empty += 1
        rows.append(row + (str(empty) if empty else ''))
    hands = ''
    for stock, lowercase in [(Counter(hand), False), (remaining, True)]:
        for piece in 'RBGSNLP':
            count = stock[piece]
            if count:
                hands += (str(count) if count > 1 else '') + (piece.lower() if lowercase else piece)
    return '/'.join(rows) + ' b ' + (hands or '-') + ' 1'

def notation(board: shogi.Board, usi: str) -> str:
    move = shogi.Move.from_usi(usi)
    piece = shogi.PIECE_SYMBOLS[move.drop_piece_type].upper() if move.drop_piece_type else board.piece_at(move.from_square).symbol().upper()
    square = usi[2:4]
    return ('▲' if board.turn == shogi.BLACK else '△') + square[0] + RANKS[ord(square[1])-97] + NAMES[piece] + ('打' if move.drop_piece_type else '成' if move.promotion else '')

PROBLEMS = [
    dict(n=1, pieces={'4a':'s','3a':'k','3c':'+P'}, hand='G', answer='G*2b',
         title='金要避开守银', hint='金应该打在哪里？',
         explanation='▲2二金打从玉的右侧贴上。3三的と保护2二，金与と共同封住逃路；守在4一的银也吃不到这枚金。',
         wrong=[('G*3b 4a3b', '金打在3二会被4一的守银吃掉，王手解除。'), ('G*4b 4a4b', '金打在4二同样会被守银吃掉；不能只看金是否将军，还要检查对方能否取金。')]),
    dict(n=2, pieces={'3a':'g','2a':'k','4b':'+R'}, hand='S', answer='S*1b',
         title='借龙的横向控制下银', hint='银应该打在哪里？',
         explanation='▲1二银打利用4二龙的横向控制：银得到龙的保护，并避开3一守金的取子范围。玉既不能取银，也没有安全逃格。',
         wrong=[('S*2b 3a2b', '2二银会被3一金吃掉，无法将死。'), ('S*3b 3a3b', '3二银也落在守金的取子范围内。'), ('4b3a 2a3a', '用龙直接吃3一的金也不成立：玉可以同玉取龙。')]),
    dict(n=3, pieces={'1a':'l','3b':'s','3c':'k','2c':'b','1c':'S','4d':'L','3d':'s'}, hand='B', answer='B*2b',
         title='封住4四的逃路', hint='不能允许玉吃掉4四的香。',
         explanation='▲2二角打既直接王手，也沿2二—3三—4四的斜线控制4四，使玉不能吃香逃走。盘上2三的角属于玉方，也占住了玉的一个相邻格。',
         wrong=[('B*2d 3c4d', '2四角虽然王手，玉却能到4四吃香，未能一步将死。'), ('B*4b 3c4d', '4二角同样漏掉4四；正确角位必须连同逃路一起封住。')]),
    dict(n=4, pieces={'3a':'k','5b':'+P','4b':'p','3b':'p','2b':'P'}, hand='R', answer='R*2a',
         title='飞要贴在步的保护下', hint='飞的打入位置是关键。',
         explanation='▲2一飞打受到2二步的保护；飞又控制2二，使玉不能取步逃跑。5二的と控制另一侧，因此恰好封住所有应手。',
         wrong=[('R*4a 3a2b', '从4一侧王手会漏掉2二，玉吃步后逃出。'), ('R*1a 3a2b', '同在右侧，1一飞也不够：仍然允许玉吃2二步。')]),
    dict(n=5, pieces={'4b':'+R','3c':'s','2c':'k','1c':'l','2e':'S','2g':'N'}, hand='', answer='2g3e',
         title='桂跳向哪一边', hint='动一动2七的桂。',
         explanation='▲3五桂用桂的跳跃王手，配合龙与银封住逃路。桂的王手不能靠合驹遮挡；玉方也无法取走3五桂。',
         wrong=[('2g1e 1c1e', '跳到1五会被1三香直线吃掉，王手被解除。'), ('4b3c 2c3c 2e3d 3c4d', '先用龙取3三银会被同玉吃龙；再3四银王手，玉还可以4四玉逃走。书中这段变化说明不能用取子替代正确的桂跳。')]),
    dict(n=6, pieces={'2b':'g','3c':'b','2c':'p','1c':'k','2e':'G'}, hand='L', answer='L*1d',
         title='香必须贴近玉打入', hint='留意玉方3三角的斜线。',
         explanation='▲1四香打受到2五金的保护，并且紧贴玉，没有可插入合驹的空格。通常香从较远处打能保留距离，但这道题必须靠近玉。',
         wrong=[('L*1f P*1e', '1六香允许玉方用剩余持驹在1五打步合驹，挡住香的王手。玉方的持驹并不是“无”。')]),
    dict(n=7, pieces={'5c':'G','4d':'k','3d':'g','4f':'G'}, hand='G', answer='G*4c',
         title='从玉的后方打尻金', hint='“尻金”应下在哪里？',
         explanation='▲4三金打是从玉的后方贴上的“尻金”。保留5三金并新增4三金，才能与4六金配合封住所有出口；这里的“打”字不能省略成移动盘上的金。',
         wrong=[('G*5d 4d3c', '▲5四金打从侧面用“腹金”逼近，会漏掉3三，玉可逃走。')]),
    dict(n=8, pieces={'3c':'s','3d':'k','5e':'+R','3f':'S','2f':'L'}, hand='', answer='5e4e',
         title='让龙同时封住4三', hint='用龙王手。',
         explanation='▲4五龙用邻接斜格王手，同时用竖向控制封住4三；银和香负责其余逃路，因此玉无应手。',
         wrong=[('5e5d P*4d 3f4e 3d3e', '▲5四龙看似有力，玉方却能△4四步打合驹。即使再▲4五银王手，也有△3五玉逃走。必须把“剩余全棋子”中的步算作玉方持驹。')]),
    dict(n=9, pieces={'6a':'r','4a':'+P','3b':'k','2b':'g','5c':'+B','5d':'g','3d':'S'}, hand='', answer='5c3a',
         title='别被白送的金诱惑', hint='5四的金可以白吃，但目标是一步将死。',
         explanation='▲3一马才是正解。马的近身直走控制3二玉，4一的と保护马并挡住6一飞；银协助封路。不能贪吃5四的金。',
         wrong=[('5c5d 3b4a', '马吃5四金会允许玉吃4一的と而逃走。'), ('4a3a 6a3a', '改走▲3一と，会让开4一，6一飞便可沿横线吃掉と。'), ('5c4b 3b2a', '▲4二马则漏掉2一，玉仍可逃走。')]),
    dict(n=10, pieces={'1b':'B','4c':'p','3c':'p','2c':'p','3d':'k','1d':'p','2e':'P','3f':'G'}, hand='R', answer='R*2d',
         title='利用角牵制守步', hint='发挥1二角的斜线。',
         explanation='▲2四飞打虽然放在玉方2三步的前面，△同歩却不合法：步一离开2三，1二角就会直射3四玉。2五步保护飞，金封住下方，因而将死。',
         wrong=[('R*3e 3d4d', '▲3五飞打允许△4四玉靠过来逃走。'), ('R*5d 4c4d', '▲5四飞打则会被4三的盘上步走到4四挡住王手；这里是走步，不是打步。')]),
    dict(n=11, pieces={'3b':'s','5c':'S','4c':'s','3c':'k','1c':'S','3d':'p','2e':'L'}, hand='', answer='1c2b',
         title='银不成才有向后斜走', hint='考虑银和香怎样配合。',
         explanation='▲2二银不成利用银向后斜走的一格控制3三玉，2五香保护这枚银并封住二筋，另一枚银守住四筋出口。若在2二升变，成银按金的走法便不再王手。',
         wrong=[('1c2d+', '走▲2四银成会挡住香的二筋控制，玉可以到2二躲开。'), ('1c2d', '▲2四银不成同样挡住香，仍允许玉逃到2二。'), ('1c2b+', '错解观察：▲2二银成虽是合法着法，却不是王手；本题必须保留银的后斜方向。')]),
    dict(n=12, pieces={'5a':'+R','3b':'k','5c':'B','4c':'p','2c':'p'}, hand='', answer='5a3a',
         title='龙封住玉的所有出口', hint='不要放玉从上方逃出。',
         explanation='▲3一龙由5三角沿斜线保护，同时控制3三的通路和两侧逃格。玉无论逃向上方还是沿一段移动都仍受攻击。',
         wrong=[('5a4b 3b2a', '▲4二龙会漏掉2一，玉仍能脱身。'), ('5a5b 3b2a', '▲5二龙也允许△2一玉，差一步就无法将死。')]),
]
# Printed q.11 gives the same king evasion after both promoted/unpromoted 2四銀.
PROBLEMS[10]['wrong'][0] = ('1c2d+ 3c2b', PROBLEMS[10]['wrong'][0][1])
PROBLEMS[10]['wrong'][1] = ('1c2d 3c2b', PROBLEMS[10]['wrong'][1][1])

def text(body: str, pages: list[int]):
    return dict(kind='text', body=body, source_pages=pages)

def choice(prompt, options, answer, explanation, pages):
    return dict(kind='choice', prompt=prompt, options=options, answer=answer, explanation=explanation, source_pages=pages)

def build():
    lessons = [dict(id='intro-tsume-rules', title='詰将棋：五条专用规则', pages=[206,207],
                    summary='通过连续王手练习捕玉，并了解攻方、玉方和剩余持驹的约定。', steps=[
        text('詰将棋是连续向对方玉发动王手，直到将死的练习。多解题能训练看清棋子的控制与逃路。本章原书一共十二题，全部是一手詰：先手只用一手就要让玉方没有合法应手。', [206,207]),
        text('规则一：攻方每一步都必须王手。可以移动盘上的棋子，也可以打入持驹；只做“下一步能将死”的詰めろ或必至，不能代替当前的王手。', [207]),
        choice('这一手没有王手，只是准备下一手将死，可以算作詰将棋的进攻着法吗？', ['可以，只要威胁很强', '不可以，攻方必须连续王手'], 1, '本章练习要求立即王手，并不是一般对局中营造下一步威胁的题。', [207]),
        text('规则二、三：攻方用最短的手顺将死；玉方用能抵抗最久的手顺逃跑。不能把本来一手的题故意绕成三手，也不能让玉方故意选更快被将死的应手。', [207]),
        choice('某局面攻方能一手将死，却选了三手；玉方也放弃能坚持更久的应手。这样符合本章约定吗？', ['符合，反正最后都将死', '不符合：攻方取最短，玉方取最长'], 1, '攻方不能故意绕路，玉方也不能配合速败。', [207]),
        text('规则四：除盘上棋子与攻方列出的持驹之外，剩余棋子全部视为玉方持驹（玉不作持驹）。玉方能够用这些棋子合驹。教程已把这些持驹实际加入题目，不能把原图“剩余全部”误解成没有持驹。', [207]),
        choice('图上只写了攻方一枚香，玉方标着“剩余全部”。较远的香王手中间有空格时，应该怎样判断？', ['玉方没画持驹，所以不能挡', '还要检查玉方用剩余持驹合驹的办法'], 1, '本章第六、第八题就会用到玉方打步挡住长距离王手的应手。', [207]),
        text('规则五：不采用“无駄合”——局面实质不变、只为了多凑手数的无效合驹。有效地遮挡攻击、改变后续局面的合驹仍要计算。本章十二个正解都使玉方没有任何合法应手，包括有效合驹。', [207]),
        choice('某个合驹只增加手数，并不改变将死的实质结果；专用规则把它称为什么？', ['无駄合，不采用', '最长抵抗，所以一定采用'], 0, '最长抵抗的原则不能用来重复没有实际作用的合驹。', [207]),
    ])]
    validations = []
    for item in PROBLEMS:
        page = 208 + 2*((item['n']-1)//2)
        pages = [page, page+1]
        sfen = position(item['pieces'], item['hand'])
        board = shogi.Board(sfen)
        answer = shogi.Move.from_usi(item['answer'])
        assert answer in board.legal_moves, (item['n'], 'illegal answer')
        board.push(answer)
        assert board.is_checkmate(), (item['n'], 'not mate', [m.usi() for m in board.legal_moves])
        solutions = []
        original = shogi.Board(sfen)
        for move in list(original.legal_moves):
            original.push(move)
            if original.is_checkmate(): solutions.append(move.usi())
            original.pop()
        assert solutions == [item['answer']] or set(solutions) == {item['answer']}, (item['n'], 'alternative mates', solutions)
        steps = [dict(kind='move', prompt=f"原书第{item['n']}题：先手一步将死。提示：{item['hint']} 玉方持有剩余全部棋子，已列在上方。", position=sfen, accepted=[item['answer']], explanation=item['explanation'], source_pages=pages, diagram_ids=[f'hanyu-intro-p{page:03}-d{1 if item["n"]%2 else 2}'])]
        branches = []
        for line, explanation in item['wrong']:
            board = shogi.Board(sfen)
            names = []
            for offset, usi in enumerate(line.split()):
                move = shogi.Move.from_usi(usi)
                assert move in board.legal_moves, (item['n'], line, offset, 'illegal branch', board.sfen())
                names.append(notation(board, usi))
                board.push(move)
                if offset == 0:
                    assert not board.is_checkmate(), (item['n'], line, 'wrong branch is mate')
                    if len(line.split()) == 1:
                        assert not board.is_check(), (item['n'], line, 'expected non-check promotion')
            steps.append(dict(kind='sequence', prompt='错解复盘（不是本题正解）：请按 ' + ' → '.join(names) + ' 的顺序走一遍，观察玉方为什么还能应对。', position=sfen, moves=line.split(), student_side=0, explanation=explanation, source_pages=[page+1]))
            branches.append(dict(moves=line.split(), legal=True, first_move_not_mate=True))
        if item['n'] == 10:
            after = shogi.Board(sfen)
            after.push_usi(item['answer'])
            assert shogi.Move.from_usi('2c2d') not in after.legal_moves
            steps.append(choice('正解▲2四飞打后，为什么玉方不能用2三步吃飞？', ['因为步不能吃子', '因为步被1二角牵制，移动后会让自己的玉暴露在角线上'], 1, '步本来可以向前取子，但不能走出使己方玉被将军的着法。1二角—2三步—3四玉在同一条斜线上。', pages))
        if item['n'] == 11:
            steps.append(choice('▲2二银为什么必须“不成”？', ['升变后按金的走法，失去向后斜走的3三王手', '银在二段不能升变'], 0, '这里可以选择升变，但升变会失去完成任务所需的走法。正确答案是主动不成。', pages))
        steps.append(dict(kind='move', prompt=f"复习第{item['n']}题：看过错解后，再独立走出原书的一手詰正解。", position=sfen, accepted=[item['answer']], explanation=item['explanation'], source_pages=pages))
        lesson_id = f'intro-tsume-{item["n"]:02}'
        lessons.append(dict(id=lesson_id, title=f'一手詰第{item["n"]}题：{item["title"]}', pages=pages, summary='原图、正解、全部原书错解变化与再次练习。', steps=steps))
        validations.append(dict(number=item['n'], position=sfen, accepted=item['answer'], checkmate=True, unique_mate=True, defender_hands='all_remaining_non_king_material', source_pages=pages, source_images_visually_reviewed=True, branches=branches))
    coverage = []
    for page in range(206, 220):
        mapped = [lesson['id'] for lesson in lessons if page in lesson['pages']]
        coverage.append(dict(page=page, status='authored_verified', lesson_ids=mapped, note='原图、持驹、正文、正确答案及全部书中错误变化已人工核对并编写；一手詰和错解均经规则验证。' if page >= 208 else '章节导语与五条专用规则均已核对，含最长抵抗、剩余全持驹和无駄合。'))
    source = json.loads((ROOT / 'course_sources/hanyu-intro/index.json').read_text('utf-8'))
    data = dict(schema=1, book_id='hanyu-intro', source_sha256=source['source_sha256'], chapter_id='intro-tsume', chapter_title='第3章：詰将棋', source_pages=list(range(206,220)), lessons=lessons, coverage=coverage, validation=dict(engine='python-shogi', mates=len(validations), branches=sum(len(x['branches']) for x in validations), problems=validations))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2), 'utf-8')
    print(json.dumps(dict(lessons=len(lessons), steps=sum(len(x['steps']) for x in lessons), pages=len(coverage), mates=len(validations), branches=data['validation']['branches']), ensure_ascii=False))

if __name__ == '__main__': build()
