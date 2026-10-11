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
# crash detection + the crash reports.
#
# script errors get caught live thru the logger (log_capture.gd). hard crashes, where the process
# just dies, cant be caught. so every session leaves a lock file and removes it on a clean exit,
# if its still there next start the last session crashed and its log is still on disk.
# reports hide the players home folder and steam id before anything leaves the machine

extends RefCounted

const LogCapture := preload("res://gdpatch/mods/avast_core/crash/log_capture.gd")
const Safety := preload("res://gdpatch/mods/avast_core/safety.gd")
const KEEP := 10

var dir := ""
var capture: LogCapture
var previous_crash := {}

var core: Node
var _log_path := ""

func _init(core_node: Node) -> void:
	core = core_node

func start() -> void:
	dir = core.mods.root().path_join("avast")
	for sub in ["logs", "reports"]:
		DirAccess.make_dir_recursive_absolute(dir.path_join(sub))
	var lock := dir.path_join("session.lock")
	if FileAccess.file_exists(lock):
		var text := FileAccess.get_file_as_string(lock)
		var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
		previous_crash = data if data is Dictionary else {"log": ""}
	_prune(dir.path_join("logs"), KEEP - 1)
	_prune(dir.path_join("reports"), KEEP)
	_log_path = dir.path_join("logs/session-%s.log" % _stamp())
	capture = LogCapture.new(_log_path)
	for line in _read(core.mods.root().path_join("output.log")).split("\n", false):
		capture.add_line("[early] " + line)
	OS.add_logger(capture)
	var file := FileAccess.open(lock, FileAccess.WRITE)
	file.store_string(JSON.stringify({"started": Time.get_datetime_string_from_system(), "log": _log_path}))

func stop() -> void:
	if capture == null:
		return
	OS.remove_logger(capture)
	capture.close()
	DirAccess.remove_absolute(dir.path_join("session.lock"))

func culprit(record: Dictionary) -> String:
	var files: Array = [record.get("file", "")]
	for frame in record.get("frames", []):
		files.append(frame.file)
	for file: String in files:
		if file.begins_with("res://gdpatch/mods/"):
			return file.trim_prefix("res://gdpatch/mods/").get_slice("/", 0)
	for file: String in files:
		if file.begins_with("res://avast/api/"):
			return "avast_api"
	for file: String in files:
		if not file.begins_with("res://"):
			continue
		for info in core.mods.list():
			if not info.dir.is_empty() and FileAccess.file_exists(info.dir.path_join("data").path_join(file.trim_prefix("res://"))):
				return info.id
	return ""

func report(record: Dictionary = {}) -> String:
	var out := PackedStringArray()
	var mods = core.mods
	out.append("AVaSt crash report")
	out.append("==================")
	out.append("Time: " + Time.get_datetime_string_from_system(false, true))
	if record.is_empty():
		out.append("What happened: the game closed unexpectedly during the session started " + str(previous_crash.get("started", "?")))
	else:
		out.append("What happened: %s" % ("script error" if record.type == LogCapture.ERROR_TYPE_SCRIPT else "error"))
		out.append("Error: " + str(record.message))
		out.append("Where: %s (%s:%d)" % [record.function, record.file, record.line])
		var who := culprit(record)
		if not who.is_empty():
			var info = mods.info(who)
			out.append("Likely cause: %s %s (%s)" % [info.name if info else who, info.version if info else "", who])
		if not record.frames.is_empty():
			out.append("Call stack:")
			for i in record.frames.size():
				var f: Dictionary = record.frames[i]
				out.append("  [%d] %s (%s:%d)" % [i, f.function, f.file, f.line])
	out.append("")
	out.append(summary())
	out.append("")
	out.append("Recent log:")
	if record.is_empty():
		var lines := _read(str(previous_crash.get("log", ""))).split("\n", false)
		out.append_array(lines.slice(maxi(0, lines.size() - 150)))
	else:
		out.append_array(PackedStringArray(capture.lines(150)))
	return redact("\n".join(out))

