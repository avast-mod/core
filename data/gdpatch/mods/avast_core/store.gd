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
# client for the AVaSt mod server. featured, search, mod pages, download counts, installs.
# store.url is the api address (ends in /api). empty url = every call just answers offline.
#
# the server basically has one answer, /v1/i, every listed mod as a compact row. we keep it in
# memory and in GDPatch/avast/store/index.json and ask again max once an hour (or on Reload) with
# If-None-Match. search, categories, sorting, pages all run on that copy.
# readmes, release notes and zips come from github, they never touch our server

extends Node

signal status_changed
signal _index_done
signal _text_done

const Library := preload("res://gdpatch/mods/avast_core/library.gd")
const Safety := preload("res://gdpatch/mods/avast_core/safety.gd")
const TIMEOUT := 10.0
const INDEX_FRESH := 3600
const _LIMITS := {"api": 16 * 1024 * 1024, "readme": 1024 * 1024, "notes": 1024 * 1024, "image": Safety.MAX_IMAGE_BYTES, "download": 64 * 1024 * 1024}
const _MAX_TEXTURES := 300
const _CATEGORY_CHARS := "0123456789abc"

var state := ""
var last_error := ""
var downloads := {}
var progress := {}

var _core: Node
var _textures := {}
var _texts := {}
var _waiting := {}
var _mods: Array = []
var _have := false
var _bases := {}
var _etag := ""
var _checked := 0
var _loading := false
var _origins := {}

func setup(core: Node) -> void:
	_core = core
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_origins_path())) if FileAccess.file_exists(_origins_path()) else null
	_origins = saved if saved is Dictionary else {}

func url() -> String:
	return str(_core.config("store", "url", "")).strip_edges().trim_suffix("/")

func available() -> bool:
	return not url().is_empty()

func refresh() -> void:
	_checked = 0

func mods() -> Dictionary:
	if not available():
		_set_state("offline", "The AVaSt server isn't set up.")
		return {"error": "offline"}
	if not Safety.is_secure_url(url()):
		_set_state("offline", "The AVaSt server address has to start with https://.")
		return {"error": "offline"}
	if _loading:
		await _index_done
		return _answer()
	if not _have:
		_read_disk()
	if _have and int(Time.get_unix_time_from_system()) - _checked < INDEX_FRESH:
		_set_state("ok", "")
		return _answer()
	_loading = true
	_set_state("loading", "")
	var headers := PackedStringArray()
	if not _etag.is_empty() and _have:
		headers.append("If-None-Match: " + _etag)
	var response := await _request(url() + "/v1/i", "", "", true, "api", headers)
	if response.code == 304:
		_checked = int(Time.get_unix_time_from_system())
		_write_disk()
		_set_state("ok", "")
	elif response.code == 200 and _use(JSON.parse_string(response.get("text", ""))):
		_etag = _header(response.get("headers", PackedStringArray()), "etag")
		_checked = int(Time.get_unix_time_from_system())
		_write_disk()
		_set_state("ok", "")
	elif response.code == 0:
		_set_state("offline", "Can't reach the AVaSt server.")
	else:
		_set_state("offline", "The AVaSt server answered with an error (%d)." % response.code)
	_loading = false
	_index_done.emit()
	return _answer()

func featured() -> Dictionary:
	var data := await mods()
	if data.has("error"):
		return data
	return {"mods": data.mods.filter(func(mod: Dictionary) -> bool: return mod.featured)}

func search(query: String, category: String, sort: String, page: int, per_page: int = 40) -> Dictionary:
	var data := await mods()
	if data.has("error"):
		return data
	var text := query.strip_edges().to_lower()
	var found: Array = data.mods.filter(func(mod: Dictionary) -> bool:
		if not category.is_empty() and not mod.categories.has(category):
			return false
		return text.is_empty() or [mod.name, mod.id, ", ".join(mod.authors), mod.summary].any(func(field: String) -> bool: return field.to_lower().contains(text)))
	if sort == "new":
		found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.updated > b.updated or (a.updated == b.updated and a.id < b.id))
	elif sort == "name":
		found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var order: int = str(a.name).naturalnocasecmp_to(str(b.name))
			return order < 0 or (order == 0 and a.id < b.id))
	var pages := maxi(1, ceili(found.size() / float(per_page)))
	page = clampi(page, 1, pages)
	return {"mods": found.slice((page - 1) * per_page, page * per_page), "total": found.size(), "page": page, "pages": pages}

