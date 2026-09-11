extends Node
## Owns one isolated parser. Only the main thread consumes its completed result.
signal completed(result: Dictionary)
var worker: Thread

func begin(source: String) -> Error:
	worker = Thread.new()
	var error = worker.start(func():
		var parser = preload("res://scripts/shogi_exchange.gd").new()
		var game = parser.parse(source)
		return {"game": game, "error": parser.error}
	)
	if error != OK: worker = null
	return error

func _process(_delta: float) -> void:
	if worker == null or worker.is_alive(): return
	var result = worker.wait_to_finish()
	worker = null
	completed.emit(result)
	queue_free()

func _exit_tree() -> void:
	if worker != null and worker.is_started(): worker.wait_to_finish()
	worker = null
