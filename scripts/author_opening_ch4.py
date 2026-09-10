"""Complete the 21 remaining draft pages of opening chapter 4.

Source images were read in full; inverted promoted pieces and hands were also
inspected in rotated crops. This file only writes a mergeable supplement.
"""
import copy
import json
from pathlib import Path
import shogi

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review/app/complete/tutorial-opening-ch4-supplement.json'
PAGES = [139,140,141,142,147,148,149,150,154,155,156,159,160,161,162,163,164,167,168,169,170]
FIGURES, ACTIONS, CHECKS = [], [], []

def pos(pieces, hand='-', turn='b'):
    b = shogi.Board('9/9/9/9/9/9/9/9/9 '+turn+' '+hand+' 1')
    for item in pieces.split():
        sq, piece = item[:2], item[2:]
        assert b.piece_at(shogi.SQUARE_NAMES.index(sq)) is None, item
        b.set_piece_at(shogi.SQUARE_NAMES.index(sq), shogi.Piece.from_symbol(piece))
    return b.sfen()

def board(sfen):
    return shogi.Board() if sfen == 'startpos' else shogi.Board(sfen)

def after(sfen, moves):
    b = board(sfen)
    for usi in moves.split():
        m = shogi.Move.from_usi(usi)
        assert m in b.legal_moves, (usi, moves, b.sfen())
        b.push(m)
    return b.sfen()

def edit(sfen, changes='', hand=None, turn=None):
    b = board(sfen)
    for item in changes.split():
        sq, piece = shogi.SQUARE_NAMES.index(item[:2]), item[2:]
        b.remove_piece_at(sq)
        if piece != '-': b.set_piece_at(sq, shogi.Piece.from_symbol(piece))
    fields = b.sfen().split()
    if turn is not None: fields[1] = turn
    if hand is not None: fields[2] = hand
    return ' '.join(fields)

def fig(page, number, sfen):
    key = f'{page}:{number}'
    FIGURES.append(dict(id=key,page=page,number=number,position=sfen,hands_visually_reviewed=True))
    return sfen

def t(body, pages, **kw):
    return dict(kind='text',body=body,source_pages=pages,**kw)

def q(prompt, options, answer, explanation, pages, **kw):
    return dict(kind='choice',prompt=prompt,options=options,answer=answer,explanation=explanation,source_pages=pages,**kw)

def seq(prompt, sfen, moves, explanation, pages, **kw):
    result = after(sfen, moves)
    ACTIONS.append(dict(position=sfen,moves=moves.split(),final_position=result,legal=True))
    return dict(kind='sequence',prompt=prompt,position=sfen,moves=moves.split(),student_side=0,explanation=explanation,source_pages=pages,**kw)

def m(prompt, sfen, moves, explanation, pages, **kw):
    accepted = moves.split()
    for usi in accepted:
        result = after(sfen, usi)
        ACTIONS.append(dict(position=sfen,moves=[usi],final_position=result,legal=True))
    return dict(kind='move',prompt=prompt,position=sfen,accepted=accepted,explanation=explanation,source_pages=pages,**kw)

def targets(prompt, sfen, origin, squares, explanation, pages, **kw):
    return dict(kind='targets',prompt=prompt,position=sfen,**{'from':origin},targets=squares.split(),explanation=explanation,source_pages=pages,**kw)

def check_mate(sfen, moves, label):
    final = after(sfen, moves)
    assert board(final).is_checkmate(), (label, final, [x.usi() for x in board(final).legal_moves])
    CHECKS.append(dict(kind='checkmate',label=label,position=sfen,moves=moves.split(),final_position=final))

def guards(sfen, target, expected, color=shogi.BLACK, kinds=None):
    b = board(sfen)
    actual = sorted(shogi.SQUARE_NAMES[s] for s in b.attackers(color, shogi.SQUARE_NAMES.index(target)) if kinds is None or b.piece_at(s).symbol().upper() in kinds)
    assert actual == sorted(expected.split()), (target, actual, expected, sfen)
    CHECKS.append(dict(kind='guards',position=sfen,target=target,expected=actual,filter_piece_types=kinds,color=color))

def legal_destinations(sfen, origin, expected):
    actual = sorted({x.usi()[2:4] for x in board(sfen).legal_moves if x.usi().startswith(origin)})
    assert actual == sorted(expected.split()), (origin, actual, expected)
    CHECKS.append(dict(kind='legal_destinations',position=sfen,origin=origin,expected=actual))

def material(sfen, label):
    b=board(sfen); counts={k:0 for k in 'PLNSGBRK'}
    for s in range(81):
        p=b.piece_at(s)
        if p: counts[p.symbol().upper().replace('+','')]+=1
    for hand in b.pieces_in_hand:
        for p,n in hand.items(): counts[shogi.Piece(p,0).symbol()]+=n
    assert counts == dict(P=18,L=4,N=4,S=4,G=4,B=2,R=2,K=2), (label,counts)
    CHECKS.append(dict(kind='full_material',label=label,counts=counts))

