#       .:       .::         .::            .:: ::    .::
#      .: ::      .::       .::           .::    .::  .::
#     .:  .::      .::     .::     .::     .::      .:.: .:
#    .::   .::      .::   .::    .::  .::    .::      .::
#   .:::::: .::      .:: .::    .::   .::       .::   .::
#  .::       .::      .::::     .::   .:: .::    .::  .::
# .::         .::      .::        .:: .:::  .:: ::     .::
#
# AVaSt - https://github.com/avast-mod
#
# the Thanks! window, old school keygen style. logo picture on top, credits under it, sine
# scroller and buttons at the bottom. everything moves pixel by pixel, never smooth.
#
# screen darkens, window unfolds from a line, AVaSt letters drop in one by one on the intro sound
# and the picture flashes on the hit. then the music starts and credits roll. game music is paused
# meanwhile.
# the picture sits under water, a wave equation running on the gpu with the frame as walls.
# mouse over it drops drops (lol), click = big one, hold to draw. holding the mouse (or A) on the
# credits makes them roll twice as fast.
#
# credits are in assets/thanks/credits.txt. "# " is a heading, "> " goes to the scroller, and a
# line can start with [italic] [wave] [rainbow] or [big]

extends "res://gdpatch/mods/avast_core/ui/overlay.gd"

const _DIR := "res://gdpatch/mods/avast_core/assets/thanks/"
const _FONT := "res://gdpatch/mods/avast_core/assets/fonts/fs-tahoma-8px-bold.ttf"
const _SIZE := Vector2(364, 384)
const _PICTURE_HEIGHT := 124.0
const _LETTERS := 5
const _LANDS: Array[float] = [0.45, 0.65, 0.85, 1.05, 1.25]
const _HIT := 1.6
const _FALL := 0.3
const _FALL_FROM := -70.0
const _LOGO_SCALE := 2.0
const _CELLS := Vector2i(174, 61)
const _WATER_RATE := 60.0
const _POKES := 8
const _UNFOLD := 0.3
const _LOOP_FROM := 3.84
const _GAME_TRACK_RMS := -11.1
const _MUSIC_RMS := -14.0
const _INTRO_RMS := -17.3
const _LOUDER := 1.267
const _MUSIC_LOUDER := 1.1
const _EFFECTS := ["italic", "wave", "rainbow", "big"]
const _LETTER_SHADER := """
shader_type canvas_item;
uniform float flash = 0.0;
void fragment() {
	vec4 color = texture(TEXTURE, UV);
	color.rgb = mix(color.rgb, vec3(1.0), flash);
	COLOR = color * COLOR;
}
"""
const _WAVE_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D state : filter_nearest, repeat_disable;
uniform vec2 cells = vec2(174.0, 61.0);
uniform vec4 pokes[8];
uniform float damping = 0.988;
float height(vec2 cell) {
	cell = clamp(cell, vec2(0.0), cells - 1.0);
	return texture(state, (cell + 0.5) / cells).r - 0.5;
}
void fragment() {
	vec2 cell = floor(UV * cells);
	vec4 here = texture(state, (cell + 0.5) / cells);
	float before = here.g - 0.5;
	float next = (height(cell + vec2(1.0, 0.0)) + height(cell - vec2(1.0, 0.0))
		+ height(cell + vec2(0.0, 1.0)) + height(cell - vec2(0.0, 1.0))) * 0.5 - before;
	next *= damping;
	for (int i = 0; i < 8; i++) {
		vec4 p = pokes[i];
		if (p.w == 0.0) {
			continue;
		}
		float d = distance(cell, p.xy * cells) / p.z;
		if (d < 1.0) {
			next -= p.w * (0.5 + 0.5 * cos(d * PI));
		}
	}
	COLOR = vec4(clamp(next, -0.49, 0.49) + 0.5, here.r, 0.0, 1.0);
}
"""
const _WATER_SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform sampler2D heights : filter_linear, repeat_disable;
uniform vec2 cells = vec2(174.0, 61.0);
uniform float flash = 0.0;
void fragment() {
	vec2 t = 1.0 / cells;
	float left = texture(heights, UV - vec2(t.x, 0.0)).r;
	float right = texture(heights, UV + vec2(t.x, 0.0)).r;
	float up = texture(heights, UV - vec2(0.0, t.y)).r;
	float down = texture(heights, UV + vec2(0.0, t.y)).r;
	vec2 slope = vec2(right - left, down - up);
	vec4 color = texture(screen, SCREEN_UV + slope * 60.0 * SCREEN_PIXEL_SIZE);
	color.rgb += vec3(1.0, 0.85, 0.85) * max(0.0, -slope.x - slope.y) * 1.6;
	COLOR = vec4(mix(color.rgb, vec3(1.0), flash), 1.0);
}
"""

