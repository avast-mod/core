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
# the "Game crashed" window. shows what went wrong, which mod probably caused it and the details,
# player can copy, save or upload a report from here.
# with an error record its a live script error, without one its a crash from the last session

extends "res://gdpatch/mods/avast_core/ui/overlay.gd"

var on_ignore := Callable()

var _reporter
var _record: Dictionary
var _report := ""
var _status: Label
var _upload: Button
var _upload_armed := false

func _init(reporter, record: Dictionary = {}) -> void:
	super("Game crashed" if record.is_empty() else "Game error", Vector2(440, 290))
	_reporter = reporter
	_record = record
	layer = 200

func _build() -> void:
	_report = _reporter.report(_record)
	var heading := label("The game closed unexpectedly last time." if _record.is_empty() else "The game hit an error and may not work correctly from here.")
	heading.add_theme_color_override("font_color", Color(0.65, 0.05, 0.05))
	body.add_child(heading)
	body.add_child(label(_cause()))
	var details := text_box()
	details.bbcode_enabled = false
	details.text = _report
	body.add_child(details)
	_status = label("", false)
	_status.clip_text = true
	body.add_child(_status)

	var share: Array = [button("Copy report", _copy), button("Save full log", _save)]
	if not str(_reporter.core.config("debug", "upload_url", "")).is_empty():
		_upload = button("Upload log", _do_upload)
		share.append(_upload)
	body.add_child(row(share))

	var actions: Array = []
	if not _record.is_empty():
		actions.append(button("Ignore similar", func() -> void:
			if on_ignore.is_valid():
				on_ignore.call(_record)
			close()))
	actions.append(spacer())
	if _reporter.core.run.active():
		actions.append(button("Back to desktop", _to_desktop))
	actions.append(button("Quit game", func() -> void: get_tree().quit()))
	actions.append(button("Continue", close))
	body.add_child(row(actions))

func _cause() -> String:
	if _record.is_empty():
		return "Below is what was logged right before it closed. Save or upload the full log and send it to the mod's author, or to the game's developer if no mod is named."
	var who: String = _reporter.culprit(_record)
	if who.is_empty():
		return "The error comes from the game itself, not from a mod."
	var info = _reporter.core.mods.info(who)
	var name: String = info.title() if info else who
	return "Probably caused by the mod %s. Send the report to its author." % name

func _copy() -> void:
	DisplayServer.clipboard_set(_report)
	_status.text = "Report copied. Paste it in a bug report or a message."

func _save() -> void:
	var path: String = _reporter.save(_report, _record.is_empty())
	_status.text = "Saved to " + path
	OS.shell_open(path.get_base_dir())

func _do_upload() -> void:
	if not _upload_armed:
		_upload_armed = true
		_upload.text = "Click to confirm"
		_status.text = "This uploads the report and full log as a public link. Your home folder and Steam id are hidden."
		return
	_upload.disabled = true
	_status.text = "Uploading..."
	var full_log: String = _reporter.previous_log() if _record.is_empty() else _reporter.session_log()
	var link: String = await _reporter.upload(_report + "\n\n\nFull log\n========\n" + full_log)
	if not is_inside_tree():
		return
	_upload.disabled = false
	_upload.text = "Upload log"
	_upload_armed = false
	if link.is_empty():
		_status.text = "Upload failed. Use Save full log and send the file instead."
	else:
		DisplayServer.clipboard_set(link)
		_status.text = "Link copied: " + link

func _to_desktop() -> void:
	close()
	Engine.get_main_loop().root.get_node("GameEvents").return_to_main_menu()