def central(lesson):
    base=fig(139,1,pos('7gP 6gP 7iS 6iG 5iK 4iG 3iS 5g+p'))
    ready=edit(base,hand='n',turn='w')
    fig(139,2,after(ready,'N*4g'))
    check_mate(ready,'N*4g','吊桂将死')
    lesson['steps'] += [
        t('居玉是玉留在初形：先手5九、后手5一。玉在底线，往后无路；寄せ是把玉逼向将死的过程。“把玉逼到底线”能减小逃跑范围。第1图中，后手成步沿3七→4七→5七靠近，己方金反而挡在先手玉的两边。',[139]),
        targets('第1图：选出紧挨5九玉、堵住左右底线逃路的两枚先手棋子。',base,'5i','6i 4i','两枚金在6九、4九。它们位置低，不能挡住接下来桂的跳跃王手。',[139],source_figures=['139:1']),
        m('第1→2图：按正文假设后手有一枚持驹桂。将桂打在4七，完成“吊桂”将死。',ready,'N*4g','桂从4七跳着攻击5九玉；5七成步封住4八、5八、6八，己方金堵住4九、6九，玉无法逃脱。这类把桂打到玉前方的将死称为吊るし桂。',[139],source_figures=['139:1','139:2'])]
    for number, rook, bishop in [(3,'2h','3g'),(4,'2d','1e'),(5,'8d','9e')]:
        pre=pos(f'5iK {rook}R','b','w')
        post=fig(140,number,after(pre,'B*'+bishop))
        lesson['steps'].append(m(f'第{number}图：后手把持驹角打到{bishop[0]}{"abcdefghi".index(bishop[1])+1}，同时王手并攻击飞车。',pre,'B*'+bishop,'角的一条斜线通向5九玉，另一条斜线通向飞车。必须先应付王手，因而飞车面临丢失。',[140],source_figures=[f'140:{number}']))
        lesson['steps'].append(targets('选出刚打下的角同时瞄准的先手玉与飞车。这里只选受攻棋子，不选角的全部走法。',post,bishop,f'5i {rook}','居玉与不同位置的飞车，都可能落在角的两条斜线上。',[140],source_figures=[f'140:{number}']))
    pawn=pos('5iK 2hR 2eP 2cp')
    lesson['steps'] += [seq('正文补充：复盘飞先步交换▲2四歩→△同歩→▲同飛，观察飞车为什么会出现在第4图的2四。',pawn,'2e2d 2c2d 2h2d','本练习只摆正文所涉及的玉、飞与两枚步；交换后双方各持一枚步。飞车到2四时，仍需注意1五角的王手飞取。',[140]),
        seq('改善示意：先手先把玉从5九侧移到6九；后手再打3七角。',pos('5iK 2hR','b'),'5i6i B*3g','3七角仍攻击2八飞，但斜线不再通向玉。正文指出，玉只侧移到6九，这三张特定的王手飞取图就不成立；这不代表从此没有其他双攻。',[140])]

def beginner(lesson):
    opening='7i6h 3c3d 2h5h 7a6b 3i4h 8c8d'
    base=fig(141,6,after('startpos',opening)); material(base,'初心者围初图')
    line='9g9f 8d8e 8h9g 9c9d 5g5f 9d9e 9f9e 9a9e 9g7e 9e9i+'
    fig(142,7,after(base,'9g9f 8d8e 8h9g 9c9d'))
    fig(142,8,after(base,'9g9f 8d8e 8h9g 9c9d 5g5f 9d9e'))
    fig(142,9,after(base,'9g9f 8d8e 8h9g 9c9d 5g5f 9d9e 9f9e 9a9e'))
    for step in lesson['steps']:
        if step['kind']=='sequence' and step.get('position')=='startpos':
            step.update(seq('从初形复盘“初心者围”与失败的端攻应对，按提示走完双方各手。','startpos',opening+' '+line,'第6图看起来紧密，但9筋步交换后，9七角被香攻击。正文最后两手是▲7五角逃开、△9九香成取香；九筋被破后，八筋也将承受压力。',[141,142],source_figures=['141:6','142:7','142:8','142:9']))
    lesson['steps'] += [
        targets('第6图：选出两枚进攻与防守职责不同、却紧贴在一起的先手玉和飞车。',base,'5i','5i 5h','5九玉与5八飞贴在同一筋，容易被一起攻击；这只是该阵形的五个弱点之一。',[141],source_figures=['141:6']),
        t('五个弱点要逐项检查：①居玉；②两翼的桂、香没有参与防守；③玉飞贴近；④角头缺少保护；⑤2八出现空洞。金银聚集在中央的外观，不能代替实际的棋路与联系。',[141]),
        m('第6图尚能修正：把左金从6九移到7八，先补好角头。',base,'6i7h','▲7八金增加对8七的保护。书中反对的是把金银形状固定后拒绝再动，不是说一旦走成这样就必须认输。',[142]),
        seq('检查另一种轻率走法：▲7六歩打开角道后，观察后手如何取走没有保护的8八角。',base,'7g7f 2b8h+','正文提醒此时不能随便走7六步，因为打开角道会让角被白吃；这里把这一警告展开成合法的取角演示。',[142],analysis_continuation=True)]

