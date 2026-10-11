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
# base for the windows drawn above the game in the games own window style.
#
# while one is open the game is paused, the games click actions get switched off so nothing behind
# the window reacts, and a copy of the games cursor follows the mouse. that way normal godot
# controls (scroll areas, text selection...) work, during runs too.
# subclasses fill `body` in _build()

extends CanvasLayer

signal closed

const Game := preload("res://avast/api/lib/game.gd")
const Windows := preload("res://avast/api/windows.gd")
const _WINDOW := "res://scenes/ui/Window/basic_window.tscn"
const _CURSOR := "uid://qtcyq70j3mqq"
const _HAND := "res://scenes/game_object/player/cursrorhand.png"
const _CURSOR_OFFSET := Vector2(6, 10)
const _CLICK_ACTIONS: Array[StringName] = [&"left_click", &"left_click_secondary"]
const _BODY_COLOR := Color(0.9490196, 0.9411765, 0.8509804)

static var _stack: Array[CanvasLayer] = []
static var _saved := {}

var body: VBoxContainer
var window: PanelContainer
var _title := ""
var _size := Vector2.ZERO
var _closing := false
var _pointer: TextureRect
var _pointer_shadow: TextureRect
var _links_hovered := 0

func _init(title: String, size: Vector2) -> void:
	_title = title
	_size = size
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	window = load(_WINDOW).instantiate()
	window.custom_minimum_size = _size
	window.set_anchors_preset(Control.PRESET_CENTER)
	window.offset_left = -_size.x / 2
	window.offset_top = -_size.y / 2
	window.offset_right = _size.x / 2
	window.offset_bottom = _size.y / 2
	dim.add_child(window)
	for path in ["PanelContainer", "VBoxContainer", "MarginContainer/HBoxContainer/Min", "MarginContainer/HBoxContainer/Max"]:
		window.get_node(path).visible = false
	window.get_node("MarginContainer2/Label").text = _title
	var background := ColorRect.new()
	background.color = _BODY_COLOR
	background.add_to_group(&"theme_window_body")
	window.add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	window.add_child(margin)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	margin.add_child(body)
	var close_button := Button.new()
	close_button.flat = true
	close_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	window.get_node("MarginContainer/HBoxContainer/Close").add_child(close_button)
	_pointer_shadow = _make_pointer()
	_pointer_shadow.modulate = Color(0, 0, 0, 0.25)
	_pointer = _make_pointer()
	_push()
	_build()

func _build() -> void:
	pass

func close() -> void:
	if _closing:
		return
	_closing = true
	_pop()
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("close") and not _stack.is_empty() and _stack.back() == self:
		get_viewport().set_input_as_handled()
		close()

func _process(_delta: float) -> void:
	if window != null:
		window.pivot_offset = window.size / 2
		window.scale = Vector2.ONE * screen_fit(window.size)
	var top: bool = not _stack.is_empty() and _stack.back() == self
	_pointer.visible = top and not _headless()
	_pointer_shadow.visible = _pointer.visible
	if not _pointer.visible:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var hovered := get_viewport().gui_get_hovered_control()
	var on_link := _links_hovered > 0 and hovered is RichTextLabel
	var texture: Texture2D = load(_HAND) if on_link or (hovered is BaseButton and not hovered.disabled) else _cursor_texture()
	_pointer.texture = texture
	_pointer_shadow.texture = texture
	var at := get_viewport().get_mouse_position() + _CURSOR_OFFSET - texture.get_size() / 2
	_pointer.position = at.round()
	_pointer_shadow.position = (at + Vector2(0, 1)).round()

func _exit_tree() -> void:
	_pop()

func label(text: String, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"ThemeLabel"
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 20
	b.pressed.connect(on_press)
	return b

func row(children: Array) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 4)
	for child in children:
		r.add_child(child)
	return r

func spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

func text_box(min_height: float = 80.0) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.selection_enabled = true
	t.context_menu_enabled = false
	t.scroll_following = false
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.custom_minimum_size.y = min_height
	t.add_theme_color_override("default_color", Color(0.05, 0, 0.1, 0.85))
	t.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
	t.meta_hover_started.connect(func(_meta: Variant) -> void: _links_hovered += 1)
	t.meta_hover_ended.connect(func(_meta: Variant) -> void: _links_hovered = maxi(_links_hovered - 1, 0))
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(1, 1, 1, 0.55)
	frame.border_color = Color(0.67, 0.67, 0.52)
	frame.set_border_width_all(1)
	frame.set_content_margin_all(4)
	t.add_theme_stylebox_override("normal", frame)
	return t

func _push() -> void:
	if _stack.has(self):
		return
	if _stack.is_empty():
		var tree := get_tree()
		_saved = {"paused": tree.paused, "mouse": Input.mouse_mode, "clicks": {}}
		_saved.centred = _centre_desktop() if layer < 128 else false
		tree.paused = true
		for action in _CLICK_ACTIONS:
			if InputMap.has_action(action):
				_saved.clicks[action] = InputMap.action_get_events(action)
				InputMap.action_erase_events(action)
		var cursor: Node = Game.autoload("GameEvents").active_cursor
		if is_instance_valid(cursor) and Game.main_menu() != null:
			_saved.cursor = cursor
			_saved.cursor_visible = cursor.visible
			cursor.visible = false
		if not _headless():
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_stack.append(self)

func _pop() -> void:
	if not _stack.has(self):
		return
	_stack.erase(self)
	if _stack.is_empty() and is_inside_tree():
		get_tree().paused = _saved.get("paused", false)
		for action in _saved.get("clicks", {}):
			for event in _saved.clicks[action]:
				InputMap.action_add_event(action, event)
		if is_instance_valid(_saved.get("cursor")):
			_saved.cursor.visible = _saved.cursor_visible
		if not _headless():
			Input.mouse_mode = _saved.get("mouse", Input.MOUSE_MODE_VISIBLE)
		var menu := Game.main_menu()
		if _saved.get("centred") and menu != null:
			menu.camera_2d.process_mode = _saved.camera_mode
			Windows._prune()
			if Windows._open.is_empty() and not Windows._MENU_FLAGS.any(func(flag: String) -> bool: return menu.get(flag)):
				menu.go_back()

static func _centre_desktop() -> bool:
	var menu := Game.main_menu()
	if menu == null or menu.camera_2d.offset.is_zero_approx():
		return false
	menu.goto_centre()
	menu.tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_saved.camera_mode = menu.camera_2d.process_mode
	menu.camera_2d.process_mode = Node.PROCESS_MODE_ALWAYS
	return true

static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"

static func screen_fit(size: Vector2, reserve := Vector2(16, 16)) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	var room: Vector2 = tree.root.get_visible_rect().size - reserve
	var scaler: Node = Game.autoload("ExpandIntScaler")
	var screen: int = maxi(1, int(scaler.get("chosen_scale"))) if scaler != null and scaler.get("chosen_scale") != null else 1
	var steps := screen
	while steps > 1 and (size.x * steps / screen > room.x or size.y * steps / screen > room.y):
		steps -= 1
	return float(steps) / screen

func _make_pointer() -> TextureRect:
	var pointer := TextureRect.new()
	pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pointer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pointer.z_index = 100
	pointer.visible = false
	add_child(pointer)
	return pointer

func _cursor_texture() -> Texture2D:
	var cursor: Node = Game.autoload("GameEvents").active_cursor
	if is_instance_valid(cursor) and cursor.get("cursor_texture") is Texture2D:
		return cursor.cursor_texture
	return load(_CURSOR)
