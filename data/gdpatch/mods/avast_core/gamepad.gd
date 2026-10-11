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
# gamepad and steam deck support for avast's own windows. the games buttons get clicked by the
# games cursor (an Area2D thing), but our fields, lists, tabs and the overlay windows are normal
# godot controls that only listen to the mouse, so A does nothing on them by itself.
# so: A over avast ui sends a real left click (skipped when the games cursor is already on one of
# its own buttons, or it would click twice), right stick scrolls, and while an overlay is open
# (game paused, its cursor frozen) the left stick and dpad move the mouse.
# a text field that gets focus from A, or anything on a steam deck, opens steams floating keyboard

extends Node

const Overlay := preload("res://gdpatch/mods/avast_core/ui/overlay.gd")
const DEVICE := 77
const SPEED := 360.0
const DEAD_ZONE := 0.2
const SCROLL_EVERY := 0.06

var _held := false
var _clicked_at := -100000
var _scroll_wait := 0.0
var _deck := OS.get_environment("SteamDeck") == "1"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().gui_focus_changed.connect(_on_focus)

func _input(event: InputEvent) -> void:
	if not event is InputEventJoypadButton or event.button_index != JOY_BUTTON_A:
		return
	if event.pressed and not _held and _active() and not _game_cursor_busy():
		_held = true
		_clicked_at = Time.get_ticks_msec()
		_send(_mouse_button(MOUSE_BUTTON_LEFT, true))
	elif not event.pressed and _held:
		_held = false
		_send(_mouse_button(MOUSE_BUTTON_LEFT, false))

func _process(delta: float) -> void:
	var viewport := get_viewport()
	if not Overlay._stack.is_empty():
		var move := (_stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y) + _dpad()).limit_length(1.0)
		if move != Vector2.ZERO:
			var to := viewport.get_mouse_position() + move * SPEED * delta
			viewport.warp_mouse(to.clamp(Vector2.ZERO, viewport.get_visible_rect().size - Vector2.ONE))
	_scroll_wait -= delta
	var scroll := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y).y
	if scroll != 0.0 and _scroll_wait <= 0.0 and _active():
		_scroll_wait = SCROLL_EVERY
		var wheel := MOUSE_BUTTON_WHEEL_DOWN if scroll > 0.0 else MOUSE_BUTTON_WHEEL_UP
		for down in [true, false]:
			var e := _mouse_button(wheel, down)
			e.factor = absf(scroll) * 2.0
			_send(e)

func _active() -> bool:
	if not Overlay._stack.is_empty():
		return true
	var at := get_viewport().get_mouse_position()
	for node in get_tree().get_nodes_in_group(&"avast_ui"):
		var control := node as Control
		if control != null and control.is_visible_in_tree():
			if (control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)).has_point(at):
				return true
	return false

func _game_cursor_busy() -> bool:
	if not Overlay._stack.is_empty():
		return false
	var events: Node = get_tree().root.get_node_or_null("GameEvents")
	var cursor = events.get("active_cursor") if events != null else null
	return is_instance_valid(cursor) and cursor.get("cursor_hovering") == true

func _ours(node: Node) -> bool:
	while node != null:
		if node.is_in_group(&"avast_ui") or Overlay._stack.has(node):
			return true
		node = node.get_parent()
	return false

func _on_focus(control: Control) -> void:
	if not (control is LineEdit or control is TextEdit) or not _ours(control):
		return
	if not _deck and Time.get_ticks_msec() - _clicked_at > 1000:
		return
	var steam: Object = Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
	if steam == null or not steam.has_method("showFloatingGamepadTextInput"):
		return
	var rect := control.get_viewport().get_screen_transform() * control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
	steam.call("showFloatingGamepadTextInput", 1 if control is TextEdit else 0, int(rect.position.x), int(rect.position.y), int(rect.size.x), int(rect.size.y))

func _stick(x_axis: JoyAxis, y_axis: JoyAxis) -> Vector2:
	var total := Vector2.ZERO
	for device in _devices():
		var value := Vector2(Input.get_joy_axis(device, x_axis), Input.get_joy_axis(device, y_axis))
		if value.length() > DEAD_ZONE:
			total += value * value.length()
	return total

func _dpad() -> Vector2:
	var total := Vector2.ZERO
	for device in _devices():
		total.x += float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT))
		total.y += float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP))
	return total

func _devices() -> Array:
	var devices: Array = Input.get_connected_joypads()
	return devices if not devices.is_empty() else [0]

func _mouse_button(button: MouseButton, down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.device = DEVICE
	e.button_index = button
	e.pressed = down
	if button == MOUSE_BUTTON_LEFT and down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e

func _send(e: InputEventMouseButton) -> void:
	var viewport := get_viewport()
	e.position = viewport.get_screen_transform() * viewport.get_mouse_position()
	e.global_position = e.position
	Input.parse_input_event(e)
