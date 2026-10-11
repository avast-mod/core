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
# checks if this is the steam demo (app 4320630) and if so shows a notice right at the start,
# avast wasnt made for the demo. game logo on top, a yellow "Notice from AVaSt" under it in the
# bold tahoma pixel font (api and core both ship it, whichever is there gets used), then the
# text centered, store button and OK.
# the game has no mouse of its own while it boots, so the notice draws the games cursor itself
# (the arrow, the hand over buttons) like core's windows do, untill you close it.
# this exact file is in both the api and core on purpose, just in case. the api calls check()
# from its mod.gd, core runs it as the AVaStDemo autoload from patcher.lua, because cores mod.gd
# doesnt even compile in the demo (no StatTracker, SaveManager...). whichever goes first shows
# the notice, the other one sees the Engine meta and stays quiet

extends Node

const DEMO_APP_ID := "4320630"
const STORE_PAGE := "https://store.steampowered.com/app/3832490"
const LOGOS := ["res://assets/ui/avs03pro logo white dithered transparent.png", "res://assets/ui/avs03pro logo sml.png"]
const ARROW := "uid://qtcyq70j3mqq"
const HAND := "res://scenes/game_object/player/cursrorhand.png"
const CURSOR_OFFSET := Vector2(6, 10)
const TITLE := "Notice from AVaSt"
const TITLE_FONTS := ["res://avast/api/assets/fonts/fs-tahoma-8px-bold.ttf", "res://gdpatch/mods/avast_core/assets/fonts/fs-tahoma-8px-bold.ttf"]
const YELLOW := Color(1, 0.85, 0.15)
const MESSAGE := "AVaSt wasn't made for the demo version, so some mods may not work right.\nI recommend buying Antivirus Survivors 2003 Professional and playing the full version."

func _ready() -> void:
	check(self)

static func is_demo() -> bool:
	var ids := [OS.get_environment("SteamAppId"), OS.get_environment("SteamGameId"), str(ProjectSettings.get_setting("steam/initialization/app_data/app_id", ""))]
	if DEMO_APP_ID in ids:
		return true
	return OS.get_executable_path().get_base_dir().get_file().to_lower().ends_with("demo")

static func check(host: Node) -> bool:
	if not is_demo():
		return false
	if not Engine.has_meta("avast_demo_notice"):
		Engine.set_meta("avast_demo_notice", true)
		host.get_tree().root.add_child.call_deferred(_notice())
	return true

static func _notice() -> CanvasLayer:
	var notice := CanvasLayer.new()
	notice.layer = 128
	notice.process_mode = Node.PROCESS_MODE_ALWAYS
	var screen := ColorRect.new()
	screen.color = Color(0.02, 0.03, 0.08, 0.94)
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	notice.add_child(screen)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)
	for path in LOGOS:
		if ResourceLoader.exists(path):
			var logo := TextureRect.new()
			logo.texture = load(path)
			logo.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			column.add_child(logo)
			break
	var title := Label.new()
	title.text = TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", YELLOW)
	for path in TITLE_FONTS:
		if FileAccess.file_exists(path):
			var font := FontFile.new()
			font.data = FileAccess.get_file_as_bytes(path)
			font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			font.hinting = TextServer.HINTING_NONE
			font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			title.add_theme_font_override("font", font)
			break
	column.add_child(title)
	var text := Label.new()
	text.text = MESSAGE
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 460
	column.add_child(text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var store := Button.new()
	store.text = "Steam store page"
	store.pressed.connect(OS.shell_open.bind(STORE_PAGE))
	buttons.add_child(store)
	var ok := Button.new()
	ok.text = "OK"
	ok.custom_minimum_size.x = 80
	ok.pressed.connect(notice.queue_free)
	buttons.add_child(ok)
	var pointer := TextureRect.new()
	pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.add_child(pointer)
	var arrow: Texture2D = load(ARROW) if ResourceLoader.exists(ARROW) else null
	var hand: Texture2D = load(HAND) if ResourceLoader.exists(HAND) else arrow
	var mode := Input.MOUSE_MODE_HIDDEN if arrow != null else Input.MOUSE_MODE_VISIBLE
	var mouse := Timer.new()
	mouse.wait_time = 0.01
	mouse.autostart = true
	mouse.timeout.connect(func():
		if Input.mouse_mode != mode:
			notice.set_meta("mouse", Input.mouse_mode)
			Input.mouse_mode = mode
		if arrow != null:
			pointer.texture = hand if notice.get_viewport().gui_get_hovered_control() is BaseButton else arrow
			pointer.position = (notice.get_viewport().get_mouse_position() + CURSOR_OFFSET - pointer.texture.get_size() / 2).round()
	)
	notice.add_child(mouse)
	notice.tree_exited.connect(func():
		Input.mouse_mode = notice.get_meta("mouse", Input.MOUSE_MODE_VISIBLE)
	)
	return notice