def yagura(lesson):
    partial=fig(147,4,pos('9al 8br 9cp 7cn 6cs 7dp 6dp 8ep 7fP 6fP 5fP 9gP 8gP 7gS 6gG 8hK 7hG 6hB 9iL 8iN'))
    mutual=fig(147,5,pos('9al 2an 1al 8br 4bb 3bg 2bk 9cp 7cn 6cs 4cg 3cs 2cp 1cp 7dp 6dp 5dp 4dp 3dp 8ep 2eP 7fP 6fP 5fP 3fP 2fS 1fP 9gP 8gP 7gS 6gG 4gP 8hK 7hG 6hB 2hR 9iL 8iN 2iN 1iL'))
    material(mutual,'相矢仓第5图')
    sideways=fig(148,6,pos('9al 8an 6ag 1al 8bk 7bs 5bg 2b+R 9cp 8cp 7cp 6cp 5cp 4cp 2cp 1cp 2eP 7fP 6fP 5fP 4fP 9gP 8gP 7gS 6gG 1gP 8hK 7hG 2h+r 9iL 8iN 1iL','BSNPbsnp'))
    fig(148,7,after(sideways,'2b1a S*6i')); material(sideways,'矢仓对美浓第6图')
    reverse=fig(149,8,pos('7fP 6fP 5fP 9gP 8gP 7gG 6gG 8hK 7hS 9iL 8iN'))
    badside=fig(149,9,edit(reverse,'7is 4ir'))
    knight=fig(149,10,edit(reverse,'9g- 9fP 8dp 8en',hand='2p'))
    normal=edit(knight,'7gS 7hG')
    guards(reverse,'7i','',kinds='GS'); legal_destinations(knight,'7g','8f');legal_destinations(normal,'7g','8f 6h')
    start=fig(150,11,pos('9al 2an 1al 8br 4bb 3bg 2bk 7cn 6cs 4cg 3cs 2cp 9dp 7dp 6dp 5dp 4dp 3dp 1dp 8ep 2eP 9fP 7fP 6fP 5fP 4fP 3fP 1fP 8gP 7gS 6gG 4gS 3gN 8hK 7hG 6hB 2hR 9iL 8iN 1iL'))
    material(start,'相居飞车第11图')
    first='4f4e 4d4e 3g4e 3c4d 4g4f'
    counter='6d6e 6f6e 7c6e 7g6f 8e8f 8g8f P*8e 8f8e P*8f'
    f12=fig(150,12,after(start,first)); f13=fig(150,13,after(f12,counter)); material(f13,'相居飞车第13图')
    lesson['steps'] += [
        targets('第4图：选出站在先手第三段、正面迎接敌军的金与银。',partial,'8h','7g 6g','7七银、6七金组成正面防线；7八金在它们后面，不能混同为第三段。敌方飞、桂、银正在玉的正面集结。',[147],source_figures=['147:4']),
        targets('第5图：选出双方玉的位置，观察两边的矢仓正面各自面对哪一路进攻。',mutual,'8h','8h 2b','双方都采用居飞车并围成矢仓，称为相矢仓。第三段金银挡在玉与对方攻击阵之间；原书也指出，羽生善治等居飞车棋士曾在许多相矢仓棋局中争夺头衔。',[147],source_figures=['147:5']),
        seq('第6→7图：先手▲1一龍取香，后手△6九銀打，攻击7八金。',sideways,'2b1a S*6i','横向攻击时，7七银、6七金难以迅速回防底部，7八金会成为目标。后手采用美浓，更适应这种横向争斗；本例因此是先手不利。',[148],source_figures=['148:6','148:7']),
        targets('第7图：6九银打直接攻击矢仓中的哪枚金？只选择受攻击的金。',after(sideways,'2b1a S*6i'),'6i','7h','后手银能斜后走到7八。选择围玉要看对方战法和进攻方向，不能把适合相居飞车的结构直接照搬到所有对局。',[148]),
        targets('第8图：选出位置交换后的7七金和7八银。',reverse,'7g','7g 7h','这是把正常矢仓的7七银、7八金交换后形成的逆形。即使玉已进入8八，也不能只看外观像围玉就认为可靠。',[149],source_figures=['149:8']),
        q('逆形的金银为什么不能应付第9图从底线攻来的银、飞？',['7九没有己方金银控制，横向弱点暴露','银与金走法相同，所以换位无影响','任何银打都不能防'],0,'正常的7八金能后退到7九；7八银不能直后走，7七金也够不到7九。这是具体走法造成的区别。',[149]),
        targets('第9图：选出从底线突入、受到4九飞保护的后手银。',badside,'4i','7i','7九银攻击8八玉，而飞车沿九段保护银；围玉上方的金没有发挥应有的回防作用。',[149],source_figures=['149:9']),
        m('第10图：8五桂攻击7七金。这枚金要躲避攻击，只能到哪格？',knight,'7g8f','▲8六金虽然逃开，但金离开围玉。其余相邻可走格被己方棋子占住。',[149],source_figures=['149:10']),
        m('改为正常的7七银、7八金：仍面对8五桂，试走书中给出的任一银退路。',normal,'7g8f 7g6h','▲8六银一面避开攻击，一面保护桂瞄准的7七、9七；▲6八银则留在己阵。银在7七、金在7八各有具体理由。',[149]),
        seq('第11→12图：先手从玉前四筋开始交换，再走▲4六银。',start,first,'▲4五步△同步▲同桂取得步；△4四银后▲4六银暂告一段落。金银正面围着玉，攻击部队也在对方玉的前方。',[150],source_figures=['150:11','150:12']),
        seq('第12→13图：后手六筋反击，再连续利用八筋步交换和打步。',f12,counter,'△6五步▲同步△同桂▲6六银，然后△8六步▲同步△8五步打▲同步△8六步打。后手把前面受攻时得到的持驹步用于反击；最终先手持四步、后手无持驹。',[150],source_figures=['150:12','150:13']),
        targets('第13图：选出双方已进入敌方正面的桂。',f13,'4e','4e 6e','先手桂在4五、后手桂在6五。双方一边承受攻击，一边积累反击力量，争斗可以同时发生在两处，甚至扩展到全盘。',[150],source_figures=['150:13'])]
    return start,f13

