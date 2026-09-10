extends SceneTree
const Sync = preload("res://scripts/shogi_tournament_sync.gd")
const Download = preload("res://scripts/shogi_kif_download.gd")
const Historic = preload("res://scripts/shogi_historic_games.gd")
var checks = 0
var failures = []
var output = "res://../review/app/chessis20"

class MockSync extends "res://scripts/shogi_tournament_sync.gd":
	var responses: Array = []
	var requests: Array = []
	func _request(url: String, _limit: int) -> Dictionary:
		requests.append(url)
		await get_tree().process_frame
		return responses.pop_front() if not responses.is_empty() else {"ok": false, "body": PackedByteArray()}

func check(value: bool, title: String) -> void:
	checks += 1
	if not value: failures.append(title); printerr("TEST FAIL: ", title)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var raw = Historic.entries()[0].kif.to_utf8_buffer()
	var normalized = Download.normalize(raw)
	check(not normalized.is_empty() and normalized.plies > 60, "normalize full real historical game")
	var entry = Historic.entries()[0].duplicate(true)
	entry.erase("kif")
	entry.moves_sha256 = normalized.moves_sha256
	var index = {"schema": 1, "updated_utc": "2099-01-01T00:00:00+00:00", "games": [entry]}
	index = JSON.parse_string(JSON.stringify(index))
	check(Sync.valid_index(index), "accept valid catalog")
	for mutation in ["duplicate", "traversal", "host", "userinfo", "query", "sha", "fraction", "missing-tags", "open-game"]:
		var bad = index.duplicate(true)
		match mutation:
			"duplicate": bad.games.append(bad.games[0])
			"traversal": bad.games[0].id = "../../preferences"
			"host": bad.games[0].kif_source = "http://example.org/game.kif"
			"userinfo": bad.games[0].kif_source = "http://live.shogi.or.jp@example.org/game.kif"
			"query": bad.games[0].kif_source += "?redirect=http://localhost"
			"sha": bad.games[0].moves_sha256 = "incorrect"
			"fraction": bad.games[0].plies = 1.2
			"missing-tags": bad.games[0].tags.erase("先手")
			"open-game": bad.games[0].terminal = "中断"
		check(not Sync.valid_index(bad), "reject catalog " + mutation)
	for invalid in [null, [], {}, {"schema": 1, "updated_utc": "", "games": []}]: check(not Sync.valid_index(invalid), "invalid catalog shape")
	check(Download.decode("先手：藤井聡太\n後手：伊藤匠".to_utf8_buffer()) == "先手：藤井聡太\n後手：伊藤匠", "UTF8 Japanese")
	check(Download.decode("82a093af81408be228333129".hex_decode()) == "あ同　銀(31)", "CP932 fullwidth space and kanji")
	check(Download.decode("82".hex_decode()).is_empty(), "truncated CP932 rejected")
	check(Download.decode("827f".hex_decode()).is_empty(), "invalid CP932 trail rejected")
	var small = "先手：甲\n後手：乙\n開始日時：2026/09/01\n棋戦：テスト\n1 ７六歩(77) ( 0:01/0:01)\n2 ３四歩(33)\n3 同　銀(31)\n*comment\n4 投了"
	check(Download.normalize(small.to_utf8_buffer()).kif.contains("3 同銀(31)"), "same-square notation retains piece across Japanese whitespace")
	check(Download.normalize(("手合割：平手　　\n" + small).to_utf8_buffer()).tags["手合割"] == "平手", "official fullwidth handicap padding does not turn an even game into a handicap")
	check(not Download.normalize(small.to_utf8_buffer()).kif.contains("comment"), "editorial content stripped")
	check(Download.normalize(small.replace("4 投了", "4 中断").to_utf8_buffer()).is_empty(), "unfinished game rejected")
	check(Download.normalize(small.replace("2 ３四", "5 ３四").to_utf8_buffer()).is_empty(), "nonsequential moves rejected")
	var sync = MockSync.new()
	root.add_child(sync)
	sync.initialize(ProjectSettings.globalize_path("res://../.work/tournament-sync20-" + str(Time.get_ticks_usec())), false)
	var packaged = sync.entries().size()
	check(packaged >= 26, "offline recent index bundled")
	await sync.refresh()
	check(sync.requests.is_empty(), "automatic requests disabled in isolated tests")
	sync.responses.append({"ok": true, "body": JSON.stringify(index).to_utf8_buffer()})
	await sync.refresh(true)
	check(JSON.stringify(sync.index) == JSON.stringify(index) and sync.last_checked > 0, "valid refresh persists and sets timestamp")
	var cached_bytes = FileAccess.get_file_as_string(sync.storage.path_join("index.json"))
	sync.responses.append({"ok": true, "body": "{}".to_utf8_buffer()})
	await sync.refresh(true)
	check(JSON.stringify(sync.index) == JSON.stringify(index) and FileAccess.get_file_as_string(sync.storage.path_join("index.json")) == cached_bytes, "malformed update preserves memory and disk")
	sync.responses.append({"ok": false, "body": PackedByteArray()})
	await sync.refresh(true)
	check(JSON.stringify(sync.index) == JSON.stringify(index) and not sync.refreshing, "network failure retains catalog and releases busy flag")
	sync.automatic = true
	var count = sync.requests.size()
	await sync.refresh()
	check(sync.requests.size() == count, "daily throttle avoids repeat requests")
	var loaded: Array = []
	sync.game_ready.connect(func(game): loaded.append(game))
	sync.responses.append({"ok": true, "body": raw})
	await sync.open_game(entry)
	check(loaded.size() == 1 and loaded[0].moves.size() == entry.plies and not loaded[0].result.is_empty(), "download validates every move and final result")
	count = sync.requests.size()
	await sync.open_game(entry)
	check(loaded.size() == 2 and sync.requests.size() == count, "downloaded game reopens offline without network")
	check(sync._save(entry.id + ".json", {"kif": "corrupt"}), "atomic cache replacement works on Windows")
	check(sync.cached_game(entry) == null, "corrupt disk cache rejected")
	sync.responses.append({"ok": true, "body": small.to_utf8_buffer()})
	await sync.open_game(entry)
	check(loaded.size() == 2 and not sync.downloading, "wrong move hash cannot open or overwrite a game")
	var illegal = Download.normalize(small.to_utf8_buffer())
	var illegal_entry = entry.duplicate(true)
	illegal_entry.plies = illegal.plies; illegal_entry.moves_sha256 = illegal.moves_sha256
	check(sync._validated_game(illegal_entry, illegal) == null, "legal move validation rejects a hash-matching but impossible game")
	var restarted = MockSync.new()
	root.add_child(restarted)
	restarted.initialize(sync.storage, false)
	check(JSON.stringify(restarted.index) == JSON.stringify(index) and restarted.last_checked == sync.last_checked, "catalog and throttle survive restart")
	check(Historic.filter_entries(index.games, "", "全部赛事", str(entry.tags["開始日時"]).left(4)).size() == 1, "year filter supports dynamic recent dates")
	var result = {"checks": checks, "failures": failures}
	FileAccess.open(output.path_join("tournament-sync-tests.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print("TOURNAMENT SYNC: ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
