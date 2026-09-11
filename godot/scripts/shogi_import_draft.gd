extends RefCounted
## Full input stays separate from the bounded, sometimes read-only preview.
const MAX_BYTES = 2097152
const PREVIEW_CHARS = 16000
const Decoder = preload("res://scripts/shogi_kif_download.gd")
var source = ""
var source_name = ""
var error = ""
var revision = 0

func replace(value: String, name: String = "") -> bool:
	if value.to_utf8_buffer().size() > MAX_BYTES:
		error = "棋谱超过 2 MiB，已保留原输入。"
		return false
	source = value.trim_prefix(String.chr(0xfeff)); source_name = name; error = ""
	revision += 1
	return true

func read_bytes(raw: PackedByteArray, name: String = "") -> bool:
	if raw.size() > MAX_BYTES: error = "棋谱超过 2 MiB，已保留原输入。"; return false
	var value = Decoder.decode(raw)
	if value.is_empty() and not raw.is_empty(): error = "无法读取文字编码，请使用 UTF-8 或 Shift JIS 棋谱。"; return false
	return replace(value, name)

func locked() -> bool:
	return source.length() > PREVIEW_CHARS

func preview() -> String:
	return source.left(PREVIEW_CHARS) + "\n\n…" if locked() else source

func description() -> String:
	if locked(): return "预览前 16,000 字；载入完整 %s 字。可重新粘贴或清空。" % source.length()
	return source_name if not source_name.is_empty() else "KIF · CSA · USI · SFEN · JSON"
