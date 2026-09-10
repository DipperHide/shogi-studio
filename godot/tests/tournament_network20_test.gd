extends SceneTree
const Sync = preload("res://scripts/shogi_tournament_sync.gd")
const Download = preload("res://scripts/shogi_kif_download.gd")
var checks = 0
var failures = []
var evidence = []

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var sync = Sync.new()
	root.add_child(sync)
	sync.initialize(ProjectSettings.globalize_path("res://../.work/tournament-network20"), false)
	for entry in sync.entries():
		var response = await sync._request(entry.kif_source, 2097152)
		checks += 1
		if not response.ok: failures.append(entry.id + " download failed"); continue
		var normalized = Download.normalize(response.body)
		checks += 1
		if normalized.get("moves_sha256", "") != entry.moves_sha256: failures.append(entry.id + " hash mismatch"); continue
		var game = sync._validated_game(entry, normalized)
		checks += 1
		if game == null: failures.append(entry.id + " illegal game"); continue
		evidence.append({"id": entry.id, "plies": game.moves.size(), "winner": game.winner, "result": game.result_code, "final_sfen": preload("res://scripts/shogi_usi_codec.gd").sfen(game.position), "source": entry.source})
		print("VERIFIED CURRENT ", entry.id, " ", game.moves.size())
	var directory = ProjectSettings.globalize_path("res://../review/app/chessis20")
	DirAccess.make_dir_recursive_absolute(directory)
	var result = {"checks": checks, "failures": failures, "games": evidence.size(), "evidence": evidence}
	FileAccess.open(directory.path_join("tournament-network-tests.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print("TOURNAMENT NETWORK: ", evidence.size(), " games; ", checks, " checks; failures: ", failures)
	quit(0 if failures.is_empty() and evidence.size() == sync.entries().size() else 1)
