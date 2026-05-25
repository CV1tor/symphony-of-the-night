extends Node2D

const Rules = preload("res://scripts/BattleRules.gd")
const TimelineScript = preload("res://scripts/Timeline.gd")
const VIEWPORT_SIZE := Vector2(1280.0, 720.0)

enum BattleState {
	IDLE,
	RECORDING,
	DEFENDING,
	RESOLVING,
	GAME_OVER,
}

const PLAYER_INPUT_KEYS := {
	KEY_W: "up",
	KEY_D: "right",
	KEY_S: "down",
	KEY_A: "left",
	KEY_UP: "up",
	KEY_RIGHT: "right",
	KEY_DOWN: "down",
	KEY_LEFT: "left",
}

const INPUT_OWNERS := {
	KEY_W: 0,
	KEY_D: 0,
	KEY_S: 0,
	KEY_A: 0,
	KEY_UP: 1,
	KEY_RIGHT: 1,
	KEY_DOWN: 1,
	KEY_LEFT: 1,
}

var state := BattleState.IDLE
var active_player := 0
var defender_player := 1
var health := [Rules.STARTING_HEALTH, Rules.STARTING_HEALTH]
var sequence: Array[Dictionary] = []
var turn_ready_started_at := 0.0
var record_started_at := 0.0
var defend_started_at := 0.0
var pending_misses := 0

var timeline
var status_label: Label
var timer_label: Label
var feedback_label: Label
var role_label: Label
var controls_label: Label
var p1_health: ProgressBar
var p2_health: ProgressBar
var p1_panel: Panel
var p2_panel: Panel
var camera: Camera2D
var _shake_time := 0.0
var _shake_strength := 0.0


func _ready() -> void:
	_build_scene()
	Conductor.start_song()
	_begin_turn_ready_delay()


func _process(delta: float) -> void:
	if _shake_time > 0.0:
		_shake_time -= delta
		camera.offset = Vector2(randf_range(-_shake_strength, _shake_strength), randf_range(-_shake_strength, _shake_strength))
	else:
		camera.offset = Vector2.ZERO

	match state:
		BattleState.IDLE:
			var elapsed := Conductor.get_song_time() - turn_ready_started_at
			timer_label.text = "Ready: %.2fs" % maxf(Rules.TURN_READY_DELAY - elapsed, 0.0)
			if elapsed >= Rules.TURN_READY_DELAY:
				_start_recording()
		BattleState.RECORDING:
			var elapsed := Conductor.get_song_time() - record_started_at
			timer_label.text = "Record: %.2fs" % maxf(Rules.RECORD_DURATION - elapsed, 0.0)
			if elapsed >= Rules.RECORD_DURATION or sequence.size() >= Rules.MAX_SEQUENCE_INPUTS:
				_start_defending()
		BattleState.DEFENDING:
			var remaining := _defense_remaining_time()
			timer_label.text = "Defend: %.2fs" % maxf(remaining, 0.0)
			if remaining <= 0.0 and pending_misses <= 0:
				_finish_turn()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey

		if state == BattleState.GAME_OVER and key_event.keycode == KEY_ENTER:
			_restart_match()
			return

		if not PLAYER_INPUT_KEYS.has(key_event.keycode):
			return

		var input_owner := int(INPUT_OWNERS[key_event.keycode])
		var expected_player := _expected_input_player()
		if input_owner != expected_player:
			feedback_label.text = "P%d input ignored" % (input_owner + 1)
			return

		var key := String(PLAYER_INPUT_KEYS[key_event.keycode])
		if state == BattleState.RECORDING:
			_record_input(key)
		elif state == BattleState.DEFENDING:
			_defend_input(key)


