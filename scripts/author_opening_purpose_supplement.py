"""Independently checked opening-book source pages 17–22 (image indices).

Full board transcriptions checked visually against the private supplied scans.
This emits a supplement for the owning author; it never modifies the book.
"""
from pathlib import Path
from collections import Counter
import json
import shogi

ROOT = Path(__file__).resolve().parents[1]
LESSONS = []

def add(key, title, pages, summary, steps):
    for step in steps:
        step.setdefault('source_pages', pages)
    LESSONS.append(dict(id='opening-purpose-' + key, title=title, pages=pages,
                        summary=summary, steps=steps))

def text(body):
    return dict(kind='text', body=body)

def choice(prompt, options, answer, explanation):
    return dict(kind='choice', prompt=prompt, options=options,
                answer=answer, explanation=explanation)

def move(prompt, position, accepted, explanation):
    return dict(kind='move', prompt=prompt, position=position,
                accepted=accepted.split(), explanation=explanation)

def sequence(prompt, position, moves, explanation):
    return dict(kind='sequence', prompt=prompt, position=position,
                moves=moves.split(), student_side=0, explanation=explanation)

def targets(prompt, position, origin, squares, explanation):
    return dict(kind='targets', prompt=prompt, position=position,
                **{'from': origin}, targets=squares.split(), explanation=explanation)

def predecessor(sfen, origin, destination):
    board = shogi.Board(sfen)
    piece = board.piece_at(shogi.SQUARE_NAMES.index(destination))
    assert piece and board.piece_at(shogi.SQUARE_NAMES.index(origin)) is None
    board.remove_piece_at(shogi.SQUARE_NAMES.index(destination))
    board.set_piece_at(shogi.SQUARE_NAMES.index(origin), piece)
    board.turn = piece.color
    return board.sfen()

# All eight numbered full-board examples; examples 1 and 3 share a position.
SCATTERED = 'ln1gk1snl/1r1s2gb1/p1pppp1pp/6p2/1p6P/6P2/PPPPPPNP1/1B1G3R1/LNS1KGS1L b - 1'
ATTACK = 'ln1g1ksnl/1r4gb1/pppsppppp/3p5/6SP1/9/PPPPPPP1P/1B5R1/LNSGKG1NL b - 1'
DEFENSE = 'ln2k1snl/1r1sg1gb1/p1pp1p1pp/1p2p1p2/9/2PPP4/PP3PPPP/1BGSG2R1/LN1K2SNL b - 1'
ROOK_DEFENSE = 'lnsgkg1nl/7r1/pppppsbpp/5pp2/7P1/2P4S1/PP1PPPP1P/1B5R1/LNSGKG1NL b - 1'
FORK = 'ln4knl/1r1s2g2/pppp1g2p/4pppR1/8b/2P1P1P2/PPSP1P2P/2G6/LN2KG1NL b BSPsp 1'
OVERDEFENSE = 'l4gknl/3rg1sb1/p3pp1pp/1pp1s1p2/1n1p5/PSPPP4/1P1G1PPPP/1KGB3R1/LN4SNL b - 1'

add('plan', '每一步都要有一个目的', [17], '把眼前一步与后面的局面连接起来。', [
    text('“想赢”是整盘棋的方向，还需要每一步能落实的小目标。序盘争取让中盘容易进攻和防守，中盘则为终盘创造条件。开局时不必马上追着玉走。'),
    text('定迹像一条经过前人研究的路线。只记路线而不知道各步的用处，遇到对手走别的路就容易迷失。练习时先说清楚：这一步在准备进攻、保护哪里，还是改善同伴的联系？'),
    choice('准备走一步棋，哪种说明最有助于学习？', ['把金上来保护角头的步，预防对手交换飞先', '这枚子很久没动了，随便走一次', '只要向前，总会比较好'], 0,
           '具体到保护点和对手威胁，才便于下一手检查计划是否有效。')])

add('disconnected', '没有联系的端攻会失去香', [18], '重演原书第 1–2 图的四手交换。', [
    text('图中先手走了端步、桂和金，却没有让它们合作。后手的飞先步、金银与角形成了联系。现在看先手只凭一枚香发动端攻会怎样。'),
    sequence('双方轮流操作：一五步进一四，交换后用香吃回，再让后手香吃这枚香。', SCATTERED,
             '1e1d 1c1d 1i1d 1a1d',
             '两枚步交换以后，先手香独自冲到一四，被后手香吃掉。先手只有一枚步入手，后手却得到一枚步和一枚香；其他先手棋子没能参加。'),
    choice('这次端攻的问题是什么？', ['香脱离同伴，最后被吃后无人能吃回', '端线绝对不允许进攻', '香必须先成才能吃子'], 0,
           '问题在于棋子的配合。相同的端攻若有合适后援，结论可能不同。')])

