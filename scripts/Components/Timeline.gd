extends Node2D

signal noteMissed(note: Dictionary)

const Rules = preload("res://scripts/Battle/BattleRules.gd")
const NoteScene = preload("res://scenes/Components/Note.tscn")

const LANE_KEYS := ["up", "right", "left", "down"]
const PLAYER_KEY_LABELS := [
	{"up": "W", "right": "D", "down": "S", "left": "A"},
	{"up": "↑", "right": "→", "down": "↓", "left": "←"}
]

@onready var laneTargets := $LaneTargets
@onready var notesContainer := $NotesContainer

var travelTime := 1.35
var noteSpeed := 420.0
var targetX := 350.0
var spawnX := 917.0
var baseY := 559.0
var laneGap := 34.0
var resultHoldTime := 0.75

var notes: Array[Dictionary] = []
var _missedIndices: Dictionary = {}
var displayPlayer := 0

func setDisplayPlayer(idx: int) -> void:
	displayPlayer = clampi(idx, 0, PLAYER_KEY_LABELS.size() - 1)
	_updateLaneLabels()

func loadSequence(seq: Array, startTime: float) -> void:
	clearNotes()
	for i in seq.size():
		var noteData = {
			"key": seq[i]["key"],
			"timestamp": startTime + Rules.DEFENSE_PHRASE_DELAY + travelTime + float(seq[i]["timestamp"]),
			"index": i,
			"resolved": false,
			"result": "",
			"resolvedAt": -1.0,
			"node": null
		}
		
		var noteNode = NoteScene.instantiate()
		noteNode.get_node("Background").color = _getNoteColor(noteData["key"])
		noteNode.get_node("Label").text = PLAYER_KEY_LABELS[displayPlayer][noteData["key"]]
		notesContainer.add_child(noteNode)
		noteData["node"] = noteNode
		
		notes.append(noteData)

func clearNotes() -> void:
	for n in notes:
		if is_instance_valid(n["node"]):
			n["node"].queue_free()
	notes.clear()
	_missedIndices.clear()

func markResolved(idx: int, result := "HIT") -> void:
	for n in notes:
		if int(n["index"]) == idx:
			n["resolved"] = true
			n["result"] = result
			n["resolvedAt"] = Conductor.getSongTime()
			if is_instance_valid(n["node"]):
				var node: Control = n["node"]
				node.get_node("ResultLabel").text = result
				node.get_node("ResultLabel").visible = true
				if Rules.RESULT_COLORS.has(result):
					node.get_node("Background").color = Rules.RESULT_COLORS[result]
			break

func getPendingNoteForKey(key: String) -> Dictionary:
	var best := {}
	var minDelta := INF
	var now := Conductor.getSongTime()
	for n in notes:
		if n["resolved"] or n["key"] != key: continue
		var delta := absf(now - n["timestamp"])
		if delta < minDelta:
			minDelta = delta
			best = n
	return best

func _process(_delta: float) -> void:
	var now := Conductor.getSongTime()
	for n in notes:
		var idx := int(n["index"])
		
		# Handle misses
		if not n["resolved"] and not _missedIndices.has(idx):
			if now - n["timestamp"] > Rules.MISS_WINDOW:
				_missedIndices[idx] = true
				noteMissed.emit(n)
		
		# Update positions
		if is_instance_valid(n["node"]):
			var node: Control = n["node"]
			if n["resolved"] and now - n["resolvedAt"] > resultHoldTime:
				node.visible = false
			else:
				var x: float = targetX + (float(n["timestamp"]) - now) * noteSpeed
				node.position = Vector2(x, _laneY(n["key"]))
				node.visible = true

func _updateLaneLabels() -> void:
	var labels: Dictionary = PLAYER_KEY_LABELS[displayPlayer]
	laneTargets.get_node("Up/Label").text = labels["up"]
	laneTargets.get_node("Right/Label").text = labels["right"]
	laneTargets.get_node("Left/Label").text = labels["left"]
	laneTargets.get_node("Down/Label").text = labels["down"]

func _laneY(key: String) -> float:
	return baseY + float(LANE_KEYS.find(key)) * laneGap

func _getNoteColor(key: String) -> Color:
	match key:
		"up": return Color(0.4, 1.0, 0.8)
		"right": return Color(1.0, 0.8, 0.3)
		"down": return Color(1.0, 0.4, 0.3)
		"left": return Color(0.4, 0.7, 1.0)
	return Color.WHITE
