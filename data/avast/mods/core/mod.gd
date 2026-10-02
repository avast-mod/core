extends Node

const MOD_ID := "core"
const ICON_SCENE: PackedScene = preload("res://scenes/game_object/folder/folder_menu.tscn")
const ICON_SCRIPT_PATH := "res://avast/mods/core/desktop_icon.gd"
const ICON_TEXTURE_PATH := "res://avast/mods/core/icon.png"
const WINDOW_SCENE: PackedScene = preload("res://scenes/ui/Window/basic_window.tscn")
const STD_BUTTON_SCENE: PackedScene = preload("res://scenes/ui/standard_button/standard_button.tscn")
const DESKTOP_PATH := "DesktopCanvas/Desktop"
const ICON_POS := Vector2(185, 280)

var _injected := false
var _icon: Node2D = null
var _menu: Node = null
var _center: Control = null
var _popup: Control = null

func _ready() -> void:
	var scene := get_tree().current_scene
	if _is_menu(scene):
		_inject(scene)
		return
	get_tree().root.child_entered_tree.connect(_on_root_child)

func _on_root_child(node: Node) -> void:
	if _injected:
		return
	if _is_menu(node):
		_inject(node)

func _is_menu(node: Node) -> bool:
	if node == null or node.name != "MainMenu":
		return false
	return node.get_node_or_null(DESKTOP_PATH) != null

func _inject(menu: Node) -> void:
	_injected = true
	if get_tree().root.child_entered_tree.is_connected(_on_root_child):
		get_tree().root.child_entered_tree.disconnect(_on_root_child)
	var desktop := menu.get_node(DESKTOP_PATH) as Node
	var holder := Node2D.new()
	holder.position = ICON_POS
	desktop.add_child(holder)
	var icon := ICON_SCENE.instantiate() as Node2D
	var icon_script := load(ICON_SCRIPT_PATH) as Script
	if icon_script != null:
		icon.set_script(icon_script)
	icon.name = "AVaSt"
	icon.set("_folder_name", "AVaSt")
	icon.set("_tooltip_key", "CLICKABLE.double_click_open")
	var sprite := icon.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		var tex := _load_texture(ICON_TEXTURE_PATH)
		if tex != null:
			sprite.texture = tex
			var s := 32.0 / maxf(tex.get_width(), tex.get_height())
			sprite.scale = Vector2(s, s)
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.add_child(icon)
	icon.connect("open_requested", _on_icon)
	_icon = icon
	_menu = menu
	_center = menu.get_node_or_null("DesktopCanvas/DesktopCenter") as Control
	print("[AVaSt:%s] desktop icon injected" % MOD_ID)

func _on_icon() -> void:
	if is_instance_valid(_popup):
		return
	_popup = _make_popup()
	if _menu != null and _menu.has_method("goto_centre"):
		_menu.goto_centre()
	if _center != null:
		_center.add_child(_popup)
	else:
		get_tree().current_scene.add_child(_popup)
	print("[AVaSt:%s] popup opened" % MOD_ID)

static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			return ImageTexture.create_from_image(img)
	return null

func _make_popup() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var win := WINDOW_SCENE.instantiate() as PanelContainer
	win.custom_minimum_size = Vector2(360, 330)
	win.set_anchors_preset(Control.PRESET_CENTER)
	win.offset_left = -180.0
	win.offset_top = -154.0
	win.offset_right = 180.0
	win.offset_bottom = 154.0
	root.add_child(win)
	var title := win.get_node_or_null("MarginContainer2/Label") as Label
	if title != null:
		title.text = "AVaSt"
	var footer := win.get_node_or_null("VBoxContainer/Activ-bgDith")
	if footer != null:
		footer.visible = false
	for holder_name in ["MarginContainer/HBoxContainer/Min", "MarginContainer/HBoxContainer/Close"]:
		var holder := win.get_node_or_null(holder_name)
		if holder == null:
			continue
		var btn := STD_BUTTON_SCENE.instantiate() as Button
		btn.set_anchors_preset(Control.PRESET_CENTER)
		btn.offset_left = -9.0
		btn.offset_top = -12.0
		btn.offset_right = 9.0
		btn.offset_bottom = 12.0
		for state in ["normal", "pressed", "hover", "hover_pressed", "disabled", "focus"]:
			btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		btn.text = ""
		btn.set("custom_theme", true)
		btn.clicked.connect(_on_window_close)
		holder.add_child(btn)
	return root

func _on_window_close() -> void:
	if _menu != null and is_instance_valid(_menu) and _menu.has_method("go_back"):
		_menu.go_back()
	if is_instance_valid(_popup):
		var pop := _popup
		_popup = null
		pop.queue_free()
