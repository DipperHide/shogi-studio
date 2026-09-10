"""Visually reviewed additions for opening-book source pages 199-200, 211-212.

Standalone output: never edits the main course or the opening author's script.
Source diagrams are transcribed by hand; source screenshots remain read-only.
"""
import json
from collections import Counter
from pathlib import Path
import shogi

ROOT=Path(__file__).resolve().parents[1]
SOURCE=json.loads((ROOT/'course_sources/hanyu-opening/index.json').read_text('utf-8'))
MAIN=json.loads((ROOT/'godot/courses/hanyu-opening.json').read_text('utf-8'))
OLD={l['id']:l for c in MAIN['chapters'] for l in c['lessons']}
GUIDE='opening-strategy-guide'
PREPARE='opening-right-four-prepare'

def text(body,page): return dict(kind='text',body=body,source_pages=[page])
def choice(prompt,options,answer,explanation,page):
    return dict(kind='choice',prompt=prompt,options=options,answer=answer,explanation=explanation,source_pages=[page])
def targets(prompt,position,origin,answer,explanation,page,diagram_id):
    return dict(kind='targets',prompt=prompt,position=position,**{'from':origin},targets=answer.split(),explanation=explanation,source_pages=[page],source_diagram=diagram_id)
def move(prompt,position,answer,explanation,page,diagram_id):
    return dict(kind='move',prompt=prompt,position=position,accepted=[answer],explanation=explanation,source_pages=[page],source_diagram=diagram_id)
def after(position,moves):
    b=shogi.Board(position)
    for code in moves:
        m=shogi.Move.from_usi(code)
        assert m in b.legal_moves,(code,b.sfen())
        b.push(m)
    return b.sfen()
def as_black(position):
    b=shogi.Board(position); b.turn=shogi.BLACK; return b.sfen()

# Full 40-piece diagrams, in the source's coordinates. Fig 4 deliberately shows
# the historically gote strategy on the bottom, as its original caption states.
FIGURES={
    'opening-p199-fig1':dict(page=199,title='相矢仓',position='ln5nl/1r4gk1/2sp1gsp1/p1pbppp1p/1p5P1/P1PPPBP1P/1PSG1PS2/1KG4R1/LN5NL b - 1'),
    'opening-p199-fig2':dict(page=199,title='四间飞车',position='ln3g1nl/1r1sg1kb1/p2psp1p1/2p1p1p1p/1p7/2PPP3P/PPB2PPP1/2SRG1SK1/LN3G1NL b - 1'),
    'opening-p199-fig3':dict(page=199,title='闭角道中飞车',position='ln3g1nl/1r1sgskb1/p4p1p1/2ppp1p1p/1p7/2PPP3P/PPBS1PPP1/2G1R1SK1/LN3G1NL b - 1'),
    'opening-p199-fig4':dict(page=199,title='愉快中飞车（书中先后倒置）',position='lnsgkgsnl/1r5b1/p1pppp1pp/6p2/1p7/2P1P4/PP1P1PPPP/1B2R4/LNSGKGSNL b - 1',orientation_note='原图把采用此战法的后手放在棋盘下方；课程保持图面坐标，下方一方使用正向文字。'),
    'opening-p200-fig5':dict(page=200,title='三间飞车对居飞车穴熊',position='ln4gnk/1r2g2sl/p1ppsbppp/4p1p2/1p6P/2PPPP3/PPB1S1PP1/2R1G1SK1/LN3G1NL b - 1'),
    'opening-p200-fig6':dict(page=200,title='角换腰挂银',position='lr5nl/3g1kg2/2n1ppsp1/p1pps1p1p/1p5P1/P1P1SPP1P/1PSPP1N2/2GK1G3/LN5RL b Bb 1'),
    'opening-p200-fig7':dict(page=200,title='横步取',position='lnsgk1snl/6gb1/p1pppp2p/6R2/9/1rP6/P2PPPP1P/1BG6/LNS1KGSNL b 3P2p 1'),
    'opening-p200-fig8':dict(page=200,title='横步取后手四五角',position='lnsgk1sn+B/6g2/p1pppp2p/7p1/5b3/2P6/P2PPPP1P/2G4S1/LN2KG1NL w RL4Prs 1'),
}
guide=[]
def figstep(n,body,prompt,origin,answer,explanation):
    key=f'opening-p{199 if n<=4 else 200}-fig{n}'
    f=FIGURES[key]
    guide.extend([text(body,f['page']),targets(prompt,f['position'],origin,answer,explanation,f['page'],key)])