var _core: Node
var _dim: ColorRect
var _reveal: Control
var _frame: Control
var _picture: _Picture
var _water: ColorRect
var _logo: Control
var _letters: Array[TextureRect] = []
var _landed: Array[bool] = []
var _shadow: TextureRect
var _sparks: _Sparks
var _stage: _Stage
var _intro: AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_button: Button
var _game_music: AudioStreamPlayer
var _game_music_was_paused := false
var _waves: Array[SubViewport] = []
var _wave_step := 0
var _wave_clock := 0.0
var _pokes: Array[Vector4] = []
var _last_poke := 0.0
var _drawing_from := Vector2(-1, -1)
var _time := 0.0
var _hit_done := false
var _rolling_at := -1.0
var _leaving_at := -1.0

func _init(core: Node) -> void:
	super("Thanks!", _SIZE)
	_core = core

func _ready() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	_reveal = Control.new()
	_reveal.clip_contents = true
	_dim.add_child(_reveal)
	_frame = _make_window()
	_reveal.add_child(_frame)

	_pointer_shadow = _make_pointer()
	_pointer_shadow.modulate = Color(0, 0, 0, 0.25)
	_pointer = _make_pointer()
	_push()
	_pause_game_music()
	_intro = _player("intro.ogg", _INTRO_RMS)
	if _intro != null:
		_intro.finished.connect(_start_credits, CONNECT_ONE_SHOT)
		_intro.play()
	else:
		get_tree().create_timer(_HIT + 1.0, true, false, true).timeout.connect(_start_credits)
	_process(0.0)

func _process(delta: float) -> void:
	super._process(delta)
	_time += delta
	var frame_time := _time
	var open := minf(_time / _UNFOLD, 1.0)
	if _leaving_at >= 0.0:
		open = 1.0 - (_time - _leaving_at) / _UNFOLD
		if open <= 0.0:
			_finish()
			return
	open = open * open * (3.0 - 2.0 * open)
	_dim.color.a = 0.8 * open
	_place_window(open)

	var all_burn := 0.0
	if frame_time >= _HIT:
		if not _hit_done:
			_hit_done = true
			_sparks.burst(_logo.size / 2, 40, 90.0)
			_add_drop(Vector2(0.5, 0.5), 0.45, 7.0)
			_picture.show_icons()
		all_burn = maxf(0.0, 1.0 - floorf((frame_time - _HIT) / 0.06) * 0.17)
		_shadow.modulate.a = minf(1.0, floorf((frame_time - _HIT) / 0.08) * 0.25)
		(_water.material as ShaderMaterial).set_shader_parameter("flash", maxf(0.0, 0.8 - floorf((frame_time - _HIT) / 0.05) * 0.2))
	for i in _LETTERS:
		_animate_letter(i, frame_time, all_burn)

	_step_water(delta)

func close() -> void:
	if _leaving_at >= 0.0:
		return
	_leaving_at = _time
	for player in [_intro, _music]:
		if player != null:
			create_tween().tween_property(player, "volume_db", -60.0, _UNFOLD)

func _finish() -> void:
	set_process(false)
	super.close()

func _exit_tree() -> void:
	if is_instance_valid(_game_music):
		_game_music.stream_paused = _game_music_was_paused
	super._exit_tree()

