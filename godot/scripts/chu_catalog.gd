extends RefCounted
## Stable base identities; +32 means this physical piece has promoted once.
## Sources and the digital rule profile are documented in docs/CHU-SHOGI.md.
enum { EMPTY, PAWN, GO_BETWEEN, LANCE, REVERSE, LEOPARD, COPPER, SILVER, GOLD,
	TIGER, ELEPHANT, KIRIN, PHOENIX, SIDE, VERTICAL, ROOK, BISHOP, HORSE, DRAGON,
	QUEEN, LION, KING, WHITE_HORSE, WHALE, STAG, PRINCE, BOAR, OX, FALCON, EAGLE }
const RULES_ID = "chu-renmei-2019-digital-1"
const NAMES = ["", "歩兵", "仲人", "香車", "反車", "猛豹", "銅将", "銀将", "金将", "盲虎", "酔象", "麒麟", "鳳凰", "横行", "竪行", "飛車", "角行", "龍馬", "龍王", "奔王", "獅子", "玉将", "白駒", "鯨鯢", "飛鹿", "太子", "奔猪", "飛牛", "角鷹", "飛鷲"]
const SHORT = ["", "歩", "仲", "香", "反", "豹", "銅", "銀", "金", "虎", "象", "麒", "鳳", "横", "竪", "飛", "角", "馬", "龍", "奔", "獅", "玉", "白", "鯨", "鹿", "太", "猪", "牛", "鷹", "鷲"]
const PROMOTES = {PAWN:GOLD, GO_BETWEEN:ELEPHANT, LANCE:WHITE_HORSE, REVERSE:WHALE,
	LEOPARD:BISHOP, COPPER:SIDE, SILVER:VERTICAL, GOLD:ROOK, TIGER:STAG, ELEPHANT:PRINCE,
	KIRIN:LION, PHOENIX:QUEEN, SIDE:BOAR, VERTICAL:OX, ROOK:DRAGON, BISHOP:HORSE, HORSE:FALCON, DRAGON:EAGLE}
const KING_STEPS = [Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1),Vector2i(-1,0),Vector2i(1,0),Vector2i(-1,1),Vector2i(0,1),Vector2i(1,1)]
const ORTH = [Vector2i(0,-1),Vector2i(-1,0),Vector2i(1,0),Vector2i(0,1)]
const DIAG = [Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]
const HELP = {
	PAWN:"向前走一格。", GO_BETWEEN:"向前或向后走一格。", LANCE:"向前直行任意格，不能越子。",
	REVERSE:"向前或向后直行任意格。", LEOPARD:"斜向四方及前后各走一格。", COPPER:"前方三格或正后方走一格。",
	SILVER:"前方三格或斜后方走一格。", GOLD:"前方三格、左右或正后方走一格。", TIGER:"除正前方外，周围七格走一格。",
	ELEPHANT:"除正后方外，周围七格走一格。", KIRIN:"斜向走一格，前后左右跳两格。", PHOENIX:"前后左右走一格，斜向跳两格。",
	SIDE:"左右直行任意格，前后走一格。", VERTICAL:"前后直行任意格，左右走一格。", ROOK:"前后左右直行任意格。",
	BISHOP:"斜向直行任意格。", HORSE:"斜向直行任意格，前后左右走一格。", DRAGON:"前后左右直行任意格，斜向走一格。",
	QUEEN:"八个方向直行任意格。", LION:"可向周围两格内跳跃，或连续走两次王步；可双吃、居食或经空格往返。受狮子特殊规则限制。",
	KING:"周围八格走一格。太子仍存活时，失去玉将不立即结束。", PRINCE:"周围八格走一格，与玉将共同决定胜负。",
	WHITE_HORSE:"前方三个方向及正后方直行任意格。", WHALE:"后方三个方向及正前方直行任意格。",
	STAG:"前后直行任意格，其余六方向走一格。", BOAR:"左右和四个斜向直行任意格。", OX:"前后和四个斜向直行任意格。",
	FALCON:"斜向、左右、后方直行；正前方可走一格、跳两格，或连续两步及返回原处。",
	EAGLE:"前后左右及斜后方直行；两个斜前方各可走一格、跳两格，或沿该方向连续两步及返回原处。"}

