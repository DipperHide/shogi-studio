"""Complete, visually checked opening-book pages 25--28 (printed 24--27).

All twelve source diagrams (figures 6--17), text and footnotes inspected.
This replaces the earlier four-step overview, which incorrectly called the
rook's fork a bishop attack. No OCR guesses are used to certify diagrams.
"""
import json
from pathlib import Path
import shogi

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/complete/tutorial-opening-25-28-supplement.json'
VALIDATIONS = []
GUARD_CHECKS = []

BAD = 'ln1gkgsnl/1r5b1/p1psppppp/3p5/1p2P4/4S4/PPPP1PPPP/1BS4R1/LN1GKG1NL w - 1'
GOOD = 'ln1gkgsnl/1r5b1/p1pspp1pp/3p2p2/1p2P4/4S4/PPPP1PPPP/1BG1R4/LNS1KG1NL w - 1'
SCRUM = 'ln3ksnl/3rg1gb1/p3pp1p1/1ppps1p1p/7P1/2PPP4/PP1GSPP1P/1BGS3R1/LNK4NL w - 1'
ISHIDA = 'ln5nl/1r2ggkb1/2ps1s1p1/pp1ppp2p/2P3p2/P1RP1P2P/BPNSP1PP1/4G1SK1/L4G1NL w - 1'

def after(sfen, moves):
    board = shogi.Board(sfen)
    for usi in moves.split():
        move = shogi.Move.from_usi(usi)
        assert move in board.legal_moves, (sfen, moves, usi, 'illegal')
        board.push(move)
    return board.sfen()

def guards(sfen, target, expected, kinds=None):
    board = shogi.Board(sfen)
    square = shogi.SQUARE_NAMES.index(target)
    color = board.piece_at(square).color
    actual = sorted(shogi.SQUARE_NAMES[s] for s in board.attackers(color, square) if kinds is None or board.piece_at(s).symbol().upper() in kinds)
    assert actual == sorted(expected.split()), (target, actual, expected)
    GUARD_CHECKS.append(dict(target=target, defenders=actual, position=sfen, filter_piece_types=kinds))

def text(body, pages):
    return dict(kind='text', body=body, source_pages=pages)

def choice(prompt, options, answer, explanation, pages):
    return dict(kind='choice', prompt=prompt, options=options, answer=answer, explanation=explanation, source_pages=pages)

def sequence(prompt, position, moves, explanation, pages, diagram_numbers=None):
    end = after(position, moves)
    VALIDATIONS.append(dict(kind='sequence', moves=moves.split(), position=position, final_position=end, legal=True))
    step = dict(kind='sequence', prompt=prompt, position=position, moves=moves.split(), student_side=0, explanation=explanation, source_pages=pages)
    if diagram_numbers: step['source_figures'] = diagram_numbers
    return step

def move(prompt, position, accepted, explanation, pages, diagram_numbers=None):
    end = after(position, accepted)
    VALIDATIONS.append(dict(kind='move', moves=[accepted], position=position, final_position=end, legal=True))
    step = dict(kind='move', prompt=prompt, position=position, accepted=[accepted], explanation=explanation, source_pages=pages)
    if diagram_numbers: step['source_figures'] = diagram_numbers
    return step

def targets(prompt, position, origin, squares, explanation, pages, diagram_numbers=None):
    step = dict(kind='targets', prompt=prompt, position=position, **{'from':origin}, targets=squares.split(), explanation=explanation, source_pages=pages)
    if diagram_numbers: step['source_figures'] = diagram_numbers
    return step