func _build_scene() -> void:
	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.position = VIEWPORT_SIZE * 0.5
	camera.enabled = true
	add_child(camera)

	var root := Control.new()
	root.name = "BattleUI"
	root.size = VIEWPORT_SIZE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.055, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	status_label = _make_label(Vector2(40, 24), Vector2(780, 38), 28)
	root.add_child(status_label)

	role_label = _make_label(Vector2(40, 62), Vector2(680, 28), 20)
	role_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.92))
	root.add_child(role_label)

	controls_label = _make_label(Vector2(760, 62), Vector2(480, 28), 20)
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls_label.add_theme_color_override("font_color", Color(0.96, 0.82, 0.31))
	root.add_child(controls_label)

	timer_label = _make_label(Vector2(1040, 28), Vector2(200, 32), 24)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(timer_label)

	feedback_label = _make_label(Vector2(390, 560), Vector2(500, 48), 34)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(feedback_label)

	p1_panel = _make_player_panel(root, Vector2(70, 100), "Player 1", Color(0.23, 0.53, 1.0))
	p1_health = p1_panel.get_node("HealthBar")

	p2_panel = _make_player_panel(root, Vector2(850, 100), "Player 2", Color(0.94, 0.34, 0.26))
	p2_health = p2_panel.get_node("HealthBar")

	timeline = TimelineScript.new()
	timeline.name = "Timeline"
	timeline.note_missed.connect(_on_note_missed)
	add_child(timeline)

	_update_health_ui()