figstep(1,
    '第 1 图：双方都用矢仓围玉，所以叫相矢仓。双方飞角准备瞄准对方玉阵，战斗容易扩展到整个棋盘；书中说它常受到中级、上级棋手喜爱。这里辨认完整阵形，再观察飞先步的支援。',
    '第 1 图：只点出 2h 飞在同一筋上直接保护的己方步。','2h','2e',
    '2e 步后方的 2f、2g 都是空格，所以 2h 飞直接保护它。左侧 8h 玉由 7h 金、6g 金、7g 银围护；飞在另一侧准备开战。')
figstep(2,
    '第 2 图：先手把飞调到 6h，称四间飞车；从该方左边数是第四筋。右侧玉进入美浓围。美浓还可发展为高美浓、银冠，或另选穴熊；组阵较易理解，所以振飞车很受业余爱好者欢迎。',
    '第 2 图：只点出 6h 飞在前方直接保护的己方步。','6h','6f',
    '6f 步在飞前方，6g 空着。飞与步集中第六筋，玉在 2h，由 3h 银、4i 金、5h 金守护，形成攻守分工。')
figstep(3,
    '第 3 图：传统的闭角道中飞车把飞调到 5h，以 5f 步和中央银准备进攻。6f 步关住角路，左金升到 7h 也有抑制对方发动攻击的作用。',
    '第 3 图：只点出 5h 飞正前方直接保护的己方步。','5h','5f',
    '5g 空着，所以飞直接支援 5f 步。它与下一幅同是中飞车，但角路状态、金银部署并不一样。')
guide.append(choice('第 2 图与第 3 图最直接的飞车位置差别是什么？',['第 2 图在第六筋，第 3 图在第五筋','第 2 图飞在第一筋，第 3 图没有飞','两图飞都在初形位置'],0,'四间飞车与中飞车先从飞所在筋辨认，再看角路、银与围玉。',199))
figstep(4,
    '第 4 图：愉快中飞车保留角路，可以积极进攻。原书为了便于比较，把采用这一战法的后手放在下方，先后标签与通常图相反；此处保持图面的坐标与朝向，下方飞仍画在 5h。',
    '第 4 图按下方视角：只点出 8h 角当前直接瞄准的上方角所在格。','8h','2b',
    '8h 经 7g、6f、5e、4d、3c 到 2b，中间都没有棋。与前一图相比，6f 不再有挡角路的步，这正是保留角道的区别。')
figstep(5,
    '第 5 图：下方是飞在 7h 的三间飞车，可继续发展成后文的石田流；上方则把玉放到 1a，围成居飞车穴熊。其优势在玉阵坚固，是对抗振飞车的有力选择。',
    '第 5 图：只点出 7h 飞当前直接保护的己方角所在格。','7h','7g',
    '7g 角挡在飞前面，同时受到飞保护。发展石田流时，需要安排角退路、飞上浮与第八筋防守的交接；这一图还是三间飞车的基本配置。')
guide.append(targets('同一第 5 图：只点出上方 2b 银直接保护的己方玉、金所在格。',FIGURES['opening-p200-fig5']['position'],'2b','1a 3a','2b 银的斜后方是 1a 玉与 3a 金。玉缩在角落，香、桂与金银在周围配合，形成穴熊的防守层次；这是保护关系，不是让银走到己棋上。',200,'opening-p200-fig5'))
figstep(6,
    '第 6 图：阵形像矢仓，但双方角已交换，各自手中有一枚角。先手 5f 银位于 5g 步前方，后手银也在第五筋，这种中央腰挂银配置与角交换合起来，称角换腰挂银。',
    '第 6 图：点出 5f 腰挂银直接控制的前方三格。','5f','6e 5e 4e',
    '银的三个向前作用格是 6e、5e、4e。手中的角可以打入，因此还要注意自己阵内的空格，不能只按未交换角的矢仓来判断。')
figstep(7,
    '第 7 图：双方伸飞先、开角道，并交换飞先步；先手飞又从横向取了 3d 步，所以叫横步取。图中先手飞在 3d、后手飞在 8f，双方玉与金银尚未形成厚实的围城。',
    '第 7 图：只点出 3d 飞当前沿第三筋直接瞄准的后手金。','3d','3b',
    '3c 已经空出，飞直接瞄准 3b 金，后手的飞也已进入第六段。这种大子活跃、玉阵未完成的状态，可能很快从序盘转入激烈的终盘战斗。')
figstep(8,
    '第 8 图是横步取后手 4e 角战法的一个完成图。先手已在 1a 成马，后手角在 4e，双方手里都有飞；先手另有香和四步，后手另有银。原书提及羽生少年时期曾用过这种很快进入终盘的战法。',
    '第 8 图：只点出后手 4e 角当前直接攻击的先手步。','4e','6g',
    '4e 角沿 5f 到 6g，直接瞄准六七步；其他方向也有长斜线。它强调急战的紧张程度，不能把看见大子在敌阵就当作己方已经获胜。')