func _place_window(open: float) -> void:
	var screen := _dim.size if _dim.size.x > 0 else get_viewport().get_visible_rect().size
	var height := maxf(2.0, roundf(_SIZE.y * open / 2.0) * 2.0)
	_reveal.position = (Vector2((screen.x - _SIZE.x) / 2, (screen.y - height) / 2)).round()
	_reveal.size = Vector2(_SIZE.x, height)
	_frame.position = Vector2(0, round(-(_SIZE.y - height) / 2))

func _animate_letter(i: int, frame_time: float, all_burn: float) -> void:
	var letter := _letters[i]
	var land: float = _LANDS[i]
	if frame_time < land - _FALL:
		letter.visible = false
		return
	letter.visible = true
	var y := 0.0
	var burn := 0.0
	if frame_time < land:
		var p := (frame_time - land + _FALL) / _FALL
		y = _FALL_FROM * (1.0 - p * p)
	else:
		if not _landed[i]:
			_landed[i] = true
			var used := letter.texture.get_image().get_used_rect()
			_sparks.burst(Vector2(used.get_center().x, used.end.y - 2), 8)
		if frame_time < land + 0.12:
			y = -5.0 * sin(PI * (frame_time - land) / 0.12)
		burn = maxf(0.0, 1.0 - floorf((frame_time - land) / 0.07) * 0.34)
	letter.position.y = round(y)
	(letter.material as ShaderMaterial).set_shader_parameter("flash", maxf(burn, all_burn))

func _start_credits() -> void:
	if _leaving_at >= 0.0:
		return
	_rolling_at = _time
	_stage.roll()
	_start_music()

func _player(file: String, rms: float, extra: float = 1.0) -> AudioStreamPlayer:
	var stream := AudioStreamOggVorbis.load_from_file(_DIR + file)
	if stream == null:
		return null
	var game_music: Node = Game.autoload("MusicPlayer")
	var game_db: float = game_music.get("gameplay_volume_db") if game_music != null and game_music.get("gameplay_volume_db") != null else -10.0
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"music"
	player.volume_db = game_db + linear_to_db(_LOUDER * extra) + _GAME_TRACK_RMS - rms
	add_child(player)
	return player

func _pause_game_music() -> void:
	var game_music: Node = Game.autoload("MusicPlayer")
	if game_music is AudioStreamPlayer:
		_game_music = game_music
		_game_music_was_paused = _game_music.stream_paused
		_game_music.stream_paused = true

func _start_music() -> void:
	_music = _player("keygen.ogg", _MUSIC_RMS, _MUSIC_LOUDER)
	if _music == null:
		_music_button.hide()
		return
	var stream := _music.stream as AudioStreamOggVorbis
	stream.loop = true
	stream.loop_offset = _LOOP_FROM
	_music.play()

func _toggle_music() -> void:
	if _music == null:
		return
	_music.stream_paused = not _music.stream_paused
	_music_button.text = "Music: off" if _music.stream_paused else "Music: on"

func _make_window() -> Control:
	var font := _pixel_font()
	var credits := _read_credits()
	var frame := PanelContainer.new()
	frame.size = _SIZE
	frame.add_theme_stylebox_override("panel", _nine_patch("frame", 8, 7))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	frame.add_child(column)

	var info = _core.library.info("avast_core")
	_picture = _Picture.new(info.icon() if info != null else null)
	_picture.custom_minimum_size.y = _PICTURE_HEIGHT
	_picture.clip_contents = true
	_picture.resized.connect(_center_logo)
	column.add_child(_picture)
	_logo = _make_logo()
	_picture.add_child(_logo)
	_water = _make_water()
	_picture.add_child(_water)

	_stage = _Stage.new(font, credits.lines)
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	column.add_child(_stage)
	var scroller := _Scroller.new(font, credits.scroller)
	scroller.custom_minimum_size.y = 30
	scroller.clip_contents = true
	column.add_child(scroller)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	column.add_child(buttons)
	_music_button = _keygen_button("Music: on", font, _toggle_music)
	buttons.add_child(_music_button)
	buttons.add_child(_keygen_button("Close", font, close))
	return frame

