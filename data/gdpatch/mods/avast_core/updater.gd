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
# finds newer versions of installed mods (AVaSt too) and installs them.
#
# a mod opts in with [avast.update] in its gdpatch_mod.toml:
#   github = "owner/repo"   latest github release, asset = "my_mod.zip" (default <id>.zip)
#   url = "https://.../latest.json"   {"version": "1.2.0", "url": "<zip>", "notes": "..."}
#
# GDPatch keeps every mod file open while the game runs so we cant overwrite anything in place.
# old files get moved to GDPatch/avast/updates/trash, new ones land where they were, and the update
# kicks in on the next start

extends Node

signal checked
signal status_changed(id: String)

const Toml := preload("res://avast/api/lib/toml.gd")
const Version := preload("res://avast/api/lib/version.gd")
const Safety := preload("res://gdpatch/mods/avast_core/safety.gd")
const CHECK_EVERY := 6 * 3600

var available := {}
var status := {}
var changed := {}
var restart_needed: bool:
	get: return not changed.is_empty()
var installed_updates := {}
var batch := {}
var checking := false

var _core: Node
var _dir := ""
var _cache := {}

func setup(core: Node, avast_dir: String) -> void:
	_core = core
	_dir = avast_dir.path_join("updates")
	DirAccess.make_dir_recursive_absolute(_dir.path_join("downloads"))
	_remove_tree(_dir.path_join("trash"))
	var text := _read(_dir.path_join("cache.json"))
	var cache: Variant = JSON.parse_string(text) if not text.is_empty() else null
	_cache = cache if cache is Dictionary else {}

