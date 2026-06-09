extends Node2D

const Rules = preload("res://scripts/BattleRules.gd")

enum BattleState { IDLE, RECORDING, DEFENDING, RESOLVING, GAME_OVER }

const PLAYER_INPUT_KEYS := {
	KEY_W: "up", KEY_D: "right", KEY_S: "down", KEY_A: "left",
	KEY_UP: "up", KEY_RIGHT: "right", KEY_DOWN: "down", KEY_LEFT: "left",
}

const INPUT_OWNERS := {
	KEY_W: 0, KEY_D: 0, KEY_S: 0, KEY_A: 0,
	KEY_UP: 1, KEY_RIGHT: 1, KEY_DOWN: 1, KEY_LEFT: 1,
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

@onready var timeline: Timeline = $Timeline
@onready var feedback_label: Label = $BattleUI/FeedbackLabel
@onready var countdown_label: Label = $BattleUI/CountdownLabel
@onready var p1_health: ProgressBar = $BattleUI/HealthBars/P1HealthPanel/HealthBar
@onready var p2_health: ProgressBar = $BattleUI/HealthBars/P2HealthPanel/HealthBar
@onready var p1_panel: Control = $BattleUI/PlayerStages/Player1Stage
@onready var p2_panel: Control = $BattleUI/PlayerStages/Player2Stage
@onready var camera: Camera2D = $Camera2D
@onready var player_sprites: Array[AnimatedSprite2D] = [
	$BattleUI/PlayerStages/Player1Stage/CharacterSprite,
	$BattleUI/PlayerStages/Player2Stage/CharacterSprite,
]

var _animation_tokens := [0, 0]
var _shake_time := 0.0
var _shake_strength := 0.0

func _ready() -> void:
	timeline.note_missed.connect(_on_note_missed)
	_update_health_ui()
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
			var remaining := maxf(Rules.TURN_READY_DELAY - (Conductor.get_song_time() - turn_ready_started_at), 0.0)
			_update_countdown(remaining)
			if remaining <= 0.0: _start_recording()
		BattleState.RECORDING:
			if Conductor.get_song_time() - record_started_at >= Rules.RECORD_DURATION or sequence.size() >= Rules.MAX_SEQUENCE_INPUTS:
				_start_defending()
		BattleState.DEFENDING:
			if _defense_remaining_time() <= 0.0 and pending_misses <= 0:
				_finish_turn()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if state == BattleState.GAME_OVER and key_event.keycode == KEY_ENTER:
			_restart_match()
			return

		if not PLAYER_INPUT_KEYS.has(key_event.keycode): return

		var input_owner := int(INPUT_OWNERS[key_event.keycode])
		if input_owner != _expected_input_player():
			feedback_label.text = "P%d input ignored" % (input_owner + 1)
			return

		var key := String(PLAYER_INPUT_KEYS[key_event.keycode])
		if state == BattleState.RECORDING: _record_input(key)
		elif state == BattleState.DEFENDING: _defend_input(key)

func _begin_turn_ready_delay() -> void:
	state = BattleState.IDLE
	sequence.clear()
	timeline.clear_notes()
	turn_ready_started_at = Conductor.get_song_time()
	feedback_label.text = ""
	Conductor.play_sfx("turn_start")
	_highlight_active()
	_update_character_states()

func _start_recording() -> void:
	state = BattleState.RECORDING
	record_started_at = Conductor.get_song_time()
	countdown_label.visible = false
	_update_character_states()

func _start_defending() -> void:
	state = BattleState.DEFENDING
	defend_started_at = Conductor.get_song_time()
	pending_misses = sequence.size()
	timeline.set_display_player(defender_player)
	timeline.load_sequence(sequence, defend_started_at)
	_update_character_states()
	if sequence.is_empty(): _finish_turn()

func _finish_turn() -> void:
	if state == BattleState.GAME_OVER: return
	state = BattleState.RESOLVING
	active_player = 1 - active_player
	defender_player = 1 - active_player
	_begin_turn_ready_delay()

func _record_input(key: String) -> void:
	if sequence.size() >= Rules.MAX_SEQUENCE_INPUTS: return
	sequence.append({"timestamp": Conductor.get_song_time() - record_started_at, "key": key})
	feedback_label.text = "Recorded %s (%d/%d)" % [key.to_upper(), sequence.size(), Rules.MAX_SEQUENCE_INPUTS]
	Conductor.play_note_sfx(active_player, key)
	_play_temporary_animation(active_player, "record", 0.28)

func _defend_input(key: String) -> void:
	var note: Dictionary = timeline.get_pending_note_for_key(key)
	if note.is_empty():
		Conductor.play_sfx("wrong")
		_apply_damage(defender_player, Rules.DAMAGE_ON_MISS, "WRONG")
		return

	var delta := Conductor.get_song_time() - float(note["timestamp"])
	var result: String = Rules.judge(delta)
	timeline.mark_resolved(int(note["index"]), result)
	pending_misses -= 1

	if result == "MISS":
		Conductor.play_sfx("miss")
		_apply_damage(defender_player, Rules.DAMAGE_ON_MISS, "MISS")
	else:
		Conductor.play_note_sfx(defender_player, key)
		_play_temporary_animation(defender_player, "record", 0.2) # Feedback de toque
		if result != "PERFECT": Conductor.pulse_music_distortion()
		_show_feedback(result, Rules.RESULT_COLORS[result])

func _on_note_missed(note: Dictionary) -> void:
	if state != BattleState.DEFENDING: return
	timeline.mark_resolved(int(note["index"]), "OMISSION")
	pending_misses -= 1
	Conductor.play_sfx("omission")
	_apply_damage(defender_player, Rules.DAMAGE_ON_MISS, "OMISSION")

func _apply_damage(player_index: int, amount: int, reason: String) -> void:
	health[player_index] = maxi(health[player_index] - amount, 0)
	_update_health_ui()
	Conductor.pulse_music_distortion()
	_show_feedback("%s - P%d takes %d" % [reason, player_index + 1, amount], Rules.RESULT_COLORS[reason])
	Conductor.play_sfx("damage")
	_play_temporary_animation(player_index, "hit", 0.35)
	_shake(5.0, 0.12)
	if health[player_index] <= 0: _game_over(1 - player_index)

func _game_over(winner: int) -> void:
	state = BattleState.GAME_OVER
	timeline.clear_notes()
	feedback_label.text = "P%d wins! Enter to restart" % (winner + 1)
	Conductor.play_sfx("game_over")
	_set_player_animation(winner, "idle")
	_set_player_animation(1 - winner, "death")

func _restart_match() -> void:
	health = [Rules.STARTING_HEALTH, Rules.STARTING_HEALTH]
	active_player = 0
	defender_player = 1
	_update_health_ui()
	_begin_turn_ready_delay()

func _expected_input_player() -> int:
	return active_player if state == BattleState.RECORDING else defender_player if state == BattleState.DEFENDING else -1

func _defense_remaining_time() -> float:
	if sequence.is_empty(): return 0.0
	var last_t := 0.0
	for n in sequence: last_t = maxf(last_t, float(n["timestamp"]))
	return Rules.DEFENSE_PHRASE_DELAY + timeline.travel_time + last_t + Rules.MISS_WINDOW - (Conductor.get_song_time() - defend_started_at)

func _update_health_ui() -> void:
	p1_health.value = health[0]
	p2_health.value = health[1]

func _update_countdown(remaining: float) -> void:
	var count := clampi(int(ceil(remaining)), 1, int(Rules.TURN_READY_DELAY))
	countdown_label.text = "PLAYER %d\n%d" % [active_player + 1, count]
	countdown_label.visible = remaining > 0.0

func _update_character_states() -> void:
	for i in 2: _set_player_animation(i, "death" if health[i] <= 0 else "idle")

func _play_temporary_animation(player_index: int, anim: String, duration: float) -> void:
	if health[player_index] <= 0: return
	_animation_tokens[player_index] += 1
	var token := int(_animation_tokens[player_index])
	_set_player_animation(player_index, anim, true)
	get_tree().create_timer(duration).timeout.connect(func():
		if state != BattleState.GAME_OVER and health[player_index] > 0 and _animation_tokens[player_index] == token:
			_update_character_states()
	)

func _set_player_animation(idx: int, anim: String, restart := false) -> void:
	var sprite := player_sprites[idx]
	if sprite.sprite_frames.has_animation(anim) and (restart or sprite.animation != anim):
		sprite.play(anim)

func _show_feedback(msg: String, color: Color) -> void:
	feedback_label.text = msg
	feedback_label.add_theme_color_override("font_color", color)
	var tw := create_tween()
	modulate = color
	tw.tween_property(self, "modulate", Color.WHITE, 0.12)

func _highlight_active() -> void:
	var active := defender_player if state == BattleState.DEFENDING else active_player
	p1_panel.modulate = Color.WHITE if active == 0 else Color(0.6, 0.6, 0.7)
	p2_panel.modulate = Color.WHITE if active == 1 else Color(0.6, 0.6, 0.7)

func _shake(str: float, dur: float) -> void:
	_shake_strength = str
	_shake_time = dur
