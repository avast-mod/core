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
# AVaSt Debug window (F8). versions, mod problems, recent errors and the live log. nothing fancy

extends "res://gdpatch/mods/avast_core/ui/overlay.gd"

const _LEVEL_COLORS := {"SCRIPT ERROR": "#b00000", "ERROR": "#b00000", "WARNING": "#a05a00"}

var _core: Node
var _info: RichTextLabel
var _errors: RichTextLabel
var _log: RichTextLabel
var _stats_button: Button

func _init(core: Node) -> void:
	super("AVaSt Debug", Vector2(540, 310))
	_core = core

func _build() -> void:
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	body.add_child(tabs)
	_info = text_box()
	_info.name = "Info"
	tabs.add_child(_info)
	_errors = text_box()
	_errors.name = "Errors"
	tabs.add_child(_errors)
	_log = text_box()
	_log.name = "Log"
	_log.scroll_following = true
	tabs.add_child(_log)

	_stats_button = button("", _toggle_stats)
	var buttons: Array = [
		button("Copy info", func() -> void: DisplayServer.clipboard_set(_core.reporter.summary())),
		button("Logs folder", func() -> void: OS.shell_open(_core.reporter.dir.path_join("logs"))),
		_stats_button,
	]
	buttons.append(spacer())
	buttons.append(button("Refresh", _fill))
	buttons.append(button("Close", close))
	body.add_child(row(buttons))
	_fill()

func _fill() -> void:
	_stats_button.text = "Stats overlay: " + ("on" if _core.stats_overlay_visible() else "off")
	var reporter = _core.reporter
	var mods = _core.mods
	var lines := PackedStringArray([
		"[b]Versions[/b]",
		"Game build %s, Godot %s, GDPatch %s" % [mods.game_build(), Engine.get_version_info().string, reporter.gdpatch_version()],
		"AVaSt API %s, AVaSt Core %s" % [_core.API_VERSION, mods.info(_core.mod_id).version if mods.info(_core.mod_id) else "?"],
		"%s %s, %s" % [OS.get_name(), OS.get_version(), RenderingServer.get_video_adapter_name()],
		"",
		"[b]Now[/b]",
		"Scene: %s" % (get_tree().current_scene.scene_file_path if get_tree().current_scene else "none"),
		"FPS %d, %d nodes, %d objects, %.0f MB video memory" % [
			Engine.get_frames_per_second(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0],
		"",
		"[b]Mods[/b]",
	])
	for info in mods.list():
		var problems: Array = mods.problems(info.id)
		lines.append("%s %s [color=#00000088](%s)[/color]%s" % [info.name, info.version, info.id,
			"" if problems.is_empty() else "\n   [color=#b00000]%s[/color]" % "\n   ".join(problems)])
	lines.append("")
	lines.append("[b]Files[/b]")
	lines.append("[url=%s]Logs[/url]   [url=%s]Crash reports[/url]   [url=%s]GDPatch folder[/url]" % [
		reporter.dir.path_join("logs"), reporter.dir.path_join("reports"), mods.root()])
	_info.text = "\n".join(lines)

	var errors: Array = reporter.capture.errors()
	errors.reverse()
	var shown := PackedStringArray()
	for record in errors:
		var where := "%s:%d" % [record.file, record.line]
		var who: String = reporter.culprit(record)
		shown.append("[color=#00000088]%s[/color] [color=%s]%s[/color] %s\n   %s%s" % [
			record.time.get_slice("T", 1), "#b00000" if record.type != 1 else "#a05a00",
			["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(record.type, 0, 3)], _escape(record.message), where,
			"  (mod: %s)" % who if not who.is_empty() else ""])
	_errors.text = "\n".join(shown) if not shown.is_empty() else "No errors so far."
	(_errors.get_parent() as TabContainer).set_tab_title(1, "Errors (%d)" % errors.size())

	var log_lines := PackedStringArray()
	for line in reporter.capture.lines(300):
		var color := ""
		for level in _LEVEL_COLORS:
			if line.contains(level + ":"):
				color = _LEVEL_COLORS[level]
				break
		log_lines.append("[color=%s]%s[/color]" % [color, _escape(line)] if color else _escape(line))
	_log.text = "\n".join(log_lines)

func _toggle_stats() -> void:
	_core.set_stats_overlay(not _core.stats_overlay_visible())
	_fill()

static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