def mino(lesson, reference):
    early=fig(154,6,pos('9al 8an 4ag 3as 2an 1al 8br 6bs 5bg 3bk 2bb 9cp 7cp 6cp 4cp 2cp 5dp 3dp 1dp 8ep 7fP 6fP 1fP 9gP 8gP 7gB 5gP 4gP 3gP 2gP 7hS 6hR 3hS 2hK 9iL 8iN 6iG 4iG 2iN 1iL'))
    late=fig(154,7,pos('9al 8a+R 4ag 2an 1al 6bs 5bg 3bk 9cp 6cp 2cp 7dP 5dp 4dp 3dp 1dp 6eP 9fP 4fP 1fP 5gP 3gP 2gP 5hG 3hS 2hK 9iL 6ir 4iG 2iN 1iL','BSN2Pbsnp'))
    fig(154,'参考',reference)
    material(early,'对抗形美浓第6图');material(late,'对抗形美浓第7图')
    weakness=fig(155,8,pos('2cp 3dp 1dp 5eb 3fn 1fP 5gP 4gP 3gP 2gP 5hG 3hS 2hK 4iG 2iN 1iL','gn'))
    lines=[('向金银靠拢','2h3i G*2h','▲3九玉也不能逃过△2八金打。'),('立刻向端逃跑','2h1g N*2e 1g2f G*3e','▲1七玉后，△2五桂打▲2六玉△3五金打。桂与金封住玉。'),('先退1八再逃','2h1h G*2h 1h1g 5e4d 2g2f N*2e','▲1八玉△2八金打▲1七玉△4四角▲2六步△2五桂打，形成第9图。')]
    for label,line,ex in lines: check_mate(weakness,line,'美浓小鬓攻：'+label)
    fig(155,9,after(weakness,lines[2][1]))
    edge=fig(155,10,pos('1ak 2cp 3dp 2dn 1eP 4fP 1fL 5gP 3gP 2gP 5hG 3hS 2hK 4iG 2iN','4P'))
    pinned=shogi.Move.from_usi('3g3f')
    assert pinned not in board(weakness).legal_moves
    CHECKS.append(dict(kind='illegal_exposes_king',position=weakness,move='3g3f'))
    loose=fig(156,11,pos('6fb 5fP 4fP 3gP 2gP 1gP 5hG 3hS 2hK 7ir 4iG 3is 2iN 1iL','Lg'))
    protected=fig(156,12,pos('6fb 5fP 4fP 3fP 4gG 3gS 2gP 1gP 3hG 2hK 7ir 3is 2iN 1iL','Lg'))
    defensive=fig(156,13,edit(loose,'3i- 5iL',hand='gs'))
    predef=edit(loose,'3i-',hand='Lgs')
    guards(loose,'2h','');guards(protected,'2h','3g 3h')
    check_mate(loose,'2h1h G*2h','美浓无保护的2八')
    lesson['steps'] += [
        targets('第6图：选出双方玉的位置，再观察它们与各自飞车是否在相反一侧。',early,'6h','2h 3b','先手飞在6八、玉在2八；后手飞在8二、玉在3二。对抗形预计先在飞车附近交战，再用成大子或交换得到的大子从横向攻玉。',[154],source_figures=['154:6']),
        targets('第7图：选出已从横向进入阵地的双方飞车或龙。',late,'6i','8a 6i','先手龙在8一、后手飞在6九。先手5八金、4九金为横向攻击提供防线；前图后手的船围也为类似方向作准备。',[154],source_figures=['154:7']),
        targets('参考图：选出双方贴近对方围玉正面的桂，用它与刚才的大子横攻对照。',reference,'4e','4e 6e','相居飞车常在玉的正面直接交战；振飞车对居飞车则常经历“进攻部队交战→横向攻玉”两个阶段。围玉应适应预期的战斗方向。',[154],source_figures=['154:参考']),
        q('第8图△3六桂王手，为什么▲3六同步不合法？',['会打开5五角到2八玉的斜线，使己玉仍受攻击','步永远不能吃桂','桂的王手不能被吃掉'],0,'3七步一旦离开，5五角沿4六、3七直接照到2八玉。这是牵制，不能用暴露己玉的走法解除王手。',[155]),
    ]
    for label,line,ex in lines:
        lesson['steps'].append(seq('第8图：复盘“'+label+'”这一逃玉分支。',weakness,line,ex+' 每个终点均按合法走法验证为将死。',[155],source_figures=['155:8']+(['155:9'] if label=='先退1八再逃' else [])))
    lesson['steps'] += [
        t('小鬓攻是从玉斜前方逼近的攻击。美浓虽然完整，图8的三条逃玉分支仍都失败；前面所学完成形里先走▲4六步，正是为这类斜线攻击提前腾出空间。',[155]),
        targets('第10图：2四桂现在瞄准端上哪一枚先手香？只选图中被桂攻击的香。',edge,'2d','1f','后手用步打入并弃步，把香引到1六，再以2四桂瞄准香。端上离金银远，同样是美浓的弱点。图中先手有四枚持驹步。',[155],source_figures=['155:10']),
        targets('第11图：选出刚打入、正在王手的后手银。',loose,'2h','3i','3九银由6六角保护。▲3九同金会被△同角成取回；美浓的玉在2八却没有己方金银直接保护。',[156],source_figures=['156:11']),
        seq('第11图：先手向1八逃玉，后手把金打回玉刚离开的2八。',loose,'2h1h G*2h','△2八金打将死。玉离开后，原来的2八格没有保护者，敌金能够继续贴身追击。',[156]),
        seq('第12图对照：▲1八玉，试验△2八金打，再用原来3八的金吃回。',protected,'2h1h G*2h 3h2h','右侧矢仓只是为对照而镜像摆放。2八有金银控制，金打不再能将死；最后的吃金是把正文的“并不可怕”具体展开的验证。',[156],source_figures=['156:12'],analysis_continuation=True),
        m('第13图：回到尚未被3九银王手的局面，用持驹香先挡住底线的飞车。',predef,'L*5i','▲5九香打先受，是书中给出的预防示例。美浓比矢仓更须留心玉遭将军后的连续追击，应在王手形成前处理威胁。',[156],source_figures=['156:13'])]

