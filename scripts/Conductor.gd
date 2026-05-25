extends Node

signal song_started
signal song_stopped

var player: AudioStreamPlayer
var _fallback_start_msec := 0
var _running := false


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.name = "MusicPlayer"
	add_child(player)


func start_song(stream: AudioStream = null) -> void:
	if stream != null:
		player.stream = stream

	_fallback_start_msec = Time.get_ticks_msec()
	_running = true

	if player.stream != null:
		player.play()

	song_started.emit()


func stop_song() -> void:
	if player.playing:
		player.stop()

	_running = false
	song_stopped.emit()


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