func details(id: String) -> Dictionary:
	var data := await mods()
	if data.has("error"):
		return data
	var mod := _find(id)
	if mod.is_empty():
		last_error = "This mod isn't in the AVaSt library anymore."
		return {"error": "missing"}
	var page := mod.duplicate()
	page.readme = await _text(mod.readme_url)
	page.changelog = await _text(mod.changelog_url)
	return page

func release_notes(id: String) -> String:
	var mod := _find(id)
	if mod.is_empty() or _bases.is_empty():
		return ""
	var link := "%s/release" % mod.base if str(mod.repo).begins_with("/") else "%s/repos/%s/releases/tags/%s" % [_bases.api, mod.repo, str(mod.tag).uri_encode()]
	var response := await _request(link, "", "", true, "notes")
	var data: Variant = JSON.parse_string(response.get("text", "")) if response.code == 200 else null
	return Safety.text(str(data.get("body", ""))) if data is Dictionary else ""

func stats(ids: Array) -> void:
	await latest(ids)

func latest(ids: Array) -> Dictionary:
	if ids.is_empty() or not available():
		return {}
	var data := await mods()
	var found := {}
	for mod: Dictionary in data.get("mods", []):
		if ids.has(mod.id):
			found[mod.id] = {"version": mod.version, "download": mod.download, "size": mod.size, "repo": mod.repo}
			downloads[mod.id] = mod.downloads
	return found

func texture(image_url: String, done: Callable, holder: Object = null, max_side: int = Safety.MAX_SIDE) -> void:
	if image_url.is_empty() or not Safety.is_secure_url(_absolute(image_url)):
		done.call(null)
		return
	if _textures.has(image_url):
		done.call(_textures[image_url])
		return
	var entry := [done, weakref(holder) if holder != null else null]
	if _waiting.has(image_url):
		_waiting[image_url].append(entry)
		return
	_waiting[image_url] = [entry]
	var response := await _request(_absolute(image_url), "", "", false, "image")
	var image: Image = Safety.image(response.get("bytes", PackedByteArray()), max_side) if response.code == 200 else null
	if _textures.size() >= _MAX_TEXTURES:
		_textures.clear()
	_textures[image_url] = ImageTexture.create_from_image(image) if image != null else null
	for waiter: Array in _waiting[image_url]:
		var alive: bool = waiter[1] == null or waiter[1].get_ref() != null
		if alive and waiter[0].is_valid():
			waiter[0].call(_textures[image_url])
	_waiting.erase(image_url)

func needs(id: String) -> Dictionary:
	var out := {"mods": [], "off": [], "unknown": []}
	_walk_needs(id, [id], out)
	return out

func _walk_needs(id: String, seen: Array, out: Dictionary) -> void:
	for dep: String in _find(id).get("dependencies", []):
		if dep in seen:
			continue
		seen.append(dep)
		if _core.library.info(dep) != null and not _core.library.is_removed(dep):
			if _core.library.is_disabled(dep):
				out.off.append(dep)
			continue
		var found := _find(dep)
		if found.is_empty():
			out.unknown.append(dep)
			continue
		_walk_needs(dep, seen, out)
		out.mods.append(found)