func _make_logo() -> Control:
	var logo := Control.new()
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = _LETTER_SHADER
	_shadow = _logo_part("logo_shadow")
	_shadow.modulate.a = 0.0
	logo.add_child(_shadow)
	logo.size = _shadow.size
	logo.pivot_offset = logo.size / 2
	logo.scale = Vector2.ONE * _LOGO_SCALE
	for i in _LETTERS:
		var letter := _logo_part("logo_%d" % i)
		var material := ShaderMaterial.new()
		material.shader = shader
		letter.material = material
		letter.visible = false
		logo.add_child(letter)
		_letters.append(letter)
		_landed.append(false)
	_sparks = _Sparks.new()
	_sparks.size = logo.size
	_sparks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.add_child(_sparks)
	return logo

func _center_logo() -> void:
	if _logo == null:
		return
	_logo.position = ((_picture.size - _logo.size) / 2).round()

func _logo_part(name: String) -> TextureRect:
	var part := TextureRect.new()
	part.texture = _png(name)
	part.size = part.texture.get_size()
	part.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	part.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return part

func _make_water() -> ColorRect:
	var water := ColorRect.new()
	water.set_anchors_preset(Control.PRESET_FULL_RECT)
	water.offset_left = 1
	water.offset_top = 1
	water.offset_bottom = -1
	water.mouse_filter = Control.MOUSE_FILTER_STOP
	var shader := Shader.new()
	shader.code = _WATER_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("cells", Vector2(_CELLS))
	water.material = material
	water.gui_input.connect(_on_water_input)
	var wave := Shader.new()
	wave.code = _WAVE_SHADER
	for i in 2:
		var grid := SubViewport.new()
		grid.size = _CELLS
		grid.use_hdr_2d = true
		grid.disable_3d = true
		grid.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var cells := ColorRect.new()
		cells.size = Vector2(_CELLS)
		var step := ShaderMaterial.new()
		step.shader = wave
		step.set_shader_parameter("cells", Vector2(_CELLS))
		cells.material = step
		grid.add_child(cells)
		add_child(grid)
		_waves.append(grid)
	return water

func _step_water(delta: float) -> void:
	_wave_clock += delta
	if _wave_clock < 1.0 / _WATER_RATE:
		return
	_wave_clock = fmod(_wave_clock, 1.0 / _WATER_RATE)
	_wave_step += 1
	var now := _waves[_wave_step % 2]
	var before := _waves[(_wave_step + 1) % 2]
	var step := (now.get_child(0) as ColorRect).material as ShaderMaterial
	step.set_shader_parameter("state", before.get_texture())
	var pokes: Array[Vector4] = []
	for i in _POKES:
		pokes.append(_pokes[i] if i < _pokes.size() else Vector4.ZERO)
	_pokes.clear()
	step.set_shader_parameter("pokes", pokes)
	now.render_target_update_mode = SubViewport.UPDATE_ONCE
	(_water.material as ShaderMaterial).set_shader_parameter("heights", now.get_texture())

func _on_water_input(event: InputEvent) -> void:
	if not event is InputEventMouse or not _hit_done:
		return
	var uv: Vector2 = event.position / _water.size
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_add_drop(uv, 0.4, 5.0)
			_sparks.burst((event.position - _logo.position) / _LOGO_SCALE + _logo.size * (1.0 - 1.0 / _LOGO_SCALE) / 2, 10, 50.0)
			_drawing_from = uv
		else:
			_drawing_from = Vector2(-1, -1)
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT and _drawing_from.x >= 0.0:
			var gap := (uv - _drawing_from) * Vector2(_CELLS)
			var dots := clampi(int(gap.length() / 2.0), 1, 6)
			for k in dots:
				_add_drop(_drawing_from.lerp(uv, float(k + 1) / dots), 0.12, 2.0)
			_drawing_from = uv
		elif _time - _last_poke > 0.07 and event.relative.length() > 0.5:
			_last_poke = _time
			_add_drop(uv, 0.08, 2.5)