def anaguma(lesson):
    race=fig(159,4,pos('8aR 4ag 1al 9bl 6b+P 3bs 2bk 9cp 6c+P 4cg 3cn 2cp 1cp 5dp 4dp 3dp 8ep 5fP 9gP 8gP 6g+p 4gP 3gP 2gP 1gP 9hL 6h+p 3hG 2hS 1hL 8ir 3iG 2iN 1iK','BSNbsn','w'))
    racing='6h5h 6b5b 4a3a 6c5c'
    fig(159,5,after(race,racing));material(race,'穴熊对高美浓第4图')
    attack=fig(160,6,pos('9al 8a+R 4ag 2an 1al 6b+P 4bs 3bk 5cp 4cp 2cp 1cp 9dp 3dp 9fP 7fP 4fP 3fS 8gP 5g+n 3gP 2gP 1gP 4h+p 2hS 1hL 9i+r 3iG 2iN 1iK','G2P2bgsnlp'))
    sacrifice='8a4a 3b4a G*2b'
    won=fig(160,7,after(attack,sacrifice));material(attack,'穴熊弃龙第6图');material(won,'穴熊双必至第7图')
    mino=fig(160,8,pos('9al 4ak 2an 1al 6b+P 4bs 2bG 5cp 4cp 2cp 1cp 9dp 3dp 9fP 7fP 8gP 6g+n 4gP 3gP 2gP 1gP 5h+p 3hS 2hK 9i+r 4iG 2iN 1iL','G2Pr2bg2snl2p','w'))
    CHECKS.append(dict(kind='source_material_anomaly',page=160,figure=8,position=mino,note='原图盘上13枚未成步＋两枚と＝15；双方持驹各歩二，总计19枚步。两人独立视觉复核，忠实保留为比较示意，不声称可由初形到达。'))
    short=fig(161,9,pos('5gP 4gP 3gP 2gP 1gP 5hG 2hK 4iG 3iS 2iN 1iL'))
    long=edit(short,'1i- 1hL 2h- 1iK 3i- 2hS')
    fig(161,10,long)
    noescape=fig(162,11,pos('6eb 5fb 2gP 1gP 2hS 1hL 5ir 3iG 2iN 1iK',turn='w'))
    encircled=fig(162,12,pos('6fb 5g+p 4gp 3gP 2gP 1gP 5h+p 3hG 2hS 1hL 6i+r 3iG 2iN 1iK'))
    escape=fig(162,13,pos('6fb 4fP 1fP 5g+p 4gp 3gP 2gP 5h+p 3hS 2hK 6ir 4iG 2iN 1iL'))
    check_mate(noescape,'5f2i+ 3i2i 6e2i+','穴熊双角牺牲收尾')
    check_mate(noescape,'5f2i+ 3i2i 5i2i+','穴熊角与飞牺牲收尾')
    lesson['steps'] += [
        t('穴熊把玉围在角落，让玉远离飞车所在的主要战场。它早期曾被批评为棋子偏在一边、属于旁门，后来逐渐被承认为优秀围玉。长处要从实际攻防速度来理解。',[159]),
        seq('第4→5图：后手先走6八成步到5八；先手两个成步协力逼近高美浓。',race,racing,'△5八と寄▲5二と寄△3一金▲5三と寄。即使后手先走、攻击部队看起来更近，先手仍能先破坏高美浓。正文把这种单纯横攻竞赛评价为穴熊更强。',[159],source_figures=['159:4','159:5']),
        seq('第6→7图：▲4一龍弃龙、△同玉、▲2二金打。按原书复盘这三手妙手。',attack,sacrifice,'先手虽损失角、桂、香，却能借远离战场的穴熊争得时间。弃龙取金后再打2二金，让后手面对两个金打的将死威胁。',[160],source_figures=['160:6','160:7']),
        targets('第7图：选择先手下一手两处金打将死的落点。这里研究威胁，暂不代替后手走棋。',won,'2b','3b 5b','威胁为▲3二金打与▲5二金打。后手无法同时防住两边；并且此时无法立即对1九穴熊玉将军，所以不能用连续王手抢先。',[160],source_figures=['160:7']),
        t('“不会被将军”说的是第7图的当前局面，不是穴熊永远不会受将军。下一页就会看到穴熊无逃路的另一面。',[160]),
        t('原图核对说明：本页第8图是把先手改成美浓的比较示意。盘上含15枚步及成步，双方又各持两步，共19枚，超过实战总数18。这里忠实保留原书图与持驹，用来比较具体攻防；它不能当作由初形自然到达的实战局面。',[160]),
        seq('第8图美浓对照：△3六桂打▲同步△5五角打，利用王手再瞄准2二金。',mino,'N*3f 3g3f B*5e','5五角一条斜线通向2八玉，另一条斜线通向2二金。这一王手金取让先手不能照原计划直接攻玉。',[160],source_figures=['160:8']),
        m('第9图：只用一步补上右银，完成美浓。',short,'3i3h','▲3八银即可。与穴熊相比，美浓需要的准备时间少。',[161],source_figures=['161:9']),
        m('同一第9图，改走穴熊路线的第一步：把香从1九移到1八。',short,'1i1h','先让开角落。接下来还要移玉、移银，金仍需靠近。这里按自己的构筑顺序分题练习，不插入虚构的对方等待手。',[161]),
        m('穴熊路线第二步：把2八玉藏到1九。',edit(short,'1i- 1hL'),'2h1i','玉进入角落，但银还未填到2八。',[161]),
        m('穴熊路线第三步：把3九银填到2八。',edit(short,'1iK 1hL 2h-'),'3i2h','这才到第10图，仍未完全完成：金还离玉较远。',[161],source_figures=['161:10']),
        m('第10图继续：让4九金靠到3九。',long,'4i3i','正文说先把金靠到3九可暂时安心。构筑需要时间；若对手已发动快攻，应先处理交战处，不能机械地继续围玉。',[161]),
        seq('第11图：△2九角成、▲同金，再用另一枚角取回并成。',noescape,'5f2i+ 3i2i 6e2i+','穴熊的银、香把玉封在角落。连续牺牲后，最后一次王手就是将死。',[162],source_figures=['162:11']),
        seq('第11图另一收尾：同样先角成、金吃回，最后改用飞车取回并成。',noescape,'5f2i+ 3i2i 5i2i+','正文明确列出△同角成或△同飛成两种收尾；两者都已逐手验证为将死。',[162]),
        targets('第12图：选择玉上方封住出路的己方银、香。',encircled,'1i','2h 1h','四周已被敌军包围，先手缺少有效防守手段。这里比的是在敌方王手来到之前，己方能否先寄住敌玉，不能只数还剩多少层己方棋子。',[162],source_figures=['162:12']),
        m('第13图美浓对照：把2八玉移到1七，开始向上方逃离。',escape,'2h1g','美浓在这个局面还能从上方逃。书中说继续逃走时，有时甚至可能入玉；这不是保证成功，只是穴熊因银、香挡路很难拥有的可能性。',[162],source_figures=['162:13'])]
    return won,mino