def build():
    for label, sfen in [('fig6', BAD), ('fig11', GOOD), ('fig12', SCRUM), ('fig15', ISHIDA)]:
        board = shogi.Board(sfen)
        assert sum(board.piece_at(s) is not None for s in range(81)) == 40, (label, 'material count')
        assert not board.is_check(), (label, 'unexpected check')
        assert all(not hand for hand in board.pieces_in_hand), (label, 'source has no hands')

    fork = after(BAD, '8e8f 8g8f 8b8f')
    after_scrum = after(SCRUM, '6d6e 6f6e 5d6e')
    after_edge = after(ISHIDA, '9d9e 9f9e 9a9e')
    figures = {
        6: BAD,
        7: after(BAD, '8e8f'),
        8: fork,
        9: after(fork, 'P*8g 8f5f'),
        10: after(fork, '2h5h 8f8h+'),
        11: GOOD,
        12: SCRUM,
        13: after_scrum,
        14: after(after_scrum, 'P*6f'),
        15: ISHIDA,
        16: after_edge,
        17: after(after_edge, 'P*9f'),
    }
    # Direct protection is checked geometrically, including friendly occupied squares.
    guards(BAD, '5f', '')
    guards(BAD, '8h', '')
    guards(GOOD, '5f', '5h')
    guards(GOOD, '8h', '7h 7i')
    guards(SCRUM, '6g', '7h 6h')
    guards(SCRUM, '5g', '6g 6h')
    guards(SCRUM, '6h', '7h 6g 5g', 'GS')
    guards(figures[14], '6f', '6g 5g 8h')
    guards(ISHIDA, '7f', '6g')
    guards(ISHIDA, '9i', '')
    for protected, protector in [('7g','7f'),('7e','7f'),('9f','7f'),('6f','7f'),('6g','5h'),('5h','4i'),('4i','3h'),('3h','2h')]:
        board = shogi.Board(ISHIDA)
        assert shogi.SQUARE_NAMES.index(protector) in board.attackers(shogi.BLACK, shogi.SQUARE_NAMES.index(protected)), (protected, protector)
    board = shogi.Board(fork)
    assert all(shogi.SQUARE_NAMES.index('8f') in board.attackers(shogi.WHITE, shogi.SQUARE_NAMES.index(target)) for target in ['5f','8h'])

    lessons = [dict(
        id='opening-linked-shape', title='两枚浮驹怎样被飞车双攻', pages=[25,26],
        summary='完整复盘第6–11图：中央银与角失去保护、两条失子分支，以及先连好飞银金再进攻的改善形。',
        steps=[
            text('第6图中，先手刚走▲5六银，想从中央进攻，但这枚银没有同伴保护。8八角虽然旁边有银、桂、香和步，也没有一枚同伴能在它被取走后立即吃回。站得近，不等于实际保护。', [25]),
            choice('8八角周围棋子不少，为什么书中仍称它是浮驹？', ['没有同伴能在角被取走后直接吃回', '只有飞车能够保护角', '角一到8八就不能被保护'], 0, '判断“ヒモ”要看具体走法。第6图的7八银不能横走到8八，旁边其他棋子也没有直接保护这枚角。', [25]),
            sequence('第6→8图：先走△8六步，再▲同歩、△同飛。双方都由你操作，观察8六飞最后同时瞄准哪里。', BAD, '8e8f 8g8f 8b8f', '△8六步威胁下一步到8七成步，原书因此让先手交换。双方各得到一枚步，后手飞车到8六，形成角银双攻。发起双攻的是飞车。', [25], [6,7,8]),
            targets('第8图：选出8六飞现在同时攻击的两枚先手棋子。这题选受攻击的棋子，不是飞车的全部可走格。', fork, '8f', '5f 8h', '8六飞沿横线瞄准5六银，又沿八筋瞄准8八角；两枚都没有同伴保护，所以先手陷入两难。', [25,26], [8]),
            sequence('保角分支：▲8七歩打 → △5六飛 → ▲5八金右。先挡住八筋，再看银怎样丢掉，以及为什么需要右金到5八挡住王手。', fork, 'P*8g 8f5f 4i5h', '第9图中，后手飞车免费吃掉5六银。先手可按正文补▲5八金右继续抵抗，但无代价丢银已经是严重损失。这里“右金”是从4九走到5八的金。', [26], [8,9]),
            sequence('保银分支：▲5八飛 → △8八飛成。先把飞车移到五筋保护银，再看后手怎样沿另一条线取角。', fork, '2h5h 8f8h+', '第10图中，银虽然有了飞车保护，8八角却被免费吃掉，后手还做出了龙。原书把这形势评价为先手已很难取胜；两条分支共同说明事先连接棋子的重要性。', [26], [8,10]),
            text('原书的改善办法是第11图：银要挺进五筋，就先让飞车来到五筋支援；左侧也采用7八金、7九银的形状，而不是把银放在7八。下面从这张新的布阵图重新检查保护关系。', [26]),
            targets('第11图：高亮5六银。选出能直接保护它、在它被飞车吃掉后可以吃回的先手棋子。', GOOD, '5f', '5h', '5八飞与5六银之间的5七是空格，所以飞车能直接支援银。', [26], [11]),
            targets('仍是第11图：高亮8八角。选出直接保护这枚角的全部先手棋子。', GOOD, '8h', '7h 7i', '7八金能横走到8八，7九银也能斜前走到8八。角不再是原先那枚没有保护的浮驹。', [26], [11]),
            sequence('按第11图的正确结构应对同样的交换：△8六歩 → ▲同歩 → △同飛 → ▲8七歩打。', GOOD, '8e8f 8g8f 8b8f P*8g', '8七步挡住八筋，同时五筋的飞银仍保持联系。先手现在能守住角这一侧，不会像原来的分支那样被免费吃掉5六银。', [26], [11]),
            text('本页小注：“振る”指把飞车从最初所在的筋移向自己的左侧。先手的飞最初在二筋，移到五至八筋，就是本页所说的把飞车“振”过去。', [26]),
            choice('这两个结构的核心差别是什么？', ['把进攻银、角与后方棋子连好，再发起进攻', '只要棋子都往前走，就不会被双攻', '任何时候飞车都必须放在五筋'], 0, '本例是用实际的保护关系解决弱点，并不是规定所有战法都必须走五筋。', [25,26]),
        ]), dict(
        id='opening-gold-silver-scrum', title='金银互保：接住右四间飞车的冲击', pages=[27],
        summary='第12–14图的三组保护关系、六筋步交换和反打6六步。',
        steps=[
            text('第12图中，先手按矢仓战法组阵，后手采用右四间飞车。战法细节后面会讲，这里先看金银怎样彼此保护。原书把这种相互牵连的紧密结构比作橄榄球的“scrum”。', [27]),
            targets('第12图：高亮6七金。请选出能够直接保护这枚金的两枚先手棋子；选择的是保护者所在格。', SCRUM, '6g', '7h 6h', '6七金受到7八金与6八银的保护。', [27], [12]),
            targets('高亮5七银。选出直接保护它的全部先手棋子。', SCRUM, '5g', '6g 6h', '5七银受到6七金与6八银的保护。', [27], [12]),
            targets('高亮6八银。只选直接保护它的先手金、银，不选其他种类的棋子。原书重点指出哪三枚金银？', SCRUM, '6h', '7h 6g 5g', '这组金银互保关系中的三枚是7八金、6七金和5七银；它们都能走到6八。', [27], [12]),
            sequence('第12→13图：后手冲击六筋。请复盘△6五歩 → ▲同歩 → △同銀。', SCRUM, '6d6e 6f6e 5d6e', '后手把飞车所在六筋的步交换掉，再用银来到6五。先手虽然面对集中进攻，金银之间的联系仍然完整。双方各得一枚步。', [27], [12,13]),
            move('第13→14图：先手用刚得到的持驹步赶走6五银。把步打到合适的格子。', after_scrum, 'P*6f', '▲6六步打直接攻击前面的6五银。这枚步同时受到6七金与5七银的保护，所以不是随便送给对手的浮步。', [27], [13,14]),
            targets('第14图：高亮刚打下的6六步。选出直接保护它的全部先手棋子，也要检查后方角的斜线。', figures[14], '6f', '6g 5g 8h', '6七金能直前保护6六，5七银能斜前保护6六，8八角也沿7七空格照到6六。金银结构还连着后方的角，能够接住对方的突破。', [27], [14]),
            choice('为什么书中的金银结构经受住这次冲击？', ['金银彼此保护，还能保护主动赶银的6六步', '因为任何打步都不能被吃', '因为右四间飞车没有攻击力'], 0, '原书明确说右四间飞车很有破坏力；这一例可靠的是己方金银结构，并不是对手的战法没有威胁。', [27]),
        ]), dict(
        id='opening-ishida-connected-pieces', title='石田流：从飞车到玉的保护链', pages=[28],
        summary='第15–17图的四枚受保护棋子、九筋应对、银金玉的连续联系与振飞车小注。',
        steps=[
            text('第15图是先手石田流。原书把它列为振飞车的理想形之一，其中一个理由就是棋子之间的联系好。先看7六飞怎样照顾周围棋子，再看谁保护飞车。', [28]),
            targets('第15图：选出7六飞直接保护的全部先手棋子。这里只选有先手棋子的格子，不选空格。', ISHIDA, '7f', '7g 7e 9f 6f', '飞车向下保护7七桂，向上保护7五步，向左保护9六步，向右保护6六步。', [28], [15]),
            targets('高亮7六飞：选出直接保护这枚飞车的先手棋子。', ISHIDA, '7f', '6g', '6七银能斜前走到7六，因此飞车本身也有同伴保护。', [28], [15]),
            text('把这条联系向后继续看：6七银由5八金保护，5八金由4九金保护，4九金由3八银保护，3八银又由2八玉保护。攻守棋子不是各自孤立地站着，而是从飞车一路连到玉。原书另外提醒，九筋香仍是需要注意的浮驹。', [28]),
            sequence('第15→16图：后手从九筋攻来，复盘△9五歩 → ▲同歩 → △同香。', ISHIDA, '9d9e 9f9e 9a9e', '九筋的步交换后，后手香来到9五，双方各得到一枚步。先手可以依靠7六飞对9六的控制来回应。', [28], [15,16]),
            move('第16→17图：用先手持驹中的步挡住并攻击9五香。', after_edge, 'P*9f', '▲9六步打有7六飞横向保护，堵住九筋并攻击眼前的香。保护关系让这枚防守步站得住。', [28], [16,17]),
            text('本页小注：先手把飞车振到五至八筋，后手把飞车振到五至二筋来作战，称为“振飞车战法”。常见例子包括中飞车、四间飞车、三间飞车与向飞车。这里的左右按各自面对棋盘的方向理解。', [28]),
            choice('原书在这一节给出的保护结构比较是什么？', ['没有保护的形差；有保护的形好；彼此保护的形更好', '单独站立总比相互保护强', '保护只会妨碍进攻'], 0, '保持“ヒモ”的意识，是为了减少棋子被对手白吃的机会。检验时仍要看具体棋子的实际走法。', [28]),
        ])]
    coverage = []
    for page in range(25,29):
        coverage.append(dict(page=page, status='authored_verified', lesson_ids=[x['id'] for x in lessons if page in x['pages']], note='全部正文、图6–17对应本页图示、原书分支和小注已人工视觉核对并转为互动；序列与保护关系已规则验证。'))
    index = json.loads((ROOT / 'course_sources/hanyu-opening/index.json').read_text('utf-8'))
    data = dict(schema=1, book_id='hanyu-opening', source_sha256=index['source_sha256'], source_pages=list(range(25,29)), replacement_lesson_ids=['opening-linked-shape'], lessons=lessons, coverage=coverage, validation=dict(engine='python-shogi', visual_source_pages=[25,26,27,28], source_figures=[dict(number=n, page=25+(n-6)//3, position=sfen, hands_visually_reviewed=True) for n,sfen in figures.items()], sequences=VALIDATIONS, direct_protection=GUARD_CHECKS))
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2), 'utf-8')
    print(json.dumps(dict(lessons=len(lessons), steps=sum(len(x['steps']) for x in lessons), pages=4, source_diagrams=len(figures), legal_sequences=len(VALIDATIONS), direct_protection_checks=len(GUARD_CHECKS)), ensure_ascii=False))

if __name__ == '__main__': build()