func summary() -> String:
	var mods = core.mods
	var out := PackedStringArray()
	out.append("Game build: %s, Godot %s, GDPatch %s" % [mods.game_build(), Engine.get_version_info().string, gdpatch_version()])
	out.append("AVaSt API %s, AVaSt Core %s" % [core.API_VERSION, _core_version()])
	out.append("System: %s %s, %s" % [OS.get_name(), OS.get_version(), RenderingServer.get_video_adapter_name()])
	var scene := core.get_tree().current_scene
	out.append("Scene: %s%s" % [scene.scene_file_path if scene else "none", ", round %d" % core.run.round_number() if core.run.active() else ""])
	out.append("")
	var list: Array = mods.list()
	out.append("Mods (%d):" % list.size())
	for info in list:
		var problems: Array = mods.problems(info.id)
		out.append("  %s %s%s" % [info.id, info.version, "  [%s]" % " ".join(problems) if not problems.is_empty() else ""])
	return redact("\n".join(out))

func save(report_text: String, previous: bool = false) -> String:
	var path := dir.path_join("reports/crash-%s.txt" % _stamp())
	var full_log := _read(str(previous_crash.get("log", "")) if previous else _log_path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(report_text + "\n\n\nFull log\n========\n" + redact(full_log))
	file.close()
	return path

func upload(text: String) -> String:
	var url := str(core.config("debug", "upload_url", ""))
	if not Safety.is_secure_url(url):
		return ""
	var tls := url.begins_with("https://")
	var rest := url.substr(8 if tls else 7)
	var path := rest.substr(rest.find("/")) if rest.contains("/") else "/"
	var authority := rest.get_slice("/", 0)
	var port := authority.get_slice(":", 1).to_int() if authority.contains(":") else (443 if tls else 80)
	var client := HTTPClient.new()
	if client.connect_to_host(authority.get_slice(":", 0), port, TLSOptions.client() if tls else null) != OK:
		return ""
	var headers := ["Content-Type: text/plain; charset=utf-8", "User-Agent: AVaSt"]
	var failed := [HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]
	var body := PackedByteArray()
	var code := 0
	var sent := false
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		client.poll()
		var status := client.get_status()
		if client.has_response():
			code = client.get_response_code()
		if status == HTTPClient.STATUS_BODY:
			body.append_array(client.read_response_body_chunk())
		elif status == HTTPClient.STATUS_CONNECTED and not sent:
			client.request(HTTPClient.METHOD_POST, path, headers, text)
			sent = true
		elif (status == HTTPClient.STATUS_CONNECTED and sent) or status in failed:
			break
		await core.get_tree().process_frame
	client.close()
	var link := body.get_string_from_utf8().strip_edges()
	return link if code >= 200 and code < 300 and link.begins_with("http") else ""

func session_log() -> String:
	return redact(_read(_log_path))

func previous_log() -> String:
	return redact(_read(str(previous_crash.get("log", ""))))

static func redact(text: String) -> String:
	for home in [OS.get_environment("HOME"), OS.get_environment("USERPROFILE")]:
		if home.length() > 3:
			text = text.replace(home, "~").replace(home.replace("\\", "/"), "~")
	var steam_id := RegEx.create_from_string("7656119\\d{10}")
	return steam_id.sub(text, "<steam id>", true)

func gdpatch_version() -> String:
	var first := _read(core.mods.root().path_join("output.log")).get_slice("\n", 0)
	var found := RegEx.create_from_string("GDPatch ([0-9][^ ,]*)").search(first)
	return found.get_string(1) if found else "?"

func _core_version() -> String:
	var info = core.mods.info(core.mod_id)
	return info.version if info else "?"

static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if not path.is_empty() and FileAccess.file_exists(path) else ""

static func _stamp() -> String:
	return Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")

static func _prune(folder: String, keep: int) -> void:
	var files := Array(DirAccess.get_files_at(folder))
	files.sort()
	for i in maxi(0, files.size() - keep):
		DirAccess.remove_absolute(folder.path_join(files[i]))
