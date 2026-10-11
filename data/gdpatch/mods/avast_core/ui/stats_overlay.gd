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
# small corner readout for modders: FPS, scene, round, enemies, memory.
# own canvas layer above the monitor frame and the CRT filter, pinned top left of the game window,
# so the desktop camera and the frame dont move or cover it

extends CanvasLayer

var _core: Node
var _label: Label
var _wait := 0.0

func _init(core: Node) -> void:
	_core = core
	layer = 190
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := PanelContainer.new()
	panel.position = Vector2(2, 2)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_content_margin_all(3)
	panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	panel.add_child(_label)
	add_child(panel)

func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 0.25
	var lines := ["FPS %d  %.1f ms" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0]]
	if _core.run.active():
		lines.append("Round %d  %ds  %d enemies" % [_core.run.round_number(), _core.run.time(), _core.enemies.alive().size()])
	else:
		lines.append("Desktop")
	lines.append("%d nodes  %.0f MB video" % [Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	_label.text = "\n".join(lines)