add('connections', '看出后手各步的联系', [19], '原书第 3 图：开角道、守角头、照顾浮步和伸展飞先。', [
    text('回到前一课的起始局面。后手几步各有理由：三四步打开角道，三二金保护角头，六二银照顾浮着的步，八筋步则为飞准备活动空间。下面分别回到这些动作发生之前。'),
    move('把后手三三步推进一格，打开二二角的斜线。', predecessor(SCATTERED, '3c', '3d'), '3c3d',
         '三四步离开三三，角可以沿三三、四四等格发挥作用。'),
    move('后手用四一金走到三二，保护二三的角头步。', predecessor(SCATTERED, '4a', '3b'), '4a3b',
         '三二金斜向下一段控制二三；将来对方进攻角头，这枚步有金支持。'),
    move('后手把七一银走到六二，让银与步联系。', predecessor(SCATTERED, '7a', '6b'), '7a6b',
         '银来到六二，照顾原书圈出的七三和六三步，减少被白吃的机会。'),
    targets('在完成后的图中，选出原书圈出的七三、六三两枚步，它们都受到六二银保护。', SCATTERED, '6b', '7c 6c',
            '此题只选书中强调的两枚步，并非列举银的全部作用格。没有同伴保护的子称为“离れ駒”，容易成为攻击目标。'),
    move('后手的飞先步已经到八四，再推进一格。', predecessor(SCATTERED, '8d', '8e'), '8d8e',
         '八筋步伸展了飞的前方空间。开角道、保护弱点与推进飞先相互配合，构成连贯的布阵。')])

add('two-goals', '准备攻势，也安置好玉', [20], '用第 4–5 图区分序盘的进攻准备与围玉。', [
    text('第 4 图的先手飞、银和步集中在二筋，目标是准备中盘突破，并不是眼前已经将死。以下接着原图练习一次自然的步交换，体会银如何参加。'),
    sequence('从原图继续练习：二五步进二四，后手同步，先手用三五银吃回。', ATTACK, '2e2d 2c2d 3e2d',
             '银能跟上飞先的步交换，说明三枚子的方向一致。这是根据原图目的设计的操作练习，并不表示对手只能同步。'),
    text('第 5 图则把玉移到六九，七八金、六八银、五八金围在附近。金银共同照顾玉周围的区域，为以后战斗做准备；不要求它们每一枚都直接控制玉所在格。'),
    targets('观察六八银：选出它向前照顾的七七、六七、五七三个格子。', DEFENSE, '6h', '7g 6g 5g',
            '银保护玉前方的空间，金再与它配合。判断围玉应看整个防区，而不是只数玉旁边有多少子。'),
    text('将棋把纵向的一列叫“筋”，横向的一行叫“段”。从先手看，筋由右到左数一到九，段由上到下数一到九；例如二四就是二筋、第四段。'),
    choice('“二筋进攻”指棋盘上的哪个方向？', ['从先手看右边第二列的纵向线路', '从上往下第二排', '所有斜线'], 0,
           '筋是纵向列；二筋也是先手飞在初形中所在的纵线。')])

add('learn-failure', '计划失败，也能学到下一步', [21], '完整观察第 6–8 图的三种失衡。', [
    text('有目的地走棋，最初也会失败。第 6 图想用银突破二筋，却被后手把飞移到二二预先防住。先检查对方的防守，再决定是否继续原计划。'),
    targets('第 6 图：选出二二飞在同一条纵线上直接保护、挡住先手攻势的后手步。', ROOK_DEFENSE, '2b', '2c',
            '二三步后面有飞，银和步不能只按自己的愿望突进；下一步需要重新评估。'),
    text('第 7 图只顾攻击，把飞冲到二四，却被一五角同时瞄准飞和玉。角已经将军，先手必须先解除王手。双方持驹也按原图保留：先手角、银、步；后手银、步。'),
    targets('第 7 图：选出一五角同时攻击的先手飞和玉所在格。', FORK, '1e', '2d 5i',
            '一条斜线指向二四飞，另一条经过二六、三七、四八到五九玉，这是王手飞车。'),
    sequence('从第 7 图体验一种损失变化：玉逃到六九，后手角吃二四飞。', FORK, '5i6i 1e2d',
             '这两手是为了体验图中的威胁而设计的延续。玉安全以后，飞仍被吃；进攻前要检查大子与玉是否会受到双重攻击。'),
    text('第 8 图走了许多防守手，却没有形成攻势。左侧围玉投入了金银，右侧银仍在三九，飞先的步也尚未推进。防守完成后还需要组织进攻。'),
    targets('第 8 图：选出二八飞前方、目前挡住它纵向活动的己方步。', OVERDEFENSE, '2h', '2g',
            '二七步还在原位。此处用来观察尚未展开的进攻区域，并不是说每个局面都应立即推飞先步。'),
    choice('复盘这些失败时，最有帮助的做法是什么？', ['找出对方的反击，再调整自己的小目标', '放弃思考，继续随机走', '只走攻棋或只走守棋直到终局'], 0,
           '与“完全不知道为什么走”相比，带着目的的失败能告诉你计划缺少了哪一个条件。')])

