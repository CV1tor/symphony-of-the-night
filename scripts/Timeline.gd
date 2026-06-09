extends Node2D
class_name Timeline

signal note_missed(note)

const Rules = preload("res://scripts/BattleRules.gd")
const LANE_KEYS := ["up", "right", "left", "down"]
const PLAYER_KEY_LABELS := [
	{"up": "W", "right": "D", "down": "S", "left": "A"},
	{"up": "↑", "right": "→", "down": "↓", "left": "←"}
]

@export var pixel_font: Font

var travel_time := 1.35
var note_speed := 420.0
var target_x := 350.0
var spawn_x := 920.0
var base_y := 610.0
var lane_gap := 34.0
var result_hold_time := 0.75

var notes: Array[Dictionary] = []
var _missed_indices: Dictionary = {}
var display_player := 0

func set_display_player(idx: int) -> void:
	display_player = clampi(idx, 0, PLAYER_KEY_LABELS.size() - 1)
	queue_redraw()

func load_sequence(seq: Array, start_time: float) -> void:
	notes.clear()
	_missed_indices.clear()
	for i in seq.size():
		notes.append({
			"key": seq[i]["key"],
			"timestamp": start_time + Rules.DEFENSE_PHRASE_DELAY + travel_time + float(seq[i]["timestamp"]),
			"index": i,
			"resolved": false,
			"result": "",
			"resolved_at": -1.0,
		})
	queue_redraw()

func clear_notes() -> void:
	notes.clear()
	_missed_indices.clear()
	queue_redraw()

func mark_resolved(idx: int, result := "HIT") -> void:
	for n in notes:
		if int(n["index"]) == idx:
			n["resolved"] = true
			n["result"] = result
			n["resolved_at"] = Conductor.get_song_time()
			break
	queue_redraw()

func get_pending_note_for_key(key: String) -> Dictionary:
	var best := {}
	var min_delta := INF
	var now := Conductor.get_song_time()
	for n in notes:
		if n["resolved"] or n["key"] != key: continue
		var delta := absf(now - n["timestamp"])
		if delta < min_delta:
			min_delta = delta
			best = n
	return best

func _process(_delta: float) -> void:
	var now := Conductor.get_song_time()
	for n in notes:
		var idx := int(n["index"])
		if n["resolved"] or _missed_indices.has(idx): continue
		if now - n["timestamp"] > Rules.MISS_WINDOW:
			_missed_indices[idx] = true
			note_missed.emit(n)
	queue_redraw()

func _draw() -> void:
	var font := pixel_font if pixel_font else ThemeDB.fallback_font
	
	# Lane targets (Keyboard style)
	for i in LANE_KEYS.size():
		var key: String = LANE_KEYS[i]
		var y := _lane_y(key)
		var size := 36.0
		var color := Color(1, 1, 1, 0.9)
		draw_rect(Rect2(Vector2(target_x - size/2, y - size/2), Vector2(size, size)), Color(0, 0, 0, 0.4), true)
		draw_rect(Rect2(Vector2(target_x - size/2, y - size/2), Vector2(size, size)), color, false, 2.0)
		var label := String(PLAYER_KEY_LABELS[display_player][key])
		var l_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		draw_string(font, Vector2(target_x - l_size.x/2, y + l_size.y/4 + 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)

	# Active notes
	var now := Conductor.get_song_time()
	for n in notes:
		if n["resolved"] and now - n["resolved_at"] > result_hold_time: continue
		var x: float = target_x + (float(n["timestamp"]) - now) * note_speed
		if x < 190.0 or x > spawn_x + 120.0: continue
		var y := _lane_y(n["key"])
		var color := _note_color(n)
		
		draw_rect(Rect2(Vector2(x - 15, y - 15), Vector2(30, 30)), color, true)
		draw_rect(Rect2(Vector2(x - 15, y - 15), Vector2(30, 30)), Color.WHITE, false, 2.0)
		var label := String(PLAYER_KEY_LABELS[display_player][n["key"]])
		draw_string(font, Vector2(x - 7, y + 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0))
		
		if n["resolved"]:
			draw_string(font, Vector2(x - 26, y - 22), String(n["result"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)

func _lane_y(key: String) -> float:
	return base_y - 51.0 + float(LANE_KEYS.find(key)) * lane_gap

func _note_color(n: Dictionary) -> Color:
	if n["resolved"] and Rules.RESULT_COLORS.has(n["result"]):
		return Rules.RESULT_COLORS[n["result"]]
	match n["key"]:
		"up": return Color(0.4, 1.0, 0.8)
		"right": return Color(1.0, 0.8, 0.3)
		"down": return Color(1.0, 0.4, 0.3)
		"left": return Color(0.4, 0.7, 1.0)
	return Color.WHITE
