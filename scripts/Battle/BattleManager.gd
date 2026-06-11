extends Node2D

const Rules = preload("res://scripts/Battle/BattleRules.gd")

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
var activePlayer := 0
var defenderPlayer := 1
var health := [Rules.STARTING_HEALTH, Rules.STARTING_HEALTH]
var sequence: Array[Dictionary] = []
var turnReadyStartedAt := 0.0
var recordStartedAt := 0.0
var defendStartedAt := 0.0
var pendingMisses := 0

@onready var timeline: Node2D = %Timeline
@onready var feedbackLabel: Label = %FeedbackLabel
@onready var countdownLabel: Label = %CountdownLabel
@onready var p1Health: ProgressBar = %P1HealthPanel/HealthBar
@onready var p2Health: ProgressBar = %P2HealthPanel/HealthBar
@onready var p1Panel: Control = %Player1Stage
@onready var p2Panel: Control = %Player2Stage
@onready var camera: Camera2D = $Camera2D
@onready var playerSprites: Array[AnimatedSprite2D] = [
	%Player1Stage/CharacterSprite,
	%Player2Stage/CharacterSprite,
]

var _animationTokens := [0, 0]
var _shakeTime := 0.0
var _shakeStrength := 0.0

func _ready() -> void:
	timeline.noteMissed.connect(_onNoteMissed)
	_updateHealthUi()
	Conductor.startSong()
	_beginTurnReadyDelay()

func _process(delta: float) -> void:
	if _shakeTime > 0.0:
		_shakeTime -= delta
		camera.offset = Vector2(randf_range(-_shakeStrength, _shakeStrength), randf_range(-_shakeStrength, _shakeStrength))
	else:
		camera.offset = Vector2.ZERO

	match state:
		BattleState.IDLE:
			var remaining := maxf(Rules.TURN_READY_DELAY - (Conductor.getSongTime() - turnReadyStartedAt), 0.0)
			_updateCountdown(remaining)
			if remaining <= 0.0: _startRecording()
		BattleState.RECORDING:
			if Conductor.getSongTime() - recordStartedAt >= Rules.RECORD_DURATION or sequence.size() >= Rules.MAX_SEQUENCE_INPUTS:
				_startDefending()
		BattleState.DEFENDING:
			if _defenseRemainingTime() <= 0.0 and pendingMisses <= 0:
				_finishTurn()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var keyEvent := event as InputEventKey
		if state == BattleState.GAME_OVER and keyEvent.keycode == KEY_ENTER:
			_restartMatch()
			return

		if not PLAYER_INPUT_KEYS.has(keyEvent.keycode): return

		var inputOwner := int(INPUT_OWNERS[keyEvent.keycode])
		if inputOwner != _expectedInputPlayer():
			feedbackLabel.text = "P%d input ignored" % (inputOwner + 1)
			return

		var key := String(PLAYER_INPUT_KEYS[keyEvent.keycode])
		if state == BattleState.RECORDING: _recordInput(key)
		elif state == BattleState.DEFENDING: _defendInput(key)

func _beginTurnReadyDelay() -> void:
	state = BattleState.IDLE
	sequence.clear()
	timeline.clearNotes()
	turnReadyStartedAt = Conductor.getSongTime()
	feedbackLabel.text = ""
	Conductor.playSfx("turn_start")
	_highlightActive()
	_updateCharacterStates()

func _startRecording() -> void:
	state = BattleState.RECORDING
	recordStartedAt = Conductor.getSongTime()
	countdownLabel.visible = false
	_updateCharacterStates()

func _startDefending() -> void:
	state = BattleState.DEFENDING
	defendStartedAt = Conductor.getSongTime()
	pendingMisses = sequence.size()
	timeline.setDisplayPlayer(defenderPlayer)
	timeline.loadSequence(sequence, defendStartedAt)
	_updateCharacterStates()
	if sequence.is_empty(): _finishTurn()

func _finishTurn() -> void:
	if state == BattleState.GAME_OVER: return
	state = BattleState.RESOLVING
	activePlayer = 1 - activePlayer
	defenderPlayer = 1 - activePlayer
	_beginTurnReadyDelay()

func _recordInput(key: String) -> void:
	if sequence.size() >= Rules.MAX_SEQUENCE_INPUTS: return
	sequence.append({"timestamp": Conductor.getSongTime() - recordStartedAt, "key": key})
	feedbackLabel.text = "Recorded %s (%d/%d)" % [key.to_upper(), sequence.size(), Rules.MAX_SEQUENCE_INPUTS]
	Conductor.playNoteSfx(activePlayer, key)
	_playTemporaryAnimation(activePlayer, "record", 0.28)