def separate(lesson):
    near=fig(163,1,pos('8fp 8hK 7hR','s','w'))
    fork=fig(163,2,after(near,'S*8g'))
    far=fig(163,3,pos('8fp 8hK 2hR','s','w'))
    fig(164,4,after(far,'S*8g 8h7g'))
    lesson['steps'] += [
        t('玉与飞都是必须时刻掌握位置的重要棋子。“玉飛、接近すべからず”是围玉的基本格言。玉不能被取，飞车也很有价值；两者贴近，会让同一枚敌子容易同时攻击它们。',[163]),
        seq('第1→2图：后手在8七打银，先手逃玉到7七，再看后手怎样取飞。',near,'S*8g 8h7g 8g7h+','8六步保护8七银，所以玉不能直接吃银。玉必须先离开王手，7八飞随即被银取走。正文给出▲7七玉逃走并说明飞会丢失，最后一手把失飞结果具体演示。',[163,164],source_figures=['163:1','163:2'],analysis_continuation=True),
        targets('第2图：选出8七银同时瞄准的先手玉和飞。',fork,'8g','8h 7h','后手银能直前到8八，也能斜前到7八，因此形成玉飞双攻。',[163],source_figures=['163:2']),
        seq('第3→4图对照：飞已远在2八。再次△8七銀打、▲7七玉。',far,'S*8g 8h7g','玉能同样避开王手，飞却不在银的攻击范围。拉开重要棋子的距离，减少被一次双攻的风险。',[163,164],source_figures=['163:3','164:4']),
        t('小注：8六步这样的棋子能成为进攻的立足点，称为“拠点”。围玉的常用关系是：居飞车让飞留右、玉向左围；振飞车把飞移左、玉向右围。这是一般基础，实际对局可能出现有理由的例外。',[163,164])]

