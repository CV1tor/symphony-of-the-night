extends Node

signal songStarted
signal songStopped

const DEFAULT_BPM := 120.0
const SFX_NODE_NAMES := {
	"record_note": "SfxRecordNote",
	"p1_note_up": "SfxP1NoteUp",
	"p1_note_right": "SfxP1NoteRight",
	"p1_note_down": "SfxP1NoteDown",
	"p1_note_left": "SfxP1NoteLeft",
	"p2_note_up": "SfxP2NoteUp",
	"p2_note_right": "SfxP2NoteRight",
	"p2_note_down": "SfxP2NoteDown",
	"p2_note_left": "SfxP2NoteLeft",
	"perfect": "SfxPerfect",
	"good": "SfxGood",
	"miss": "SfxMiss",
	"wrong": "SfxWrong",
	"omission": "SfxOmission",
	"damage": "SfxDamage",
	"turn_start": "SfxTurnStart",
	"game_over": "SfxGameOver",
}
const PLAYER_NOTE_SFX_NAMES := [
	{
		"up": "p1_note_up",
		"right": "p1_note_right",
		"down": "p1_note_down",
		"left": "p1_note_left",
	},
	{
		"up": "p2_note_up",
		"right": "p2_note_right",
		"down": "p2_note_down",
		"left": "p2_note_left",
	},
]

@onready var player: AudioStreamPlayer = $MusicPlayer

var bpm := DEFAULT_BPM
var distortionPitchScale := 0.965
var distortionVolumeDropDb := 3.0
var distortionDuration := 0.16

var _fallbackStartMsec := 0
var _running := false
var _sfxPlayers := {}
var _musicBaseVolumeDb := 0.0
var _musicBasePitchScale := 1.0
var _distortionTween: Tween

func _ready() -> void:
	_musicBaseVolumeDb = player.volume_db
	_musicBasePitchScale = player.pitch_scale
	_loadSfxPlayers()

func _exit_tree() -> void:
	if _distortionTween != null:
		_distortionTween.kill()

func startSong(stream: AudioStream = null) -> void:
	if stream != null:
		player.stream = stream

	if player.playing:
		player.stop()

	_fallbackStartMsec = Time.get_ticks_msec()
	_running = true

	if player.stream != null:
		player.play(0.0)

	songStarted.emit()

func stopSong() -> void:
	if player.playing:
		player.stop()

	_running = false
	songStopped.emit()

func playSfx(sfxName: String) -> void:
	if not _sfxPlayers.has(sfxName):
		return

	var sfxPlayer := _sfxPlayers[sfxName] as AudioStreamPlayer
	if sfxPlayer.playing:
		sfxPlayer.stop()
	sfxPlayer.play(0.0)

func playNoteSfx(playerIndex: int, key: String) -> void:
	if playerIndex < 0 or playerIndex >= PLAYER_NOTE_SFX_NAMES.size():
		return

	var noteSfxNames: Dictionary = PLAYER_NOTE_SFX_NAMES[playerIndex]
	if not noteSfxNames.has(key):
		return

	playSfx(String(noteSfxNames[key]))

func pulseMusicDistortion() -> void:
	if player == null:
		return

	if _distortionTween != null:
		_distortionTween.kill()

	player.pitch_scale = _musicBasePitchScale * distortionPitchScale
	player.volume_db = _musicBaseVolumeDb - distortionVolumeDropDb

	_distortionTween = create_tween()
	_distortionTween.set_parallel(true)
	_distortionTween.tween_property(player, "pitch_scale", _musicBasePitchScale, distortionDuration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_distortionTween.tween_property(player, "volume_db", _musicBaseVolumeDb, distortionDuration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func isRunning() -> bool:
	return _running

func getSongTime() -> float:
	if not _running:
		return 0.0

	if player.stream != null and player.playing:
		var time := player.get_playback_position()
		time += AudioServer.get_time_since_last_mix()
		time -= AudioServer.get_output_latency()
		return maxf(time, 0.0)

	return float(Time.get_ticks_msec() - _fallbackStartMsec) / 1000.0

func getBeatDuration() -> float:
	return 60.0 / bpm

func getCurrentBeat() -> int:
	return int(floor(getSongTime() / getBeatDuration()))

func _loadSfxPlayers() -> void:
	for sfxName in SFX_NODE_NAMES:
		var node := get_node_or_null(String(SFX_NODE_NAMES[sfxName]))
		if not node is AudioStreamPlayer:
			continue
		if node.stream == null:
			continue

		_sfxPlayers[sfxName] = node