func _add_drop(uv: Vector2, depth: float, radius: float) -> void:
	if _pokes.size() >= _POKES:
		_pokes.pop_front()
	_pokes.append(Vector4(uv.x, uv.y, radius, depth))

func _read_credits() -> Dictionary:
	var lines: Array = []
	var scroller: Array[String] = []
	var text := FileAccess.get_file_as_string(_DIR + "credits.txt")
	for id in ["avast_core", "avast_api"]:
		var info = _core.library.info(id)
		text = text.replace("{%s}" % id, info.version if info != null else "?")
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("> "):
			scroller.append(line.substr(2))
			continue
		var heading := line.begins_with("# ")
		if heading:
			line = line.substr(2)
		var effects: Array = []
		while line.begins_with("[") and line.substr(1, line.find("]") - 1) in _EFFECTS:
			effects.append(line.substr(1, line.find("]") - 1))
			line = line.substr(line.find("]") + 1)
		lines.append([line.strip_edges(), heading, effects])
	return {"lines": lines, "scroller": "     ".join(scroller)}

func _keygen_button(text: String, font: Font, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 26
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 16)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(key, Color.WHITE)
	b.add_theme_stylebox_override("normal", _nine_patch("button", 4, 6, 2))
	b.add_theme_stylebox_override("hover", _nine_patch("button_hover", 4, 6, 2))
	b.add_theme_stylebox_override("pressed", _nine_patch("button_pressed", 4, 6, 2))
	b.add_theme_stylebox_override("hover_pressed", _nine_patch("button_pressed", 4, 6, 2))
	b.pressed.connect(on_press)
	return b

func _nine_patch(name: String, edge: int, pad_x: int, pad_y: int = -1) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = _png(name)
	box.texture_margin_left = edge
	box.texture_margin_right = edge
	box.texture_margin_top = edge
	box.texture_margin_bottom = edge
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_x if pad_y < 0 else pad_y
	box.content_margin_bottom = pad_x if pad_y < 0 else pad_y
	return box

static func _png(name: String) -> Texture2D:
	var image := Image.new()
	return ImageTexture.create_from_image(image) if image.load_png_from_buffer(FileAccess.get_file_as_bytes(_DIR + name + ".png")) == OK else null

static func _pixel_font() -> Font:
	var font := FontFile.new()
	font.data = FileAccess.get_file_as_bytes(_FONT)
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return font

class _Box extends Control:
	func _inset() -> void:
		draw_rect(Rect2(0, 0, size.x, 1), Color(0.1, 0, 0))
		draw_rect(Rect2(0, 0, 1, size.y), Color(0.1, 0, 0))
		draw_rect(Rect2(0, size.y - 1, size.x, 1), Color(1, 0.35, 0.28))

