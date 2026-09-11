extends SceneTree
const Filter = preload("res://scripts/shogi_tournament_filter.gd")
const Historic = preload("res://scripts/shogi_historic_games.gd")
const Download = preload("res://scripts/shogi_kif_download.gd")
const Job = preload("res://scripts/shogi_tournament_job.gd")
var checks = 0
var failures = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL: ",label)

func _init() -> void:
	var entries = Historic.entries()
	var original = JSON.stringify(entries)
	var options = Filter.options(entries)
	check(options.events.size() == 5 and options.years.front() == "2022" and options.years.back() == "2016", "derive options from complete offline collection")
	check(Filter.select(entries,"",[],"").size() == 195, "empty filter retains all 195 games")
	check(Filter.select(entries,"　 \t",[],"") == entries, "whitespace search retains ordering and every game")
	var first_event = options.events[0]; var second_event = options.events[1]
	var first = Historic.search("",first_event); var second = Historic.search("",second_event)
	var union = Filter.select(entries,"",[first_event,second_event],"")
	check(union.size() == first.size()+second.size(), "two events are combined with OR")
	check(Filter.select(entries,"",[first_event,first_event],"").size() == first.size(), "duplicate selected event never duplicates games")
	for event in options.events:
		for year in options.years:
			check(Filter.select(entries,"",[event],year) == Historic.search("",event,year), "event and year combine with AND: " + event + year)
	check(Filter.select(entries,"不存在的棋手",[],"").is_empty(), "honest empty search")
	check(Filter.select(entries,"",["未公开赛事"],"").is_empty(), "unknown selected event does not broaden filter")
	check(Filter.select(entries,"",[],"2099").is_empty(), "unavailable year does not broaden filter")
	check(Filter.select(entries,"藤井聪太",[],"") == Filter.select(entries,"藤井聡太",[],""), "simplified and Japanese name variants match")
	var words = Filter.select(entries,"藤井 棋圣",[],"")
	check(not words.is_empty() and words.all(func(item): return Historic.event_name(item) == "棋圣战"), "two search terms require both player and event")
	check(Filter.select(entries,"藤井　棋圣",[],"") == words, "Japanese whitespace separates search terms")
	for pair in [[1,"1 投了","先手胜"],[2,"3 投了","后手胜"],[3,"4 詰み","先手胜"],[4,"5 切れ負け","后手胜"],[5,"6 千日手","千日手"],[6,"7 持将棋","持将棋"],[1,"2 中断","结果未注明"]]:
		check(Filter.outcome({"plies":pair[0],"terminal":pair[1]}) == pair[2], "terminal result " + pair[1])
	var source = entries[0]
	var normalized = Download.normalize(source.kif.to_utf8_buffer())
	check(Job.validate(source,normalized) != null, "private worker validator accepts full official game")
	var broken = normalized.duplicate(); broken.plies += 1
	check(Job.validate(source,broken) == null, "private validator rejects wrong ply count")
	var hashed = source.duplicate(); hashed.moves_sha256 = "incorrect"
	check(Job.validate(hashed,normalized) == null, "private validator rejects wrong move digest")
	check(JSON.stringify(entries) == original, "filter and validator preserve source metadata and records")
	var directory = ProjectSettings.globalize_path("res://../review/app/chessis31")
	DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join("tournament-core.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("TOURNAMENT31: ",checks," checks, failures: ",failures)
	quit(0 if failures.is_empty() else 1)