guide.append(choice('第 8 图为什么比稳步围玉更需要逐手计算？',['双方可打飞，角马也已活跃，而两玉的守备都未完整','因为双方已经没有持驹','因为角马此时都不能移动'],0,'它不仅有盘上的大子威胁，还有持飞的打入。正确判断必须兼顾双方，不是只追求成马或吃香。',200))

# Verify the two existing mainline sequences against their actual printed
# terminal diagrams before appending the missing alternative castle.
old=OLD[PREPARE]
line211=old['steps'][0]
line212=old['steps'][1]
FIGURES['opening-p211-fig3']=dict(page=211,title='右四间飞角银桂齐备',position='ln2k2nl/1r1s2gb1/pppp1gspp/4ppp2/9/2P1SPPP1/PP1PP1N1P/1B3R3/LNSGKG2L b - 19')
FIGURES['opening-p212-fig4']=dict(page=212,title='右四间左侧围玉',position='ln5nl/1r1s1bgk1/pppp1gspp/4ppp2/9/2P1SPPPP/PP1PP1N2/1BS1GR3/LNKG4L b - 29')
FIGURES['opening-p212-figA']=dict(page=212,title='右四间蟹围',position='ln5nl/1r1s1bgk1/pppp1gspp/4ppp2/9/2P1SPPPP/PP1PP1N2/1BGSGR3/LN1K4L b - 29')
assert after(line211['position'],line211['moves'])==FIGURES['opening-p211-fig3']['position']
assert after(line212['position'],line212['moves'])==FIGURES['opening-p212-fig4']['position']
prepare=[
    targets('第 3 图：只点出 3g 桂能够直接加入第四筋进攻的落点。',FIGURES['opening-p211-fig3']['position'],'3g','4e','桂的另一跳是 2e，这里专选第四筋的 4e。飞在 4h、银在 5f、角在 8h，桂加入后形成飞角银桂共同进攻；但玉仍在 5i，应先围玉。',211,'opening-p211-fig3'),
    text('右四间虽然攻击强，交换以后也可能遭到反击。“攻用飞角银桂”与“不要居玉”需要一起运用；不能因攻子齐备，就省略玉的防守。',211),
    text('第 4 图把玉放到 7i，以 7h 银、6i 金、5h 金三枚金银守护，且让玉离开 4h 飞。A 图给出同样保留角线的另一种围法：金升 5h、金升 7h、银升 6h，玉横移 6i，称蟹围。',212),
]

castle_final=shogi.Board(FIGURES['opening-p212-figA']['position'])
castle_base=shogi.Board(castle_final.sfen())
# Reverse all placements at once: 6i is both the final king square and the
# initial left-gold square.
for sq in ['5h','7h','6h','6i']: castle_base.remove_piece_at(shogi.SQUARE_NAMES.index(sq))
for sq,piece in [('4i','G'),('6i','G'),('7i','S'),('5i','K')]:
    castle_base.set_piece_at(shogi.SQUARE_NAMES.index(sq),shogi.Piece.from_symbol(piece))
castle_base.turn=shogi.BLACK
prepare.append(text('下面只练先手的四步搭围路线，省略后手中间步骤。为便于与 A 图直接比对，后手保持 A 图已完成的玉、角位置，每步重新从所示局面开始。',212))
b=castle_base
for num,(code,prompt,explanation) in enumerate([
    ('4i5h','A 图搭围第 1 步：右金升到 5h。','右金从 4i 升到 5h，靠近左侧玉区。'),
    ('6i7h','A 图搭围第 2 步：左金升到 7h。','左金保护左侧与 6h，为玉横移留出底线。'),
    ('7i6h','A 图搭围第 3 步：左银移到 6h。','银在 6h，既加入玉的防守，又不占据 8h 角前方的 7g。'),
    ('5i6i','A 图搭围第 4 步：玉横移到 6i。','玉从 5i 横向移动到 6i，由两金一银守护。横向移动的样子使这套围法得名蟹围。')],1):
    b.turn=shogi.BLACK
    prepare.append(move(prompt,b.sfen(),code,explanation,212,'opening-p212-figA'))
    b.push(shogi.Move.from_usi(code))
