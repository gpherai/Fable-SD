## Procedural audio: every sound is synthesised at startup (no asset files).
## SFX are short PCM buffers; ambience is a looping tanpura-style drone per biome.
extends Node

const RATE := 22050
var _sfx: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _ambient: AudioStreamPlayer
var _ambient_key: String = ""
var _drones: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 1234
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_ambient = AudioStreamPlayer.new()
	add_child(_ambient)
	_build_sfx()

# ---------- synthesis helpers ----------
func _stream(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s

func _env(t: float, dur: float, attack: float = 0.005, decay_pow: float = 1.0) -> float:
	if t < attack:
		return t / attack
	var r := 1.0 - (t - attack) / maxf(0.001, dur - attack)
	return pow(clampf(r, 0.0, 1.0), decay_pow)

func _tone(dur: float, f0: float, f1: float, kind: String = "sine", vol: float = 0.5, decay_pow: float = 1.0, noise: float = 0.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / dur
		var f := lerpf(f0, f1, k)
		phase += TAU * f / RATE
		var v := 0.0
		match kind:
			"sine":
				v = sin(phase)
			"square":
				v = 1.0 if fmod(phase, TAU) < PI else -1.0
			"saw":
				v = 2.0 * (fmod(phase, TAU) / TAU) - 1.0
			"tri":
				v = 2.0 * absf(2.0 * (fmod(phase, TAU) / TAU) - 1.0) - 1.0
		if noise > 0.0:
			v = lerpf(v, _rng.randf_range(-1.0, 1.0), noise)
		out[i] = v * vol * _env(t, dur, 0.004, decay_pow)
	return out

func _noise(dur: float, vol: float = 0.5, decay_pow: float = 1.5, lowpass: float = 0.3, attack: float = 0.004) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := _rng.randf_range(-1.0, 1.0)
		last = last + (w - last) * lowpass
		out[i] = last * vol * _env(t, dur, attack, decay_pow)
	return out

func _mix(a: PackedFloat32Array, b: PackedFloat32Array, offset: float = 0.0) -> PackedFloat32Array:
	var off := int(offset * RATE)
	var n := maxi(a.size(), b.size() + off)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var v := 0.0
		if i < a.size():
			v += a[i]
		if i - off >= 0 and i - off < b.size():
			v += b[i - off]
		out[i] = v
	return out

func _chord(dur: float, freqs: Array, vol: float = 0.3, decay_pow: float = 1.2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f in freqs:
		var t := _tone(dur, f, f, "sine", vol / freqs.size(), decay_pow)
		out = _mix(out, t) if out.size() > 0 else t
	return out

func _build_sfx() -> void:
	_sfx["swing"] = _stream(_noise(0.16, 0.35, 1.2, 0.12))
	_sfx["swing_heavy"] = _stream(_mix(_noise(0.3, 0.5, 1.2, 0.08), _tone(0.3, 140, 60, "sine", 0.3)))
	_sfx["hit"] = _stream(_mix(_tone(0.14, 160, 50, "sine", 0.6, 1.5), _noise(0.08, 0.5, 2.0, 0.5)))
	_sfx["hit_heavy"] = _stream(_mix(_tone(0.25, 110, 35, "sine", 0.8, 1.5), _noise(0.15, 0.6, 2.0, 0.4)))
	_sfx["block"] = _stream(_mix(_tone(0.12, 900, 850, "square", 0.15, 2.0), _tone(0.2, 1350, 1300, "sine", 0.2, 2.0)))
	_sfx["player_hit"] = _stream(_mix(_tone(0.2, 90, 40, "saw", 0.4, 1.3), _noise(0.12, 0.4, 1.5, 0.3)))
	_sfx["pickup"] = _stream(_mix(_tone(0.08, 880, 880, "sine", 0.3), _tone(0.18, 1320, 1320, "sine", 0.3), 0.07))
	_sfx["gold"] = _stream(_mix(_tone(0.06, 1760, 1760, "tri", 0.25), _tone(0.12, 2200, 2200, "sine", 0.2), 0.05))
	_sfx["tapas"] = _stream(_tone(0.12, 1200, 1800, "sine", 0.18, 1.5))
	_sfx["cast"] = _stream(_mix(_tone(0.3, 300, 900, "sine", 0.35, 1.2), _noise(0.2, 0.2, 1.5, 0.2)))
	_sfx["fire"] = _stream(_noise(0.45, 0.5, 1.4, 0.1, 0.02))
	_sfx["lightning"] = _stream(_mix(_noise(0.25, 0.7, 2.5, 0.9), _tone(0.3, 2000, 200, "square", 0.15, 2.0)))
	_sfx["wind"] = _stream(_noise(0.5, 0.4, 1.0, 0.05, 0.05))
	_sfx["heal"] = _stream(_chord(0.7, [523.25, 659.25, 783.99], 0.45, 1.5))
	_sfx["shield"] = _stream(_chord(0.5, [392.0, 587.33], 0.4, 1.3))
	_sfx["levelup"] = _stream(_mix(_mix(_tone(0.15, 523, 523, "tri", 0.3), _tone(0.15, 659, 659, "tri", 0.3), 0.12), _mix(_tone(0.15, 784, 784, "tri", 0.3), _tone(0.5, 1046, 1046, "tri", 0.35, 1.5), 0.12), 0.24))
	_sfx["quest"] = _stream(_mix(_tone(0.2, 659, 659, "tri", 0.3), _tone(0.5, 988, 988, "tri", 0.3, 1.5), 0.15))
	_sfx["ui"] = _stream(_tone(0.04, 1500, 1200, "sine", 0.2))
	_sfx["ui_open"] = _stream(_mix(_tone(0.06, 700, 900, "sine", 0.2), _tone(0.08, 1100, 1100, "sine", 0.15), 0.05))
	_sfx["die"] = _stream(_mix(_tone(0.9, 110, 30, "saw", 0.5, 1.2), _noise(0.5, 0.4, 1.5, 0.2)))
	_sfx["enemy_die"] = _stream(_mix(_tone(0.35, 200, 60, "saw", 0.35, 1.3), _noise(0.25, 0.4, 1.5, 0.3)))
	_sfx["roll"] = _stream(_noise(0.22, 0.3, 1.2, 0.08))
	_sfx["step"] = _stream(_noise(0.05, 0.15, 2.0, 0.4))
	_sfx["bell"] = _stream(_mix(_tone(1.6, 1200, 1190, "sine", 0.4, 2.5), _tone(1.2, 2400, 2390, "sine", 0.15, 3.0)))
	_sfx["chest"] = _stream(_mix(_tone(0.12, 220, 180, "square", 0.2, 1.5), _tone(0.3, 660, 660, "sine", 0.25, 1.5), 0.1))
	_sfx["bow"] = _stream(_mix(_tone(0.08, 400, 200, "square", 0.2, 2.0), _noise(0.15, 0.3, 1.5, 0.2)))
	_sfx["arrow_hit"] = _stream(_mix(_tone(0.1, 500, 200, "sine", 0.4, 2.0), _noise(0.06, 0.3, 2.0, 0.5)))
	_sfx["eat"] = _stream(_mix(_noise(0.08, 0.3, 2.0, 0.6), _noise(0.08, 0.3, 2.0, 0.6), 0.12))
	_sfx["drink"] = _stream(_mix(_tone(0.1, 300, 500, "sine", 0.25), _tone(0.1, 350, 600, "sine", 0.25), 0.12))
	_sfx["equip"] = _stream(_mix(_noise(0.06, 0.3, 2.0, 0.3), _tone(0.1, 800, 600, "tri", 0.2), 0.03))
	_sfx["mudra"] = _stream(_mix(_tone(0.12, 660, 660, "sine", 0.25), _tone(0.2, 880, 880, "sine", 0.25), 0.1))
	_sfx["teleport"] = _stream(_mix(_tone(0.8, 200, 1600, "sine", 0.35, 1.0), _noise(0.6, 0.25, 1.2, 0.1)))
	_sfx["summon"] = _stream(_mix(_tone(0.6, 150, 450, "tri", 0.35, 1.2), _chord(0.6, [300, 450], 0.3)))
	_sfx["roar"] = _stream(_mix(_tone(0.5, 120, 80, "saw", 0.5, 1.2, 0.3), _noise(0.5, 0.4, 1.2, 0.15)))
	_sfx["splash"] = _stream(_noise(0.3, 0.4, 1.4, 0.2, 0.02))
	_sfx["dig"] = _stream(_mix(_noise(0.15, 0.4, 2.0, 0.3), _noise(0.15, 0.4, 2.0, 0.3), 0.2))
	_sfx["drum"] = _stream(_mix(_tone(0.2, 150, 70, "sine", 0.6, 1.5), _tone(0.2, 150, 70, "sine", 0.6, 1.5), 0.25))
	_sfx["conch"] = _stream(_tone(1.2, 330, 345, "saw", 0.3, 0.8, 0.05))
	_sfx["door"] = _stream(_mix(_tone(0.8, 60, 40, "saw", 0.4, 1.0, 0.2), _noise(0.8, 0.3, 1.0, 0.05)))

func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _sfx.has(name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _sfx[name]
			p.volume_db = volume_db + linear_to_db(clampf(float(Game.settings.get("sfx", 0.8)), 0.0001, 1.0))
			p.pitch_scale = pitch * (1.0 + _rng.randf_range(-0.04, 0.04))
			p.play()
			return

func play_varied(name: String, volume_db: float = 0.0) -> void:
	play(name, volume_db, _rng.randf_range(0.9, 1.1))

# ---------- ambience ----------
## Tanpura-like drone: fundamental + fifth + octave with slow beating. Keyed by mood.
func _drone(mood: String) -> AudioStreamWAV:
	if _drones.has(mood):
		return _drones[mood]
	var base := 110.0
	var minor := false
	var pulse := 0.0
	var bright := 0.4
	match mood:
		"village": base = 130.8
		"akhara": base = 123.5
		"forest": base = 110.0
		"dark": base = 87.3; minor = true; bright = 0.2
		"cave": base = 82.4; minor = true; bright = 0.15
		"witch": base = 103.8; minor = true; bright = 0.35
		"graveyard": base = 92.5; minor = true; bright = 0.2
		"city": base = 146.8; bright = 0.5
		"lake": base = 116.5; bright = 0.45
		"coast": base = 138.6; bright = 0.5
		"snow": base = 98.0; minor = true; bright = 0.3
		"temple": base = 130.8; bright = 0.6
		"camp": base = 110.0; bright = 0.3
		"prison": base = 77.8; minor = true; bright = 0.1
		"arena": base = 123.5; pulse = 2.0; bright = 0.5
		"boss": base = 73.4; minor = true; pulse = 3.0; bright = 0.3
		"overworld": base = 123.5
	var dur := 6.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var third := base * (1.189 if minor else 1.26)
	var freqs := [base, base * 1.5, base * 2.0, third, base * 0.5]
	var vols := [0.22, 0.14, 0.1 * bright, 0.08 * bright, 0.12]
	var phases := [0.0, 0.0, 0.0, 0.0, 0.0]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			var det := 1.0 + 0.0015 * sin(TAU * (0.07 + 0.03 * k) * t)
			phases[k] += TAU * freqs[k] * det / RATE
			var s := sin(phases[k]) + 0.35 * sin(2.0 * phases[k]) + 0.12 * sin(3.0 * phases[k])
			v += s * vols[k]
		# slow swell so the loop point is soft
		var swell := 0.7 + 0.3 * sin(TAU * t / dur)
		if pulse > 0.0:
			swell *= 0.75 + 0.25 * maxf(0.0, sin(TAU * pulse * t))
		out[i] = v * swell * 0.6
	var s := _stream(out, true)
	_drones[mood] = s
	return s

func set_ambient(mood: String) -> void:
	if mood == _ambient_key:
		return
	_ambient_key = mood
	_ambient.stream = _drone(mood)
	_ambient.volume_db = linear_to_db(clampf(float(Game.settings.get("music", 0.5)), 0.0001, 1.0)) - 6.0
	_ambient.play()

func stop_ambient() -> void:
	_ambient.stop()
	_ambient_key = ""

func refresh_volumes() -> void:
	if _ambient.playing:
		_ambient.volume_db = linear_to_db(clampf(float(Game.settings.get("music", 0.5)), 0.0001, 1.0)) - 6.0