class _Picture extends _Box:
	const _ENEMIES := [
		"res://scenes/game_object/enemies/basic_enemy/errortrial-export 24.png",
		"res://assets/icons/info24.png",
		"res://scenes/game_object/enemies/wizard_enemy/critical-24.png",
		"res://scenes/game_object/enemies/wizard_enemy/warning trial-export-export.png",
		"res://scenes/game_object/enemies/bat_enemy/questiontrial-export.png",
		"res://scenes/game_object/enemies/burning_disc_enemy/pyrodisc-icon.png",
		"res://scenes/game_object/enemies/click_me_enemy/clickme-32.png",
		"res://scenes/game_object/enemies/dxdiag_enemy/diag32.png",
		"res://scenes/game_object/enemies/memory_leak_enemy/memoryleak-icon.png",
		"res://scenes/game_object/enemies/bouncer_enemy/beachball-icon.png",
		"res://scenes/game_object/enemies/blocker_enemy/blocker-shield24.png",
		"res://scenes/game_object/enemies/mine_enemy/mine-enemy32.png",
		"res://scenes/game_object/enemies/swarm_enemy/xclose-13.png",
	]
	const _COUNT := 30
	const _SHADE := 0.42
	var _stars: Array = []
	var _things: Array = []
	var _time := 0.0
	var _things_at := -1.0
	var _rng := RandomNumberGenerator.new()

	func _init(icon: Texture2D) -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_rng.seed = 2003
		for i in 60:
			var layer := i % 3
			_stars.append({"x": _rng.randf_range(0, 360), "y": _rng.randf_range(0, 130), "speed": [8.0, 18.0, 36.0][layer], "shade": [0.35, 0.6, 1.0][layer]})
		var looks: Array[Texture2D] = []
		if icon != null:
			looks.append(icon)
		for path in _ENEMIES:
			if ResourceLoader.exists(path):
				looks.append(load(path))
		if looks.is_empty():
			return
		for i in _COUNT:
			var look: Texture2D = looks[i % looks.size()]
			_things.append({"look": look, "pos": Vector2(_rng.randf_range(0, 360), _rng.randf_range(0, 124)),
				"heading": _rng.randf_range(0, TAU), "speed": _rng.randf_range(8.0, 26.0),
				"turn": 0.0, "spin": _rng.randf_range(-1.5, 1.5), "angle": _rng.randf_range(0, TAU)})

	func show_icons() -> void:
		_things_at = _time

	func _process(delta: float) -> void:
		_time += delta
		for star in _stars:
			star.x -= star.speed * delta
			if star.x < 0:
				star.x += size.x
		for thing in _things:
			thing.turn = clampf(thing.turn + _rng.randf_range(-3.0, 3.0) * delta, -1.2, 1.2)
			thing.heading += thing.turn * delta
			thing.pos += Vector2.from_angle(thing.heading) * thing.speed * delta
			thing.angle += thing.spin * delta
			thing.pos.x = fposmod(thing.pos.x + 24, size.x + 48) - 24
			thing.pos.y = fposmod(thing.pos.y + 24, size.y + 48) - 24
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0, 0))
		for star in _stars:
			var c: Color = Color(1, 0.75, 0.75) * star.shade
			c.a = 1.0
			draw_rect(Rect2(round(star.x), round(star.y), 2 if star.speed > 30 else 1, 1), c)
		if _things_at >= 0.0:
			var shade := _SHADE * minf((_time - _things_at) / 0.8, 1.0)
			for thing in _things:
				var look: Texture2D = thing.look
				var grow := 2.0 if look.get_size().x <= 16 else 1.0
				draw_set_transform(thing.pos.round(), thing.angle, Vector2.ONE * grow)
				draw_texture(look, -(look.get_size() / 2).round(), Color(shade, shade * 0.85, shade * 0.85, 1.0))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_inset()

class _Sparks extends Control:
	const _COLORS: Array[Color] = [Color.WHITE, Color(1, 0.82, 0.75), Color(1, 0.3, 0.2), Color(1, 0.85, 0.3)]
	var _bits: Array = []
	var _rng := RandomNumberGenerator.new()

	func burst(at: Vector2, count: int, speed: float = 35.0) -> void:
		for i in count:
			var angle := _rng.randf_range(PI * 1.05, PI * 1.95)
			_bits.append({"pos": at, "vel": Vector2(cos(angle), sin(angle)) * _rng.randf_range(0.4, 1.0) * speed,
				"life": _rng.randf_range(0.35, 0.8), "color": _COLORS[_rng.randi() % _COLORS.size()]})

	func _process(delta: float) -> void:
		for i in range(_bits.size() - 1, -1, -1):
			var bit: Dictionary = _bits[i]
			bit.vel.y += 140.0 * delta
			bit.pos += bit.vel * delta
			bit.life -= delta
			if bit.life <= 0.0:
				_bits.remove_at(i)
		queue_redraw()

	func _draw() -> void:
		for bit in _bits:
			draw_rect(Rect2(bit.pos.round(), Vector2.ONE), bit.color)