func install(mod: Dictionary) -> String:
	var id := str(mod.get("id", ""))
	var updater: Node = _core.updater
	if not Safety.is_id(id) or str(mod.get("download", "")).is_empty():
		return "This mod has no download."
	if mod.has("repo") and id in Library.REQUIRED:
		return "AVaSt updates itself from its own releases."
	if mod.has("repo") and not same_source(id, str(mod.repo)):
		return "This mod was installed from somewhere else, so the AVaSt server can't update it."
	if updater.status.get(id) == "downloading":
		return ""
	updater.set_status(id, "downloading")
	progress[id] = {"fraction": 0.0, "bytes": 0, "total": 0, "speed": 0.0}
	var needed := needs(id)
	var error := ""
	if not needed.unknown.is_empty():
		error = "It needs %s, which the AVaSt library doesn't have." % ", ".join(needed.unknown)
	for dep: String in needed.off:
		if error.is_empty():
			error = _core.library.enable(dep)
	for dep: Dictionary in needed.mods:
		if not error.is_empty():
			break
		if updater.status.get(dep.id) == "downloading":
			continue
		updater.set_status(dep.id, "downloading")
		var failed: String = await _download(dep)
		if not failed.is_empty():
			error = "Couldn't install %s, which it needs: %s" % [dep.name, failed]
	if not error.is_empty():
		progress.erase(id)
		_core.warn("store: installing %s failed: %s" % [id, error])
		updater.set_status(id, error)
		return error
	return await _download(mod)

func _download(mod: Dictionary) -> String:
	var id := str(mod.get("id", ""))
	var updater: Node = _core.updater
	progress[id] = {"fraction": 0.0, "bytes": 0, "total": 0, "speed": 0.0}
	_core.info("store: installing %s %s from %s" % [id, mod.get("version", ""), _absolute(str(mod.download))])
	var started := Time.get_ticks_msec()
	var zip_path: String = _core.reporter.dir.path_join("updates/downloads/%s-%s.zip" % [id, mod.get("version", "")])
	DirAccess.make_dir_recursive_absolute(zip_path.get_base_dir())
	var response := await _request(_absolute(str(mod.download)), zip_path, id, true, "download")
	var size := FileAccess.get_file_as_bytes(zip_path).size() if FileAccess.file_exists(zip_path) else 0
	var seconds := maxf((Time.get_ticks_msec() - started) / 1000.0, 0.001)
	progress.erase(id)
	var error := ""
	if response.code != 200:
		error = "Download failed (%s)." % (response.code if response.code > 0 else "no connection")
	elif _core.library.info(id) != null and not _core.library.is_removed(id):
		error = updater.apply_zip(_core.library.info(id), zip_path)
	else:
		error = updater.unpack_new(id, zip_path)
	DirAccess.remove_absolute(zip_path)
	if not error.is_empty():
		_core.warn("store: installing %s failed: %s" % [id, error])
		updater.set_status(id, error)
		return error
	var where: String = _core.library.info(id).dir if _core.library.info(id) != null and not _core.library.is_removed(id) else _core.library.mods_dir().path_join(id)
	_core.info("store: installed %s %s (%s in %.1f s, %s/s) into %s" % [id, mod.get("version", ""), size_text(size), seconds, size_text(int(size / seconds)), where])
	if mod.has("repo"):
		_origins[id] = str(mod.repo)
		_save_origins()
	_core.library.reinstalled(id)
	_core.library.installed_now(id)
	updater.changed[id] = true
	updater.set_status(id, "installed")
	return ""

func same_source(id: String, repo: String = "") -> bool:
	var installed = _core.library.info(id)
	if installed == null or _core.library.is_removed(id):
		return true
	var listed := repo if not repo.is_empty() else str(_find(id).get("repo", ""))
	return not listed.is_empty() and _origins.get(id, "") == listed

func _origins_path() -> String:
	return _core.reporter.dir.path_join("store/origins.json")

func _save_origins() -> void:
	DirAccess.make_dir_recursive_absolute(_origins_path().get_base_dir())
	var file := FileAccess.open(_origins_path(), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_origins, "\t"))
		file.close()

static func size_text(bytes: int) -> String:
	if bytes >= 1048576:
		return "%.1f MB" % (bytes / 1048576.0)
	if bytes >= 1024:
		return "%d KB" % int(bytes / 1024.0)
	return "%d B" % bytes

func _answer() -> Dictionary:
	if not _have:
		return {"error": state if not state.is_empty() else "offline"}
	return {"mods": _mods}

