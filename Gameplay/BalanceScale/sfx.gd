class_name Sfx
extends Node
## Tiny synthesised sound effects, so the level has audio feedback without any audio files.
## Replace with real samples later by changing _stream().

const RATE := 22050
const POOL := 6

var _players: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var volume_db := -8.0


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.volume_db = volume_db
		add_child(p)
		_players.append(p)


func play(effect: String) -> void:
	var stream := _stream(effect)
	if stream == null or _players.is_empty():
		return
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.play()
			return
	_players[0].stream = stream
	_players[0].play()


func _stream(effect: String) -> AudioStreamWAV:
	if _cache.has(effect):
		return _cache[effect]
	var notes: Array = []
	match effect:
		"lock":     notes = [[880.0, 0.06, 0.5, "sine", 1.0], [1320.0, 0.10, 0.5, "sine", 1.0]]
		"tick":     notes = [[1100.0, 0.04, 0.4, "square", 1.0]]
		"round":    notes = [[440.0, 0.12, 0.5, "sine", 1.0], [660.0, 0.18, 0.5, "sine", 1.0]]
		"penalty":  notes = [[330.0, 0.15, 0.5, "square", 0.9], [247.0, 0.25, 0.5, "square", 0.9]]
		"reveal":   notes = [[196.0, 0.45, 0.6, "sine", 1.0], [294.0, 0.45, 0.4, "sine", 1.0]]
		"win":      notes = [[523.0, 0.10, 0.5, "sine", 1.0], [659.0, 0.10, 0.5, "sine", 1.0], [784.0, 0.10, 0.5, "sine", 1.0], [1046.0, 0.30, 0.5, "sine", 1.0]]
		"standoff": notes = [[300.0, 0.18, 0.5, "square", 1.0], [300.0, 0.18, 0.5, "square", 1.0]]
		"acid":     notes = [[160.0, 0.7, 0.5, "noise", 0.6]]
		"alarm":    notes = [[760.0, 0.18, 0.5, "square", 1.0], [520.0, 0.18, 0.5, "square", 1.0]]
		"eliminate": notes = [[440.0, 0.7, 0.6, "saw", 0.25]]
		"gameover": notes = [[392.0, 0.2, 0.5, "sine", 1.0], [330.0, 0.2, 0.5, "sine", 1.0], [262.0, 0.5, 0.5, "sine", 1.0]]
		_: return null
	var wav := _synth(notes)
	_cache[effect] = wav
	return wav


## notes: [[frequency, seconds, volume, wave, end_frequency_factor]]
func _synth(notes: Array) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for note in notes:
		var freq: float = note[0]
		var length := int(float(note[1]) * RATE)
		var vol: float = note[2]
		var wave: String = note[3]
		var end_factor: float = note[4]
		var phase := 0.0
		for i in length:
			var t := float(i) / float(length)
			var f := freq * lerpf(1.0, end_factor, t)
			phase = fmod(phase + f / RATE, 1.0)
			var v := 0.0
			match wave:
				"square": v = 1.0 if phase < 0.5 else -1.0
				"saw": v = 2.0 * phase - 1.0
				"noise": v = rng.randf_range(-1.0, 1.0) * 0.8 + sin(phase * TAU) * 0.2
				_: v = sin(phase * TAU)
			var env := minf(1.0, float(i) / 120.0) * pow(1.0 - t, 0.8)
			samples.append(v * vol * env * 0.6)
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav
