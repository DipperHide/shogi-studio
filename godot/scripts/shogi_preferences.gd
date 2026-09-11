class_name ShogiPreferences
extends RefCounted

const PATH = "user://preferences.cfg"
var confirm_move: bool = false
var sound: bool = true
var volume: float = 0.55
var hints: bool = true
var last_move: bool = true
var coordinates: bool = false
var auto_flip: bool = false
var appearance: String = "anime2d"
var color_mode: String = "dark"
var language: String = "zh"
var piece_font: String = "mincho"
var move_pace: int = 1
var report: Dictionary = preload("res://scripts/shogi_report_settings.gd").DEFAULTS.duplicate()
var studio: Dictionary = {"board_theme": "classic", "custom_color": "ddbc8b", "analysis_lines": 3, "threads": 2, "hash": 64, "arrows": true, "eval_bar": true, "animation": 0.22, "autoplay": 1.0, "threats": false, "username": "你", "drag": true}

func _init() -> void:
	studio["bad_move_warning"] = true
	studio["win_rate"] = true
	studio["report_cpl"] = false
	studio["variation_policy"] = "replace"
	studio["variation_policy_confirmed"] = false
	studio["eval_position"] = "smart"
	studio["editor_eval_bar"] = true
	studio["editor_eval_running"] = true
	studio["editor_positions"] = []
	studio["analysis_tab"] = 0
	var locale = OS.get_locale_language()
	language = locale if locale in ["ja", "en"] else "zh"

func is_dark() -> bool:
	if color_mode != "system":
		return color_mode == "dark"
	if OS.get_name() == "Android" and Engine.has_singleton("ShogiPlatform"):
		var platform = Engine.get_singleton("ShogiPlatform")
		if platform.has_method("isDarkMode"): return platform.isDarkMode()
	return DisplayServer.is_dark_mode() if DisplayServer.is_dark_mode_supported() else true

func load_from(path: String = PATH) -> void:
	var config = ConfigFile.new()
	if config.load(path) != OK:
		return
	var report_value = config.get_value("preferences", "report", {})
	if report_value is Dictionary: report = preload("res://scripts/shogi_report_settings.gd").normalized(report_value)
	var extra = config.get_value("preferences", "studio", {})
	if extra is Dictionary:
		for key in studio:
			if not extra.has(key): continue
			if typeof(extra[key]) == typeof(studio[key]): studio[key] = extra[key]
			elif studio[key] is int and extra[key] is float and is_finite(extra[key]) and int(extra[key]) == extra[key]: studio[key] = int(extra[key])
	studio.analysis_lines = clampi(studio.analysis_lines, 1, 5)
	studio.threads = clampi(studio.threads, 1, 8)
	studio.hash = clampi(studio.hash, 16, 512)
	studio.animation = clampf(studio.animation, 0, 1)
	studio.autoplay = clampf(studio.autoplay, 0.3, 5)
	if studio.variation_policy not in ["replace", "never"]: studio.variation_policy = "replace"
	if studio.eval_position not in ["smart", "left", "bottom", "left_on_game_report"]: studio.eval_position = "smart"
	studio.editor_positions = preload("res://scripts/shogi_editor_history.gd").normalized(studio.editor_positions)
	studio.analysis_tab = clampi(studio.analysis_tab, 0, 1)
	for key in ["confirm_move","sound","hints","last_move","coordinates","auto_flip"]:
		var value = config.get_value("preferences",key,get(key))
		if value is bool:
			set(key,value)
	var value = config.get_value("preferences","volume",volume)
	if (value is int or value is float) and is_finite(float(value)):
		volume = clampf(float(value),0,1)
	for key in {"appearance": ["anime2d", "minimal", "wood"], "color_mode": ["system", "light", "dark"], "language": ["zh", "ja", "en"], "piece_font": ["ryoko", "mincho"]}:
		var allowed = {"appearance": ["anime2d", "minimal", "wood"], "color_mode": ["system", "light", "dark"], "language": ["zh", "ja", "en"], "piece_font": ["ryoko", "mincho"]}[key]
		var saved = config.get_value("preferences", key, get(key))
		if saved in allowed: set(key, saved)
	if int(config.get_value("preferences", "ui_version", 0)) < 7 and appearance == "minimal":
		appearance = "anime2d"
		piece_font = "mincho"
	var pace = config.get_value("preferences", "move_pace", 1)
	if (pace is int or pace is float) and pace in [0, 1, 2]: move_pace = int(pace)

func save_to(path: String = PATH) -> Error:
	var config = ConfigFile.new()
	for key in ["confirm_move","sound","volume","hints","last_move","coordinates","auto_flip", "appearance", "color_mode", "language", "piece_font", "move_pace"]:
		config.set_value("preferences",key,get(key))
	config.set_value("preferences", "ui_version", 7)
	config.set_value("preferences", "studio", studio)
	config.set_value("preferences", "report", report)
	return config.save(path)