func _find(id: String) -> Dictionary:
	for mod: Dictionary in _mods:
		if mod.id == id:
			return mod
	return {}

func _use(data: Variant) -> bool:
	if not data is Dictionary or not data.get("m") is Array:
		return false
	var bases := {"raw": str(data.get("h", "")), "api": str(data.get("g", "")), "web": str(data.get("w", ""))}
	if not bases.values().all(func(base: String) -> bool: return Safety.is_secure_url(base)):
		return false
	_bases = bases
	Safety.allow_host(url())
	Safety.allow_host(bases.raw)
	var list: Array = []
	for row: Variant in data.m:
		if row is Array and row.size() >= 18:
			var mod := _mod(row)
			if not mod.is_empty():
				list.append(mod)
	_mods = list
	_have = true
	return true

func _mod(row: Array) -> Dictionary:
	var repo := str(row[8])
	var tag := str(row[9])
	var test := repo.begins_with("/")
	var dependencies: Array = Array(str(row[18]).split(",", false)).map(func(dep: String) -> String: return dep.strip_edges()) if row.size() > 18 else []
	if not Safety.is_id(str(row[0])) or not Safety.is_version(str(row[2])) or not Safety.is_repo(repo) \
			or not dependencies.all(func(dep: String) -> bool: return Safety.is_id(dep)):
		return {}
	var website := str(row[17])
	var base := "%s/%s" % [url() + repo if test else _bases.raw + "/" + repo, tag.uri_encode()]
	var asset := str(row[14]).uri_encode()
	var categories: Array = []
	for c in str(row[5]):
		var index := _CATEGORY_CHARS.find(c)
		if index >= 0 and index < Library.CATEGORIES.size():
			categories.append(Library.CATEGORIES.keys()[index])
	return {
		"id": str(row[0]), "name": str(row[1]), "version": str(row[2]),
		"authors": Array(str(row[3]).split(",", false)).map(func(author: String) -> String: return author.strip_edges()),
		"summary": str(row[4]), "categories": categories, "downloads": int(row[6]), "featured": int(row[7]) == 1,
		"repo": repo, "tag": tag, "icon": _file(base, str(row[10])), "banner": _file(base, str(row[11])),
		"updated": int(row[12]), "size": int(row[13]),
		"download": base + "/" + asset if test else "%s/%s/releases/download/%s/%s" % [_bases.web, repo, tag.uri_encode(), asset],
		"readme_url": _file(base, str(row[15])), "changelog_url": _file(base, str(row[16])),
		"website": website if website.begins_with("https://") else "", "base": base, "dependencies": dependencies,
	}

func _file(base: String, path: String) -> String:
	return "" if path.is_empty() else base + "/" + "/".join(Array(path.split("/")).map(func(part: String) -> String: return part.uri_encode()))

func _text(link: String) -> String:
	if link.is_empty():
		return ""
	while _texts.has(link) and _texts[link] == null:
		await _text_done
	if _texts.has(link):
		return _texts[link]
	_texts[link] = null
	var response := await _request(link, "", "", true, "readme")
	var text := Safety.text(response.get("text", "")) if response.code == 200 else ""
	if response.code == 200:
		_texts[link] = text
	else:
		_texts.erase(link)
	_text_done.emit()
	return text

func _disk_path() -> String:
	return _core.reporter.dir.path_join("store/index.json")

func _read_disk() -> void:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_disk_path())) if FileAccess.file_exists(_disk_path()) else null
	if not saved is Dictionary or str(saved.get("url", "")) != url() or not _use(saved.get("data")):
		return
	_etag = str(saved.get("etag", ""))
	_checked = int(saved.get("checked", 0))

func _write_disk() -> void:
	DirAccess.make_dir_recursive_absolute(_disk_path().get_base_dir())
	var rows: Array = _mods.map(func(mod: Dictionary) -> Array: return _row(mod))
	var file := FileAccess.open(_disk_path(), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"url": url(), "etag": _etag, "checked": _checked,
		"data": {"h": _bases.raw, "g": _bases.api, "w": _bases.web, "m": rows}}))
	file.close()