func check(force: bool = false) -> void:
	if checking:
		return
	checking = true
	available.clear()
	_core.info("updates: checking%s" % (" (forced)" if force else ""))
	var from_store: Array = []
	for info in _core.library.all():
		if _core.library.is_removed(info.id):
			continue
		if info.update.is_empty():
			from_store.append(info.id)
			continue
		var latest: Dictionary = await _latest(info, force)
		if latest.has("error"):
			status[info.id] = latest.error
			status_changed.emit(info.id)
		elif latest.has("version") and Version.compare(latest.version, info.version) > 0 and Safety.is_secure_url(str(latest.get("url", ""))):
			available[info.id] = latest
	var store_latest: Dictionary = await _core.store.latest(from_store)
	for id in store_latest:
		var info = _core.library.info(id)
		var entry: Dictionary = store_latest[id]
		if info != null and _core.store.same_source(id) and Version.compare(str(entry.get("version", "")), info.version) > 0:
			available[id] = {"version": str(entry.version), "url": str(entry.get("download", "")), "notes": await _core.store.release_notes(id),
				"size": int(entry.get("size", 0)), "from": info.version, "source": "store"}
	var file := FileAccess.open(_dir.path_join("cache.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_cache, "\t"))
	file.close()
	_core.info("updates: %d available%s" % [available.size(), (": " + ", ".join(available.keys().map(func(k: String) -> String: return "%s %s" % [k, available[k].version]))) if not available.is_empty() else ""])
	checking = false
	checked.emit()

func install(id: String) -> bool:
	var update: Dictionary = available.get(id, {})
	var info = _core.library.info(id)
	if update.is_empty() or info == null or status.get(id) == "downloading":
		return false
	update.from = info.version
	var error: String = await _core.store.install({"id": id, "version": update.version, "download": update.url})
	if not error.is_empty():
		return false
	installed_updates[id] = update
	available.erase(id)
	return true

func install_all() -> int:
	var done := 0
	var ids: Array = available.keys()
	_core.info("updates: installing %d update%s" % [ids.size(), "" if ids.size() == 1 else "s"])
	for i in ids.size():
		batch = {"done": i, "total": ids.size(), "id": ids[i]}
		status_changed.emit(ids[i])
		if await install(ids[i]):
			done += 1
	batch = {}
	status_changed.emit("")
	_core.info("updates: %d of %d installed" % [done, ids.size()])
	return done

func _latest(info, force: bool) -> Dictionary:
	var source: Dictionary = info.update
	var cached: Dictionary = _cache.get(info.id, {})
	var now := int(Time.get_unix_time_from_system())
	if not force and now - int(cached.get("checked", 0)) < CHECK_EVERY and cached.has("version"):
		return cached
	var result := {}
	if source.has("github"):
		var headers := ["User-Agent: AVaSt", "Accept: application/vnd.github+json"]
		if cached.has("etag"):
			headers.append("If-None-Match: " + str(cached.etag))
		var response: Dictionary = await _request("https://api.github.com/repos/%s/releases/latest" % source.github, headers)
		if response.code == 304:
			cached.checked = now
			return cached
		if response.code == 404:
			return {}
		if response.code != 200:
			return {"error": "Couldn't check for updates (%s)." % (response.code if response.code > 0 else "no connection")}
		var data: Variant = JSON.parse_string(response.body)
		if not data is Dictionary:
			return {"error": "GitHub sent an unexpected answer."}
		var asset_name := str(source.get("asset", info.id + ".zip"))
		var url := ""
		for asset in data.get("assets", []):
			if asset.get("name") == asset_name:
				url = asset.get("browser_download_url", "")
		result = {
			"version": str(data.get("tag_name", "")).trim_prefix("v"),
			"url": url,
			"notes": str(data.get("body", "")),
			"page": str(data.get("html_url", "")),
			"etag": response.headers.get("etag", ""),
		}
	elif source.has("url"):
		if not Safety.is_secure_url(str(source.url)):
			return {"error": "Updates have to come over https, but [avast.update] url is %s." % source.url}
		var response: Dictionary = await _request(str(source.url), ["User-Agent: AVaSt"])
		var data: Variant = JSON.parse_string(response.body) if response.code == 200 and not response.body.is_empty() else null
		if not data is Dictionary:
			return {"error": "Couldn't check for updates (%s)." % response.code}
		result = {
			"version": str(data.get("version", "")).trim_prefix("v"),
			"url": str(data.get("url", "")),
			"notes": str(data.get("notes", data.get("changelog", ""))),
			"page": str(data.get("page", "")),
		}
	else:
		return {}
	result.checked = now
	_cache[info.id] = result
	return result

func unpack_new(id: String, zip_path: String) -> String:
	if not Safety.is_id(id):
		return "'%s' isn't a valid mod id." % id
	var problem := Safety.zip_problem(zip_path)
	if not problem.is_empty():
		return problem
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "The download isn't a zip file."
	var files := zip.get_files()
	var prefix := ""
	if files.has(id + "/gdpatch_mod.toml"):
		prefix = id + "/"
	elif not files.has("gdpatch_mod.toml"):
		return "The download has no gdpatch_mod.toml."
	var manifest := Toml.parse(zip.read_file(prefix + "gdpatch_mod.toml").get_string_from_utf8())
	if manifest.get("id") != id:
		return "The download is for another mod (%s)." % manifest.get("id")
	var target: String = _core.library.mods_dir().path_join(id)
	if DirAccess.dir_exists_absolute(target):
		return "The mods folder already has a '%s' folder." % id
	for file in files:
		var rel := file.trim_prefix(prefix)
		if not file.begins_with(prefix) or not Safety.is_zip_path(rel):
			continue
		DirAccess.make_dir_recursive_absolute(target.path_join(rel).get_base_dir())
		var out := FileAccess.open(target.path_join(rel), FileAccess.WRITE)
		if out == null:
			_remove_tree(target)
			return "Couldn't write %s." % rel
		out.store_buffer(zip.read_file(file))
		out.close()
	zip.close()
	return ""

func apply_zip(info, zip_path: String) -> String:
	var problem := Safety.zip_problem(zip_path)
	if not problem.is_empty():
		return problem
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "The download isn't a zip file."
	var files := zip.get_files()
	var prefix := ""
	if files.has(info.id + "/gdpatch_mod.toml"):
		prefix = info.id + "/"
	elif not files.has("gdpatch_mod.toml"):
		return "The download has no gdpatch_mod.toml."
	var manifest := Toml.parse(zip.read_file(prefix + "gdpatch_mod.toml").get_string_from_utf8())
	if manifest.get("id") != info.id:
		return "The download is for another mod (%s)." % manifest.get("id")
	var new_files: Array[String] = []
	for file in files:
		var rel := file.trim_prefix(prefix)
		if file.begins_with(prefix) and Safety.is_zip_path(rel):
			new_files.append(rel)

	var trash: String = _dir.path_join("trash/%d/%s" % [int(Time.get_unix_time_from_system()), info.id])
	var moved: Array[String] = []
	for rel in _walk(info.dir, ""):
		if rel.begins_with("data/") or rel in new_files:
			DirAccess.make_dir_recursive_absolute(trash.path_join(rel).get_base_dir())
			if DirAccess.rename_absolute(info.dir.path_join(rel), trash.path_join(rel)) != OK:
				_restore(info.dir, trash, moved, [])
				return "Couldn't move %s. Close other programs using the mod's files and try again." % rel
			moved.append(rel)
	var written: Array[String] = []
	for rel in new_files:
		var target: String = info.dir.path_join(rel)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			_restore(info.dir, trash, moved, written)
			return "Couldn't write %s." % rel
		out.store_buffer(zip.read_file(prefix + rel))
		out.close()
		written.append(rel)
	zip.close()
	return ""

func _restore(mod_dir: String, trash: String, moved: Array[String], written: Array[String]) -> void:
	for rel in written:
		DirAccess.remove_absolute(mod_dir.path_join(rel))
	for rel in moved:
		DirAccess.rename_absolute(trash.path_join(rel), mod_dir.path_join(rel))

func _request(url: String, headers: Array, download_to: String = "") -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 30.0
	http.download_file = download_to
	add_child(http)
	var result := {"code": 0, "body": "", "headers": {}}
	if http.request(url, PackedStringArray(headers)) == OK:
		var response: Array = await http.request_completed
		if response[0] == HTTPRequest.RESULT_SUCCESS:
			result.code = response[1]
			for header: String in response[2]:
				result.headers[header.get_slice(":", 0).strip_edges().to_lower()] = header.substr(header.find(":") + 1).strip_edges()
			if download_to.is_empty():
				result.body = (response[3] as PackedByteArray).get_string_from_utf8()
	http.queue_free()
	return result

func set_status(id: String, value: String) -> void:
	status[id] = value
	status_changed.emit(id)

static func _walk(root: String, rel: String) -> Array[String]:
	var out: Array[String] = []
	var path := root.path_join(rel)
	for file in DirAccess.get_files_at(path):
		out.append(rel.path_join(file) if not rel.is_empty() else file)
	for sub in DirAccess.get_directories_at(path):
		out.append_array(_walk(root, rel.path_join(sub) if not rel.is_empty() else sub))
	return out

static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)

static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