static func base(piece: int) -> int: return absi(piece) % 32
static func promoted(piece: int) -> bool: return absi(piece) >= 32
static func kind(piece: int) -> int: return PROMOTES.get(base(piece), base(piece)) if promoted(piece) else base(piece)
static func valid(piece: int) -> bool:
	return piece == 0 or (base(piece) in range(1,22) and absi(piece) < 64 and (not promoted(piece) or PROMOTES.has(base(piece))))
static func title(piece: int) -> String:
	return NAMES[kind(piece)] + ("（成" + NAMES[base(piece)] + "）" if promoted(piece) else "")
static func help(piece: int) -> String:
	return title(piece) + "\n" + HELP[kind(piece)] + ("\n已升变，不能再次升变。" if promoted(piece) else "\n可升变为：" + NAMES[PROMOTES[base(piece)]] if PROMOTES.has(base(piece)) else "\n此棋子不升变。")
static func square(index: int) -> String: return "%d-%d" % [12-index%12, index/12+1]
static func inside(p: Vector2i) -> bool: return p.x >= 0 and p.x < 12 and p.y >= 0 and p.y < 12
static func zone(index: int, side: int) -> bool: return index < 48 if side == 1 else index >= 96
static func distance(a: int, b: int) -> int: return maxi(absi(a%12-b%12), absi(a/12-b/12))

static func motion(type: int) -> Dictionary:
	var steps: Array = []; var rays: Array = []; var jumps: Array = []; var twice: Array = []
	match type:
		PAWN: steps = [Vector2i(0,-1)]
		GO_BETWEEN: steps = [Vector2i(0,-1),Vector2i(0,1)]
		LANCE: rays = [Vector2i(0,-1)]
		REVERSE: rays = [Vector2i(0,-1),Vector2i(0,1)]
		LEOPARD: steps = DIAG + [Vector2i(0,-1),Vector2i(0,1)]
		COPPER: steps = [Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1),Vector2i(0,1)]
		SILVER: steps = DIAG + [Vector2i(0,-1)]
		GOLD: steps = [Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1),Vector2i(-1,0),Vector2i(1,0),Vector2i(0,1)]
		TIGER: steps = KING_STEPS.filter(func(v): return v != Vector2i(0,-1))
		ELEPHANT: steps = KING_STEPS.filter(func(v): return v != Vector2i(0,1))
		KIRIN: steps = DIAG; jumps = ORTH.map(func(v): return v*2)
		PHOENIX: steps = ORTH; jumps = DIAG.map(func(v): return v*2)
		SIDE: rays = [Vector2i(-1,0),Vector2i(1,0)]; steps = [Vector2i(0,-1),Vector2i(0,1)]
		VERTICAL: rays = [Vector2i(0,-1),Vector2i(0,1)]; steps = [Vector2i(-1,0),Vector2i(1,0)]
		ROOK: rays = ORTH
		BISHOP: rays = DIAG
		HORSE: rays = DIAG; steps = ORTH
		DRAGON: rays = ORTH; steps = DIAG
		QUEEN: rays = KING_STEPS
		KING, PRINCE: steps = KING_STEPS
		WHITE_HORSE: rays = [Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1),Vector2i(0,1)]
		WHALE: rays = [Vector2i(-1,1),Vector2i(0,1),Vector2i(1,1),Vector2i(0,-1)]
		STAG: rays = [Vector2i(0,-1),Vector2i(0,1)]; steps = KING_STEPS
		BOAR: rays = DIAG + [Vector2i(-1,0),Vector2i(1,0)]
		OX: rays = DIAG + [Vector2i(0,-1),Vector2i(0,1)]
		FALCON: rays = DIAG + [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,1)]; twice = [Vector2i(0,-1)]
		EAGLE: rays = ORTH + [Vector2i(-1,1),Vector2i(1,1)]; twice = [Vector2i(-1,-1),Vector2i(1,-1)]
		LION:
			twice = KING_STEPS
			for y in range(-2,3):
				for x in range(-2,3):
					if x != 0 or y != 0: jumps.append(Vector2i(x,y))
	return {"steps":steps,"rays":rays,"jumps":jumps,"twice":twice}