class _Stage extends _Box:
	const _ROLL_SPEED := 18.0
	const _TEXT := 16
	const _BIG := 24
	const _LINE := 20.0
	const _MARGIN := 8.0
	const _SLANT := 0.25
	var _font: Font
	var _italic: Font
	var _lines: Array
	var _rows: Array = []
	var _since := -1.0
	var _fast := false

	func _init(font: Font, lines: Array) -> void:
		_font = font
		var italic := FontVariation.new()
		italic.base_font = font
		italic.variation_transform = Transform2D(Vector2(1, _SLANT), Vector2(0, 1), Vector2.ZERO)
		_italic = italic
		_lines = lines
		resized.connect(_wrap)

	func _text_size(effects: Array) -> int:
		return _BIG if "big" in effects else _TEXT

	func _wrap() -> void:
		_rows.clear()
		for line in _lines:
			var effects: Array = line[2]
			var row := ""
			for word in String(line[0]).split(" "):
				var longer: String = word if row.is_empty() else row + " " + word
				if not row.is_empty() and _font.get_string_size(longer, HORIZONTAL_ALIGNMENT_LEFT, -1, _text_size(effects)).x > size.x - _MARGIN * 2:
					_rows.append([row, line[1], effects])
					longer = word
				row = longer
			_rows.append([row, line[1], effects])

	func roll() -> void:
		_since = 0.0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_fast = event.pressed

	func _process(delta: float) -> void:
		if _since >= 0.0:
			_since += delta * (2.0 if _fast else 1.0)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0, 0))
		if _since >= 0.0:
			var offset := roundf(fmod(_since * _ROLL_SPEED, _rows.size() * _LINE + size.y))
			for i in _rows.size():
				var baseline := size.y + _LINE - offset + i * _LINE
				if baseline >= 0 and baseline <= size.y + _LINE:
					_draw_text(_rows[i], baseline)
		_inset()

	func _draw_text(row: Array, baseline: float) -> void:
		var text: String = row[0]
		var effects: Array = row[2]
		var text_size := _text_size(effects)
		var font: Font = _italic if "italic" in effects else _font
		var fade := _fade(baseline - _LINE * 0.6 - (text_size - _TEXT), baseline)
		var x := roundf((size.x - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x) / 2)
		for c in text.length():
			draw_char(font, Vector2(x, baseline - 4 + _wave(effects, x)), text[c], text_size, _color(row, x, fade))
			x += font.get_char_size(text.unicode_at(c), text_size).x

	func _fade(ink_top: float, baseline: float) -> float:
		return clampf(floorf(minf(ink_top, size.y - baseline + 4.0) / 6.0) * 0.34, 0.0, 1.0)

	func _wave(effects: Array, x: float) -> float:
		return roundf(sin(_since * 5.0 - x * 0.07) * 2.0) if "wave" in effects else 0.0

	func _color(row: Array, x: float, fade: float) -> Color:
		if "rainbow" in row[2]:
			return Color.from_hsv(floorf(fmod(_since * 0.5 + x * 0.006, 1.0) * 12.0) / 12.0, 0.75, 1.0, fade)
		return Color(1, 0.25, 0.2, fade) if row[1] else Color(1, 0.9, 0.9, fade)

class _Scroller extends _Box:
	const _SPEED := 55.0
	const _SIZE := 16
	const _GAP := 4.0
	const _INK_ABOVE := 2.5
	var _font: Font
	var _text: String
	var _time := 0.0

	func _init(font: Font, text: String) -> void:
		_font = font
		_text = text

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0, 0))
		if not _text.is_empty():
			var width := _font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _SIZE).x
			var start := roundf(size.x - fmod(_time * _SPEED, width + size.x))
			var baseline := roundf((size.y - _GAP) / 2 + _INK_ABOVE)
			var x := 0.0
			for i in _text.length():
				var advance := _font.get_char_size(_text.unicode_at(i), _SIZE).x
				var left := start + x
				if left > -advance and left < size.x:
					var y := roundf(baseline + sin(_time * 3.0 + left * 0.04) * 3.0)
					var color := Color.from_hsv(fmod(_time * 0.1 + i * 0.015, 0.1), 0.8, 1.0)
					draw_char(_font, Vector2(left, y), _text[i], _SIZE, color)
				x += advance
		_inset()