def walls(lesson):
    bad=fig(167,10,pos('9gP 8gP 7gP 6gP 8hS 7hG 9iL 8iN 7iK','rg','w'))
    attacked=fig(167,11,after(bad,'R*5i'))
    fixed=fig(168,12,pos('7fP 9gP 8gP 7gS 6gP 7hG 9iL 8iN 7iK'))
    fig(168,13,after(fixed,'7i8h'))
    alternative=fig(168,14,pos('8fP 9gP 8gS 7gP 6gP 7hG 9iL 8iN 7iK'))
    gold=fig(169,15,pos('7fP 9gP 8gP 6gP 5gP 8hG 6hS 5hG 9iL 8iN 6iK'))
    goodgold=fig(169,16,after(gold,'8h7h'))
    badgold=fig(169,17,after(gold,'6i7h'))
    many=fig(170,18,pos('7fP 6fP 5fP 9gP 8gP 7gN 6gG 8hK 7hS 6hS 9iL 6iG'))
    manyattack=fig(170,19,edit(many,'9br 9cl 6db 9fp'))
    lesson['steps'] += [
        targets('第10图：哪枚己方棋子挡在玉想进入的8八？',bad,'7i','8h','8八银成了壁银。单纯把棋子聚在玉旁边，不等于围得更安全；要给玉留下能进出围玉的道路。',[167],source_figures=['167:10']),
        targets('第11图：5九飞已经沿底线王手。选出仍挡住8八入城路线的己方银。',attacked,'7i','8h','玉无法直接进入8八避开底线攻击。原书说这枚银在这个位置妨碍逃路，甚至比暂时没有它更麻烦；这里不把“路线受阻”误称为已经将死。',[167],source_figures=['167:11']),
        seq('第12图改善后，模拟前图同样的底线王手：△5九飛打、▲8八玉。',edit(fixed,hand='rg',turn='w'),'R*5i 7i8h','7七银已让开8八，玉可顺利入城。练习把第10图后手持驹飞带回，来检验正文对第12、13图的说明。',[168],source_figures=['168:12','168:13']),
        m('另一种解除壁银的方法，第一步：先推进8七步到8六。',edit(bad,hand='-',turn='b'),'8g8f','原书也认可▲8六步→▲8七银这条路线。分题只练习先手构筑，不加入虚构的对手等待手。',[168]),
        m('接着让8八银直前到8七，完成第14图。',edit(bad,'8g- 8fP',hand='-',turn='b'),'8h8g','银移开后，8八空出，玉便有了进入围玉的通路。',[168],source_figures=['168:14']),
        t('第15图是角交换后容易出现的壁金：后手在8八角成，先手同金吃回，金便站在8八。看似用了强力金保护，却可能堵住玉的通路。',[169]),
        m('第15→16图：把8八金退回7八，为玉留下通道。',gold,'8h7h','▲7八金是正文推荐的整形。随后玉可经7九走到8八。',[169],source_figures=['169:15','169:16']),
        m('金退回后，把6九玉移到7九。',edit(goodgold,turn='b'),'6i7i','玉通过底线接近空出的8八，不必挤进两枚金银之间。',[169]),
        m('继续把7九玉移到8八，完成入城。',edit(after(edit(goodgold,turn='b'),'6i7i'),turn='b'),'7i8h','这组分题按原书自己的构筑次序操作。玉有通道，金银仍保有保护作用。',[169]),
        targets('第17图走成▲7八玉后，哪枚金仍堵住向左的通路？',badgold,'7h','8h','玉到了7八，8八金仍是壁金。紧急时可能不得不这样走，但不能因此认为壁金已经解决。',[169],source_figures=['169:17']),
        targets('第18图：选出围在玉同一侧的四枚金银。',many,'8h','6g 7h 6h 6i','6七金、7八银、6八银、6九金都集中在玉的右方；四枚的数量多，不代表应付所有方向都有效。',[170],source_figures=['170:18']),
        targets('第19图：攻击从左边端上来时，选出挡住8八玉向右逃跑的己方银。',manyattack,'8h','7h','敌方飞香与角从另一侧进攻，原来的金银厚墙难以应对，7八银又堵住玉的去路。围玉还要兼顾保护关系、效率和整体逃路。',[170],source_figures=['170:19']),
        q('这一组壁驹图要求怎样理解矢仓、美浓、穴熊等围玉？',['理解每枚棋子的保护关系与玉的通路，再选择适合战斗的结构','只背形状，所有局面都照摆','围玉棋子越多，永远越安全'],0,'好的围玉把坚固、棋子联系和逃路放在一起考虑。学会理由，才知道局面变化时该怎样调整。',[170])]