func _defendInput(key: String) -> void:
	var note: Dictionary = timeline.getPendingNoteForKey(key)
	if note.is_empty():
		Conductor.playSfx("wrong")
		_applyDamage(defenderPlayer, Rules.DAMAGE_ON_MISS, "WRONG")
		return

	var delta := Conductor.getSongTime() - float(note["timestamp"])
	var result: String = Rules.judge(delta)
	timeline.markResolved(int(note["index"]), result)
	pendingMisses -= 1

	if result == "MISS":
		Conductor.playSfx("miss")
		_applyDamage(defenderPlayer, Rules.DAMAGE_ON_MISS, "MISS")
	else:
		Conductor.playNoteSfx(defenderPlayer, key)
		_playTemporaryAnimation(defenderPlayer, "record", 0.2)
		if result != "PERFECT": Conductor.pulseMusicDistortion()
		_showFeedback(result, Rules.RESULT_COLORS[result])

func _onNoteMissed(note: Dictionary) -> void:
	if state != BattleState.DEFENDING: return
	timeline.markResolved(int(note["index"]), "OMISSION")
	pendingMisses -= 1
	Conductor.playSfx("omission")
	_applyDamage(defenderPlayer, Rules.DAMAGE_ON_MISS, "OMISSION")

func _applyDamage(playerIndex: int, amount: int, reason: String) -> void:
	health[playerIndex] = maxi(health[playerIndex] - amount, 0)
	_updateHealthUi()
	Conductor.pulseMusicDistortion()
	_showFeedback("%s - P%d takes %d" % [reason, playerIndex + 1, amount], Rules.RESULT_COLORS[reason])
	Conductor.playSfx("damage")
	_playTemporaryAnimation(playerIndex, "hit", 0.35)
	_shake(5.0, 0.12)
	if health[playerIndex] <= 0: _gameOver(1 - playerIndex)

func _gameOver(winner: int) -> void:
	state = BattleState.GAME_OVER
	timeline.clearNotes()
	feedbackLabel.text = "P%d wins! Enter to restart" % (winner + 1)
	Conductor.playSfx("game_over")
	_setPlayerAnimation(winner, "idle")
	_setPlayerAnimation(1 - winner, "death")

func _restartMatch() -> void:
	health = [Rules.STARTING_HEALTH, Rules.STARTING_HEALTH]
	activePlayer = 0
	defenderPlayer = 1
	_updateHealthUi()
	_beginTurnReadyDelay()

func _expectedInputPlayer() -> int:
	return activePlayer if state == BattleState.RECORDING else defenderPlayer if state == BattleState.DEFENDING else -1

func _defenseRemainingTime() -> float:
	if sequence.is_empty(): return 0.0
	var lastT := 0.0
	for n in sequence: lastT = maxf(lastT, float(n["timestamp"]))
	return Rules.DEFENSE_PHRASE_DELAY + timeline.travelTime + lastT + Rules.MISS_WINDOW - (Conductor.getSongTime() - defendStartedAt)

func _updateHealthUi() -> void:
	p1Health.value = health[0]
	p2Health.value = health[1]

func _updateCountdown(remaining: float) -> void:
	var count := clampi(int(ceil(remaining)), 1, int(Rules.TURN_READY_DELAY))
	countdownLabel.text = "PLAYER %d\n%d" % [activePlayer + 1, count]
	countdownLabel.visible = remaining > 0.0

func _updateCharacterStates() -> void:
	for i in 2: _setPlayerAnimation(i, "death" if health[i] <= 0 else "idle")

func _playTemporaryAnimation(playerIndex: int, anim: String, duration: float) -> void:
	if health[playerIndex] <= 0: return
	_animationTokens[playerIndex] += 1
	var token := int(_animationTokens[playerIndex])
	_setPlayerAnimation(playerIndex, anim, true)
	get_tree().create_timer(duration).timeout.connect(func():
		if state != BattleState.GAME_OVER and health[playerIndex] > 0 and _animationTokens[playerIndex] == token:
			_updateCharacterStates()
	)

func _setPlayerAnimation(idx: int, anim: String, restart := false) -> void:
	var sprite := playerSprites[idx]
	if sprite.sprite_frames.has_animation(anim) and (restart or sprite.animation != anim):
		sprite.play(anim)

func _showFeedback(msg: String, color: Color) -> void:
	feedbackLabel.text = msg
	feedbackLabel.add_theme_color_override("font_color", color)
	var tw := create_tween()
	feedbackLabel.modulate = color
	tw.tween_property(feedbackLabel, "modulate", Color.WHITE, 0.12)

func _highlightActive() -> void:
	var active := defenderPlayer if state == BattleState.DEFENDING else activePlayer
	p1Panel.modulate = Color.WHITE if active == 0 else Color(0.6, 0.6, 0.7)
	p2Panel.modulate = Color.WHITE if active == 1 else Color(0.6, 0.6, 0.7)

func _shake(str: float, dur: float) -> void:
	_shakeStrength = str
	_shakeTime = dur