add('small-step', '从保护角头开始', [22], '第 9 图：从初形走七八金，建立一个看得见的小目标。', [
    text('不必一开始就想出很长的变化。可以先练习“保护一个弱点”“给飞打开道路”等小目标，再观察对手如何应对。通过反复实践，逐渐把这些动作连成计划。'),
    move('从初形出发，把六九金走到七八，保护角头。', 'startpos', '6i7h',
         '七八金保护八七步，预防后手沿八筋交换飞先。这就是第 9 图：其余棋子仍在初形位置。'),
    targets('在第 9 图中，选择七八金保护的“角头步”。', predecessor(shogi.Board().sfen(), '7h', '6i').replace(' w ', ' b '),
            '7h', '8g', '角头是角正前方一格。八八角的角头是八七，角自身不能保护这枚正前方的步，需要金等同伴照顾。'),
    choice('学会七八金之后，下一盘最应观察什么？', ['它是否应对了对手的威胁，下一步还缺什么准备', '只要记住七八金，就不必看对手走法', '每一手都重复移动同一枚金'], 0,
           '一个小目标完成以后，再根据双方布阵选择下一个目标。带着问题反复下棋，会逐渐理解序盘各步的联系。')])

def validate():
    expected = Counter({shogi.PAWN: 18, shogi.LANCE: 4, shogi.KNIGHT: 4,
                        shogi.SILVER: 4, shogi.GOLD: 4, shogi.BISHOP: 2,
                        shogi.ROOK: 2, shogi.KING: 2})
    checks = 0
    for sfen in [SCATTERED, ATTACK, DEFENSE, ROOK_DEFENSE, FORK, OVERDEFENSE]:
        board = shogi.Board(sfen)
        stock = Counter(p.piece_type for p in (board.piece_at(s) for s in shogi.SQUARES) if p)
        for hand in board.pieces_in_hand:
            stock.update(hand)
        assert stock == expected, (sfen, stock - expected, expected - stock)
        checks += 1
    for lesson in LESSONS:
        for step in lesson['steps']:
            if step['kind'] not in ('move', 'sequence', 'targets'):
                continue
            board = shogi.Board() if step['position'] == 'startpos' else shogi.Board(step['position'])
            if step['kind'] == 'targets':
                origin = shogi.SQUARE_NAMES.index(step['from'])
                piece = board.piece_at(origin)
                attacks = board.attacks_from(piece.piece_type, origin, board.occupied, piece.color)
                for target in step['targets']:
                    assert attacks & (1 << shogi.SQUARE_NAMES.index(target)), (lesson['id'], target)
                    checks += 1
            else:
                moves = step['moves'] if step['kind'] == 'sequence' else step['accepted']
                for usi in moves:
                    parsed = shogi.Move.from_usi(usi)
                    assert board.is_legal(parsed), (lesson['id'], usi, board.sfen())
                    board.push(parsed)
                    checks += 1
    return checks

if __name__ == '__main__':
    checks = validate()
    result = dict(schema=1, source_book='hanyu-opening', replace_lesson_ids=['opening-purpose'],
                  lessons=LESSONS, coverage=[dict(page=p, status='authored_verified',
                  lesson_ids=[l['id'] for l in LESSONS if p in l['pages']],
                  note='独立逐页目视核对正文、栏注及第 1–9 图；完整棋盘与持驹核对总数，所有操作与作用格用独立规则验证。') for p in range(17, 23)],
                  checks=checks)
    output = ROOT / 'review/app/complete/tutorial-opening-purpose-supplement.json'
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(lessons=len(LESSONS), steps=sum(len(l['steps']) for l in LESSONS), checks=checks)))
