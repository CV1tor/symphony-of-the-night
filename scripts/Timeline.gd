extends Node2D
class_name Timeline

signal note_missed(note)

const Rules = preload("res://scripts/BattleRules.gd")
const LANE_KEYS := ["up", "right", "left", "down"]

var travel_time := 1.35
var note_speed := 520.0
var target_x := 280.0
var spawn_x := 980.0
var base_y := 430.0
var lane_gap := 54.0
var result_hold_time := 0.75
var notes: Array[Dictionary] = []
var _missed_indices: Dictionary = {}


func load_sequence(sequence: Array, start_time: float) -> void:
	notes.clear()
	_missed_indices.clear()

	for index in sequence.size():
		var source: Dictionary = sequence[index]
		var note := {
			"key": source["key"],
			"timestamp": start_time + Rules.DEFENSE_PHRASE_DELAY + travel_time + float(source["timestamp"]),
			"recorded_timestamp": float(source["timestamp"]),
			"index": index,
			"resolved": false,
			"result": "",
			"resolved_at": -1.0,
		}
		notes.append(note)

	queue_redraw()


func clear_notes() -> void:
	notes.clear()
	_missed_indices.clear()
	queue_redraw()


func mark_resolved(index: int, result := "HIT") -> void:
	for note in notes:
		if int(note["index"]) == index:
			note["resolved"] = true
			note["result"] = result
			note["resolved_at"] = Conductor.get_song_time()
			break
	queue_redraw()


func get_pending_note_for_key(key: String) -> Dictionary:
	var best_note := {}
	var best_delta := INF
	var now := Conductor.get_song_time()

	for note in notes:
		if bool(note["resolved"]):
			continue
		if String(note["key"]) != key:
			continue

		var delta := absf(now - float(note["timestamp"]))
		if delta < best_delta:
			best_delta = delta
			best_note = note

	return best_note


func _process(_delta: float) -> void:
	var now := Conductor.get_song_time()

	for note in notes:
		var index := int(note["index"])
		if bool(note["resolved"]) or _missed_indices.has(index):
			continue

		if now - float(note["timestamp"]) > Rules.MISS_WINDOW:
			_missed_indices[index] = true
			note_missed.emit(note)

	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2(0, base_y - 135.0), Vector2(1280.0, 270.0)), Color(0.07, 0.08, 0.13, 0.92), true)
	_draw_beat_markers()
	draw_line(Vector2(target_x, base_y - 118.0), Vector2(target_x, base_y + 118.0), Color(0.95, 0.85, 0.28), 4.0)
	draw_string(ThemeDB.fallback_font, Vector2(target_x - 34.0, base_y - 132.0), "HIT", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color.WHITE)

	for lane_index in LANE_KEYS.size():
		var y := _lane_y(LANE_KEYS[lane_index])
		draw_line(Vector2(80.0, y), Vector2(1180.0, y), Color(0.28, 0.30, 0.42), 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(88.0, y - 12.0), LANE_KEYS[lane_index].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(0.78, 0.82, 0.92))

	var now := Conductor.get_song_time()
	for note in notes:
		if bool(note["resolved"]) and now - float(note["resolved_at"]) > result_hold_time:
			continue

		var key := String(note["key"])
		var note_time := float(note["timestamp"])
		var x := target_x + (note_time - now) * note_speed
		var y := _lane_y(key)
		if x < 40.0 or x > spawn_x + 160.0:
			continue

		var color := _note_color(note)
		draw_rect(Rect2(Vector2(x - 19.0, y - 19.0), Vector2(38.0, 38.0)), color, true)
		draw_rect(Rect2(Vector2(x - 19.0, y - 19.0), Vector2(38.0, 38.0)), Color.WHITE, false, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(x - 10.0, y + 7.0), _key_label(key), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(0.05, 0.06, 0.09))

		if bool(note["resolved"]):
			draw_string(ThemeDB.fallback_font, Vector2(x - 30.0, y - 28.0), String(note["result"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color.WHITE)


func _draw_beat_markers() -> void:
	var beat_duration := Conductor.get_beat_duration()
	var now := Conductor.get_song_time()
	var first_beat := int(floor((now - 0.5) / beat_duration))
	var last_beat := int(ceil((now + 2.2) / beat_duration))

	for beat in range(first_beat, last_beat + 1):
		var beat_time := float(beat) * beat_duration
		var x := target_x + (beat_time - now) * note_speed
		if x < 80.0 or x > 1180.0:
			continue

		var color := Color(0.36, 0.39, 0.52, 0.65)
		var width := 1.0
		if beat % 4 == 0:
			color = Color(0.72, 0.74, 0.86, 0.8)
			width = 2.0
		draw_line(Vector2(x, base_y - 118.0), Vector2(x, base_y + 118.0), color, width)


func _lane_y(key: String) -> float:
	var lane := LANE_KEYS.find(key)
	if lane == -1:
		lane = 0
	return base_y - 78.0 + float(lane) * lane_gap


func _key_color(key: String) -> Color:
	match key:
		"up":
			return Color(0.42, 0.95, 0.82)
		"right":
			return Color(0.96, 0.82, 0.31)
		"down":
			return Color(0.95, 0.36, 0.27)
		"left":
			return Color(0.45, 0.66, 1.0)
		_:
			return Color.WHITE


func _note_color(note: Dictionary) -> Color:
	if bool(note["resolved"]):
		var result := String(note["result"])
		if Rules.RESULT_COLORS.has(result):
			return Rules.RESULT_COLORS[result]
	return _key_color(String(note["key"]))


func _key_label(key: String) -> String:
	match key:
		"up":
			return "U"
		"right":
			return "R"
		"down":
			return "D"
		"left":
			return "L"
		_:
			return "?"
