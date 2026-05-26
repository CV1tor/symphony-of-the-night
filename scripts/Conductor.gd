extends Node

signal song_started
signal song_stopped

const DEFAULT_SONG_PATH := "res://assets/audio/battle_theme.ogg"
const DEFAULT_BPM := 120.0
const SFX_PATHS := {
	"record_note": "res://assets/audio/sfx/record_note.ogg",
	"perfect": "res://assets/audio/sfx/perfect.ogg",
	"good": "res://assets/audio/sfx/good.ogg",
	"miss": "res://assets/audio/sfx/miss.ogg",
	"wrong": "res://assets/audio/sfx/wrong.ogg",
	"omission": "res://assets/audio/sfx/omission.ogg",
	"damage": "res://assets/audio/sfx/damage.ogg",
	"turn_start": "res://assets/audio/sfx/turn_start.ogg",
	"game_over": "res://assets/audio/sfx/game_over.ogg",
}

var player: AudioStreamPlayer
var bpm := DEFAULT_BPM
var _fallback_start_msec := 0
var _running := false
var _sfx_players := {}


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.name = "MusicPlayer"
	add_child(player)
	_load_default_song()
	_load_sfx_players()


func _exit_tree() -> void:
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
	elif player.stream == null:
		_load_default_song()

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


func _load_default_song() -> void:
	var stream := _load_optional_audio_stream(DEFAULT_SONG_PATH)
	if stream is AudioStream:
		player.stream = stream


func _load_sfx_players() -> void:
	for sfx_name in SFX_PATHS:
		var path := String(SFX_PATHS[sfx_name])
		var stream := _load_optional_audio_stream(path)
		if not stream is AudioStream:
			continue

		var sfx_player := AudioStreamPlayer.new()
		sfx_player.name = "Sfx_%s" % String(sfx_name).capitalize()
		sfx_player.stream = stream
		add_child(sfx_player)
		_sfx_players[sfx_name] = sfx_player


func _load_optional_audio_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path) or _has_invalid_import(path):
		return null

	var stream := ResourceLoader.load(path)
	if stream is AudioStream:
		return stream

	return null


func _has_invalid_import(path: String) -> bool:
	var import_path := "%s.import" % path
	if not FileAccess.file_exists(import_path):
		return false

	var import_file := FileAccess.open(import_path, FileAccess.READ)
	if import_file == null:
		return false

	var import_text := import_file.get_as_text()
	return import_text.contains("valid=false")