func _make_label(pos: Vector2, size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	return label


func _make_player_panel(parent: Control, pos: Vector2, title: String, accent: Color) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = Vector2(360, 190)
	parent.add_child(panel)

	var name_label := _make_label(Vector2(18, 14), Vector2(250, 34), 24)
	name_label.text = title
	panel.add_child(name_label)

	var portrait := ColorRect.new()
	portrait.position = Vector2(28, 62)
	portrait.size = Vector2(96, 96)
	portrait.color = accent
	panel.add_child(portrait)

	var staff := ColorRect.new()
	staff.position = Vector2(58, 36)
	staff.size = Vector2(10, 120)
	staff.color = Color(0.96, 0.82, 0.36)
	portrait.add_child(staff)

	var health_bar := ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.position = Vector2(145, 78)
	health_bar.size = Vector2(180, 30)
	health_bar.max_value = Rules.STARTING_HEALTH
	health_bar.value = Rules.STARTING_HEALTH
	health_bar.show_percentage = false
	panel.add_child(health_bar)

	return panel


func _begin_turn_ready_delay() -> void:
	state = BattleState.IDLE
	sequence.clear()
	timeline.clear_notes()
	_set_players(active_player, 1 - active_player)
	turn_ready_started_at = Conductor.get_song_time()
	status_label.text = "P%d get ready to attack (%s)" % [active_player + 1, _controls_for_player(active_player)]
	role_label.text = "Attacker: P%d  |  Defender: P%d" % [active_player + 1, defender_player + 1]
	controls_label.text = "Current controls: %s" % _controls_for_player(active_player)
	feedback_label.text = ""
	Conductor.play_sfx("turn_start")
	_highlight_active()


func _start_recording() -> void:
	state = BattleState.RECORDING
	sequence.clear()
	record_started_at = Conductor.get_song_time()
	timeline.clear_notes()
	feedback_label.text = ""
	_set_players(active_player, 1 - active_player)
	status_label.text = "P%d attacks: enter up to 6 notes (%s)" % [active_player + 1, _controls_for_player(active_player)]
	role_label.text = "Record a phrase: %.0f seconds, max %d notes" % [Rules.RECORD_DURATION, Rules.MAX_SEQUENCE_INPUTS]
	controls_label.text = "P%d input: %s" % [active_player + 1, _controls_for_player(active_player)]
	_highlight_active()


func _start_defending() -> void:
	state = BattleState.DEFENDING
	defend_started_at = Conductor.get_song_time()
	pending_misses = sequence.size()
	_set_players(active_player, 1 - active_player)
	status_label.text = "P%d defends: match the notes at the hit line (%s)" % [defender_player + 1, _controls_for_player(defender_player)]
	role_label.text = "Get ready: phrase starts after %.0fs" % Rules.DEFENSE_PHRASE_DELAY
	controls_label.text = "P%d input: %s" % [defender_player + 1, _controls_for_player(defender_player)]
	timeline.load_sequence(sequence, defend_started_at)
	_highlight_active()

	if sequence.is_empty():
		feedback_label.text = "No phrase recorded"
		_finish_turn()


func _finish_turn() -> void:
	if state == BattleState.GAME_OVER:
		return

	state = BattleState.RESOLVING
	active_player = 1 - active_player
	defender_player = 1 - active_player
	if state != BattleState.GAME_OVER:
		_begin_turn_ready_delay()


func _record_input(key: String) -> void:
	if sequence.size() >= Rules.MAX_SEQUENCE_INPUTS:
		return

	var timestamp := Conductor.get_song_time() - record_started_at
	if timestamp > Rules.RECORD_DURATION:
		return

	sequence.append({
		"timestamp": timestamp,
		"key": key,
	})
	feedback_label.text = "Recorded %s (%d/%d)" % [key.to_upper(), sequence.size(), Rules.MAX_SEQUENCE_INPUTS]
	Conductor.play_sfx("record_note")


func _defend_input(key: String) -> void:
	var note: Dictionary = timeline.get_pending_note_for_key(key)
	if note.is_empty():
		Conductor.play_sfx("wrong")
		_apply_damage(defender_player, Rules.DAMAGE_ON_MISS, "WRONG", "Wrong note")
		return

	var delta := Conductor.get_song_time() - float(note["timestamp"])
	var result: String = Rules.judge(delta)

	if result == "MISS":
		timeline.mark_resolved(int(note["index"]), "MISS")
		pending_misses -= 1
		Conductor.play_sfx("miss")
		_apply_damage(defender_player, Rules.DAMAGE_ON_MISS, "MISS", "Bad timing")
		return

	timeline.mark_resolved(int(note["index"]), result)
	pending_misses -= 1
	Conductor.play_sfx(result.to_lower())
	_show_feedback(result, Rules.RESULT_COLORS[result])


func _on_note_missed(note: Dictionary) -> void:
	if state != BattleState.DEFENDING:
		return

	timeline.mark_resolved(int(note["index"]), "OMISSION")
	pending_misses -= 1
	Conductor.play_sfx("omission")
	_apply_damage(defender_player, Rules.DAMAGE_ON_MISS, "OMISSION", "Missed note")


func _apply_damage(player_index: int, amount: int, reason: String, detail := "") -> void:
	health[player_index] = maxi(health[player_index] - amount, 0)
	_update_health_ui()
	var message := "%s - P%d takes %d" % [reason, player_index + 1, amount]
	if not detail.is_empty():
		message = "%s (%s)" % [message, detail]
	_show_feedback(message, Rules.RESULT_COLORS[reason])
	Conductor.play_sfx("damage")
	_shake(5.0, 0.12)

	if health[player_index] <= 0:
		_game_over(1 - player_index)


func _game_over(winner: int) -> void:
	state = BattleState.GAME_OVER
	timeline.clear_notes()
	status_label.text = "P%d wins! Press Enter to restart" % (winner + 1)
	role_label.text = "Match complete"
	controls_label.text = "Restart: Enter"
	timer_label.text = "Game Over"
	feedback_label.text = "Final blow"
	Conductor.play_sfx("game_over")


func _restart_match() -> void:
	health = [Rules.STARTING_HEALTH, Rules.STARTING_HEALTH]
	active_player = 0
	defender_player = 1
	_update_health_ui()
	_begin_turn_ready_delay()


func _set_players(attacker: int, defender: int) -> void:
	active_player = attacker
	defender_player = defender


func _expected_input_player() -> int:
	match state:
		BattleState.RECORDING:
			return active_player
		BattleState.DEFENDING:
			return defender_player
		_:
			return -1


func _controls_for_player(player_index: int) -> String:
	if player_index == 0:
		return "WASD"
	return "arrows"


func _defense_remaining_time() -> float:
	if sequence.is_empty():
		return 0.0

	var last_timestamp := 0.0
	for note in sequence:
		last_timestamp = maxf(last_timestamp, float(note["timestamp"]))

	return Rules.DEFENSE_PHRASE_DELAY + timeline.travel_time + last_timestamp + Rules.MISS_WINDOW - (Conductor.get_song_time() - defend_started_at)


func _update_health_ui() -> void:
	p1_health.value = health[0]
	p2_health.value = health[1]


func _show_feedback(message: String, color: Color) -> void:
	feedback_label.text = message
	feedback_label.add_theme_color_override("font_color", color)
	_flash(color)


func _highlight_active() -> void:
	p1_panel.modulate = Color.WHITE if active_player == 0 else Color(0.62, 0.62, 0.72)
	p2_panel.modulate = Color.WHITE if active_player == 1 else Color(0.62, 0.62, 0.72)


func _shake(strength: float, duration: float) -> void:
	_shake_strength = strength
	_shake_time = duration


func _flash(color: Color) -> void:
	var tween := create_tween()
	modulate = color
	tween.tween_property(self, "modulate", Color.WHITE, 0.12)