func _row(mod: Dictionary) -> Array:
	var cats := ""
	for category: String in mod.categories:
		cats += _CATEGORY_CHARS[Library.CATEGORIES.keys().find(category)]
	var path := func(link: String) -> String: return link.trim_prefix(mod.base + "/").uri_decode() if not link.is_empty() else ""
	return [mod.id, mod.name, mod.version, ", ".join(mod.authors), mod.summary, cats, mod.downloads, 1 if mod.featured else 0,
		mod.repo, mod.tag, path.call(mod.icon), path.call(mod.banner), mod.updated, mod.size, mod.download.get_file().uri_decode(),
		path.call(mod.readme_url), path.call(mod.changelog_url), mod.website, ",".join(mod.get("dependencies", []))]

static func _header(headers: PackedStringArray, name: String) -> String:
	for line in headers:
		if line.to_lower().begins_with(name + ":"):
			return line.substr(name.length() + 1).strip_edges()
	return ""

func _set_state(value: String, error: String) -> void:
	state = value
	last_error = error
	status_changed.emit()

func _absolute(link: String) -> String:
	return link if link.contains("://") else url() + "/" + link.trim_prefix("/")

func _request(link: String, download_to: String, progress_id: String = "", as_text: bool = true, kind: String = "", headers := PackedStringArray()) -> Dictionary:
	var started := Time.get_ticks_msec()
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT if download_to.is_empty() else 120.0
	http.download_file = download_to
	http.body_size_limit = _LIMITS.get(kind, 1024 * 1024)
	add_child(http)
	var result := {"code": 0}
	if not Safety.is_secure_url(link):
		_core.warn("store: refused %s %s, it isn't https" % [kind, link])
		http.queue_free()
		return result
	if http.request(link, PackedStringArray(["User-Agent: AVaSt", "Accept: application/json"]) + headers) == OK:
		if not progress_id.is_empty():
			_track(http, progress_id)
		var response: Array = await http.request_completed
		if response[0] == HTTPRequest.RESULT_SUCCESS:
			result.code = response[1]
			result.headers = response[2]
			result.bytes = response[3]
			result.text = (response[3] as PackedByteArray).get_string_from_utf8() if as_text and download_to.is_empty() else ""
		else:
			result.failure = response[0]
	http.queue_free()
	var took := Time.get_ticks_msec() - started
	if result.code == 0:
		_core.warn("store: %s %s failed (no connection, result %s, %d ms)" % [kind, link, result.get("failure", "?"), took])
	else:
		var size := http.get_downloaded_bytes() if not download_to.is_empty() else (result.bytes as PackedByteArray).size()
		_core.info("store: %s %s -> %d (%s, %d ms)" % [kind, link, result.code, size_text(size), took])
	return result

func _track(http: HTTPRequest, id: String) -> void:
	var last_bytes := 0
	var last_time := Time.get_ticks_msec()
	var logged := 0
	while is_instance_valid(http) and progress.has(id):
		await get_tree().create_timer(0.25).timeout
		if not is_instance_valid(http) or not progress.has(id):
			return
		var bytes := http.get_downloaded_bytes()
		var total := maxi(http.get_body_size(), 0)
		var now := Time.get_ticks_msec()
		var rate := (bytes - last_bytes) * 1000.0 / maxf(now - last_time, 1)
		var entry: Dictionary = progress[id]
		entry.speed = rate if entry.speed <= 0.0 else lerpf(entry.speed, rate, 0.3)
		entry.bytes = bytes
		entry.total = total
		entry.fraction = clampf(float(bytes) / total, 0.0, 1.0) if total > 0 else 0.0
		last_bytes = bytes
		last_time = now
		var quarter := int(entry.fraction * 4)
		if quarter > logged and quarter < 4:
			logged = quarter
			_core.info("store: downloading %s %d%% (%s of %s, %s/s)" % [id, quarter * 25, size_text(bytes), size_text(total), size_text(int(entry.speed))])
		status_changed.emit()
