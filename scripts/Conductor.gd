extends Node

signal song_started
signal song_stopped

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
var distortion_pitch_scale := 0.965
var distortion_volume_drop_db := 3.0
var distortion_duration := 0.16
var _fallback_start_msec := 0
var _running := false
var _sfx_players := {}
var _music_base_volume_db := 0.0
var _music_base_pitch_scale := 1.0
var _distortion_tween: Tween


func _ready() -> void:
	_music_base_volume_db = player.volume_db
	_music_base_pitch_scale = player.pitch_scale
	_load_sfx_players()


func _exit_tree() -> void:
	if _distortion_tween != null:
		_distortion_tween.kill()

	if player != null:
		if player.playing:
			player.stop()
		player.stream = null

	for sfx_player in _sfx_players.values():
		if sfx_player is AudioStreamPlayer:
			if sfx_player.playing:
				sfx_player.stop()
			sfx_player.stream = null


func start_song(stream: AudioStream = null) -> void:
	if stream != null:
		player.stream = stream

	if player.playing:
		player.stop()

	_fallback_start_msec = Time.get_ticks_msec()
	_running = true

	if player.stream != null:
		player.play(0.0)

	song_started.emit()


func stop_song() -> void:
	if player.playing:
		player.stop()

	_running = false
	song_stopped.emit()


func play_sfx(sfx_name: String) -> void:
	if not _sfx_players.has(sfx_name):
		return

	var sfx_player := _sfx_players[sfx_name] as AudioStreamPlayer
	if sfx_player.playing:
		sfx_player.stop()
	sfx_player.play(0.0)


func play_note_sfx(player_index: int, key: String) -> void:
	if player_index < 0 or player_index >= PLAYER_NOTE_SFX_NAMES.size():
		return

	var note_sfx_names: Dictionary = PLAYER_NOTE_SFX_NAMES[player_index]
	if not note_sfx_names.has(key):
		return

	play_sfx(String(note_sfx_names[key]))


func pulse_music_distortion() -> void:
	if player == null:
		return

	if _distortion_tween != null:
		_distortion_tween.kill()

	player.pitch_scale = _music_base_pitch_scale * distortion_pitch_scale
	player.volume_db = _music_base_volume_db - distortion_volume_drop_db

	_distortion_tween = create_tween()
	_distortion_tween.set_parallel(true)
	_distortion_tween.tween_property(player, "pitch_scale", _music_base_pitch_scale, distortion_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_distortion_tween.tween_property(player, "volume_db", _music_base_volume_db, distortion_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func is_running() -> bool:
	return _running


func get_song_time() -> float:
	if not _running:
		return 0.0

	if player.stream != null and player.playing:
		var time := player.get_playback_position()
		time += AudioServer.get_time_since_last_mix()
		time -= AudioServer.get_output_latency()
		return maxf(time, 0.0)

	return float(Time.get_ticks_msec() - _fallback_start_msec) / 1000.0


func get_beat_duration() -> float:
	return 60.0 / bpm


func get_current_beat() -> int:
	return int(floor(get_song_time() / get_beat_duration()))


func _load_sfx_players() -> void:
	for sfx_name in SFX_NODE_NAMES:
		var node := get_node_or_null(String(SFX_NODE_NAMES[sfx_name]))
		if not node is AudioStreamPlayer:
			continue
		if node.stream == null:
			continue

		_sfx_players[sfx_name] = node