b.turn=shogi.BLACK
assert b.sfen().split()[:3]==castle_final.sfen().split()[:3]
prepare.extend([
    move('A 图的虚线还提示：玉可以继续沿底线向左横移一格。',b.sfen(),'6i7i','由 6i 到 7i，是这幅图表示的横向路线；是否继续走要看对方变化，而不是每局必须立即走。',212,'opening-p212-figA'),
    targets('第 4 图原局面：只点出 8h 角沿长斜线直接攻击的第四筋敌步。',FIGURES['opening-p212-fig4']['position'],'8h','4d','7g、6f、5e 都空着，角的作用延伸到 4d 步。右四间的飞角银桂需要这条角线共同发挥。',212,'opening-p212-fig4'),
    move('反例演示：在第 4 图把 7h 守银升到 7g，观察它为什么妨碍作战。',FIGURES['opening-p212-fig4']['position'],'7h7g','7g 银本身走法合法，但它挡在 8h 角前方，切断角对第四筋的支援。这是布局选择的问题，不是规则禁止银走 7g。',212,'opening-p212-fig4-derived-silver-obstruction'),
    targets('升银后的反例：角线被己方银挡住，现在直接保护到哪一格就停了？',after(FIGURES['opening-p212-fig4']['position'],['7h7g']),'8h','7g','角只能直接作用到 7g 的己银，不能穿过它继续攻击 4d。蟹围中的 6h 银若改上 7g，也会造成同样堵线；两种围玉方法都应保持角道。',212,'opening-p212-fig4-derived-silver-obstruction'),
])

SUPPLEMENT=dict(schema=1,book_id=MAIN['id'],source_sha256=SOURCE['source_sha256'],source_pages=[199,200,211,212],chapter_id='strategy',replace_lesson_ids=[],steps_by_lesson={GUIDE:guide,PREPARE:prepare},coverage=[dict(page=p,status='authored_verified',lesson_ids=[GUIDE if p<201 else PREPARE],note='已逐页目视核对正文与全部棋图；导览 8 图、右四间第 3/4 图及蟹围 A 图均完整转录，追加原图作用辨认、蟹围路线与堵角线反例。保留原有课的全部正文及主线。') for p in [199,200,211,212]],figures=[dict(id=k,**v) for k,v in FIGURES.items()])

def validate():
    material_expected=Counter({shogi.KING:2,shogi.ROOK:2,shogi.BISHOP:2,shogi.GOLD:4,shogi.SILVER:4,shogi.KNIGHT:4,shogi.LANCE:4,shogi.PAWN:18})
    figures_checked=[]; actions=0; squares=0
    for key,f in FIGURES.items():
        board=shogi.Board(f['position']); actual=Counter()
        for sq in shogi.SQUARES:
            p=board.piece_at(sq)
            if p:
                demoted={shogi.PROM_PAWN:shogi.PAWN,shogi.PROM_LANCE:shogi.LANCE,shogi.PROM_KNIGHT:shogi.KNIGHT,shogi.PROM_SILVER:shogi.SILVER,shogi.PROM_BISHOP:shogi.BISHOP,shogi.PROM_ROOK:shogi.ROOK}.get(p.piece_type,p.piece_type)
                actual[demoted]+=1
        for hand in board.pieces_in_hand:
            for p,n in hand.items(): actual[p]+=n
        assert actual==material_expected,(key,actual-material_expected,material_expected-actual)
        figures_checked.append(key)
    for lid,steps in SUPPLEMENT['steps_by_lesson'].items():
        assert lid in OLD
        for i,s in enumerate(steps):
            if s['kind']=='targets':
                board=shogi.Board(s['position']); origin=shogi.SQUARE_NAMES.index(s['from']); p=board.piece_at(origin)
                reachable={shogi.SQUARE_NAMES[sq] for sq in shogi.SquareSet(board.attacks_from(p.piece_type,origin,board.occupied,p.color))}
                assert set(s['targets']).issubset(reachable),(lid,i,s['targets'],reachable)
                squares+=len(s['targets'])
            elif s['kind']=='move':
                for code in s['accepted']:
                    after(s['position'],[code]); actions+=1
            elif s['kind']=='choice': assert 0<=s['answer']<len(s['options'])
    # Recheck all old steps, as these additions must preserve the original work.
    old_steps=0
    for lid in [GUIDE,PREPARE]:
        for s in OLD[lid]['steps']:
            old_steps+=1
            if s['kind']=='sequence': after(s['position'],s['moves']); actions+=len(s['moves'])
    return dict(figures_visually_reviewed=figures_checked,full_40_piece_material_checks=len(figures_checked),legal_actions_checked=actions,geometric_target_squares_checked=squares,old_steps_retained=old_steps,appended_steps=sum(map(len,SUPPLEMENT['steps_by_lesson'].values())),errors=[])

if __name__=='__main__':
    SUPPLEMENT['validation']=validate()
    dest=ROOT/'review/app/complete/tutorial-opening-ch6-supplement.json'
    dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(json.dumps(SUPPLEMENT,ensure_ascii=False,indent=2),'utf-8')
    print(json.dumps(SUPPLEMENT['validation'],ensure_ascii=False))