def validate_threats(won, mino, lesson):
    b=board(won)
    checking=[]; survived=[]; defenses=0
    for defense in list(b.legal_moves):
        b.push(defense); defenses+=1
        if b.is_check(): checking.append(defense.usi())
        mates=[]
        for usi in ['G*3b','G*5b']:
            candidate=shogi.Move.from_usi(usi)
            if candidate in b.legal_moves:
                b.push(candidate)
                if b.is_checkmate(): mates.append(usi)
                b.pop()
        if not mates: survived.append(defense.usi())
        b.pop()
    assert not checking, checking
    assert not survived, survived
    CHECKS.append(dict(kind='hisshi',position=won,defenses_checked=defenses,checking_defenses=checking,defenses_surviving_both_gold_drops=survived))
    # The source says S*3i starts a forced mate but does not print the continuations.
    # Expand its complete response tree with real legal moves, and label that part
    # as explanatory analysis rather than as a line printed in the book.
    cache={}
    def solve(b, depth):
        key=(b.zobrist_hash(),depth)
        if key in cache: return cache[key]
        if b.is_checkmate(): return []
        if depth==0: return None
        if b.turn==shogi.WHITE:
            choices=[]
            for move in list(b.legal_moves):
                b.push(move)
                if b.is_check():
                    count=len(list(b.legal_moves))
                    if count==0:
                        b.pop();return [(move.usi(),[])]
                    choices.append((count,move))
                b.pop()
            for _,move in sorted(choices,key=lambda item:item[0]):
                b.push(move)
                branch=solve(b,depth-1)
                b.pop()
                if branch is not None:
                    cache[key]=[(move.usi(),branch)];return cache[key]
            cache[key]=None
            return None
        branches=[]
        for move in list(b.legal_moves):
            b.push(move);branch=solve(b,depth-1);b.pop()
            if branch is None:
                cache[key]=None;return None
            branches.append((move.usi(),branch))
        cache[key]=branches if branches else None
        return cache[key]
    root=board(after(mino,'S*3i'))
    result=None
    for depth in [2,4,6,8]:
        result=solve(root,depth)
        if result is not None: break
    assert result is not None,'could not validate source S*3i mate'
    def leaves(tree,prefix):
        if not tree: return [prefix]
        return [line for usi,child in tree for line in leaves(child,prefix+[usi])]
    lines=leaves(result,['S*3i'])
    for i,line in enumerate(lines):
        check_mate(mino,' '.join(line),'美浓对照银打将死分支'+str(i+1))
        lesson['steps'].append(seq(f'第8图：△3九银打的将死验证，第{i+1}条逃玉或吃银应手。',mino,' '.join(line),'原书给出△3九银打并说明先手被将死；其后为本教程补出的规则验证续着。长分支里，4八银由5八成步保护，3九角由4八银保护，最后2八金又有3九角保护。观察连续牺牲与打入怎样衔接。',[160],source_figures=['160:8'],analysis_continuation=True))
    CHECKS.append(dict(kind='forced_mate_tree',position=mino,first_move='S*3i',tree=result,all_defender_replies_included=True))

def build():
    course=json.loads((ROOT/'godot/courses/hanyu-opening.json').read_text('utf-8'))
    byid={l['id']:l for c in course['chapters'] for l in c['lessons']}
    ids=['opening-central-king','opening-beginner-castle','opening-yagura-context','opening-mino-weakness','opening-anaguma-speed','opening-separate-rook','opening-walls']
    lessons=[]
    for key in ids:
        l=copy.deepcopy(byid[key])
        n=l.get('ch4_preserved_step_count',len(l['steps']))
        l['steps']=l['steps'][:n];l['ch4_preserved_step_count']=n
        lessons.append(l)
    central(lessons[0]);beginner(lessons[1]);_,reference=yagura(lessons[2]);mino(lessons[3],reference)
    won,comparison=anaguma(lessons[4]);separate(lessons[5]);walls(lessons[6])
    validate_threats(won,comparison,lessons[4])
    for l in lessons:
        # Keep chapter catalog ordered even though supporting analyses are appended.
        suffix=' 本课已补齐所列来源页的全部正文、原图与变化，含可逐手重放的互动练习。'
        if not l['summary'].endswith(suffix):l['summary']+=suffix
    coverage=[dict(page=p,status='authored_verified',lesson_ids=[l['id'] for l in lessons if p in l['pages']],note='本页全部正文、原图、注释与变化已视觉核对并转成互动；原书的构筑省略对手着法处使用独立分步题，未虚构等待手。') for p in PAGES]
    next(c for c in coverage if c['page']==160)['note']+=' 第8图原图物料异常：盘上及持驹共19枚步，两人独立核对后忠实保留并在课程明确注明，不声称可从初形到达。△3九銀后的将死全分支是教程补充分析，已与原书明载着法区分。'
    index=json.loads((ROOT/'course_sources/hanyu-opening/index.json').read_text('utf-8'))
    data=dict(schema=1,book_id='hanyu-opening',source_sha256=index['source_sha256'],source_pages=PAGES,replace_lesson_ids=ids,replacement_lesson_ids=ids,lessons=lessons,coverage=coverage,validation=dict(engine='python-shogi',visual_source_pages=PAGES,source_figures=FIGURES,actions=ACTIONS,checks=CHECKS))
    OUT.write_text(json.dumps(data,ensure_ascii=False,indent=2),'utf-8')
    print(json.dumps(dict(lessons=len(lessons),steps=sum(len(x['steps']) for x in lessons),pages=len(PAGES),figures=len(FIGURES),actions=len(ACTIONS),checks=len(CHECKS)),ensure_ascii=False))

if __name__=='__main__':build()
