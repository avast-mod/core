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
# the installed mods like core sees them: categories, turning mods off and on, uninstalling.
#
# GDPatch loads every folder in GDPatch/mods and theres no switch to skip one, so a disabled mod
# gets moved to GDPatch/avast/disabled file by file. moving works even while gdpatch has the files
# open (windows too). uninstall moves stuff to avast/updates/trash, the updater empties it on start.
# all of this applies next time the game starts

extends RefCounted

const Toml := preload("res://avast/api/lib/toml.gd")
const ModInfo := preload("res://avast/api/lib/mod_info.gd")
const Game := preload("res://avast/api/lib/game.gd")
const _API_SCRIPT := "res://avast/api/mod.gd"

const CATEGORIES := {
	"weapons": ["Weapons", "res://assets/icons/damage file-export 24.png"],
	"enemies": ["Enemies & Bosses", "res://assets/icons/enemy32.png"],
	"cursors": ["Cursors", "res://assets/icons/pointertrails32.png"],
	"protocols": ["Protocols & Policies", "res://assets/icons/shi32.png"],
	"upgrades": ["Upgrades & Plugins", "res://assets/icons/upgrades-24.png"],
	"gameplay": ["Gameplay", "res://assets/icons/play-folder-24.png"],
	"interface": ["Interface", "res://assets/icons/settings-24.png"],
	"themes": ["Themes & Wallpapers", "res://assets/icons/paint24.png"],
	"audio": ["Sounds & Music", "res://assets/icons/orchestra24dithered.png"],
	"languages": ["Languages", "res://assets/icons/internetcruiser24.png"],
	"tools": ["Tools", "res://assets/icons/driver-24.png"],
	"libraries": ["Libraries", "res://assets/icons/dllicon32.png"],
	"other": ["Other", "res://assets/icons/copy icon-export 24.png"],
}
const REQUIRED: Array[String] = ["avast_api", "avast_core"]

var _core: Node
var _disabled := {}
var _enabled := {}
var _removed := {}
var pending := {}

func _init(core: Node) -> void:
	_core = core
	_scan()

func disabled_dir() -> String:
	return _core.mods.root().path_join("avast/disabled")

func mods_dir() -> String:
	return _core.mods.root().path_join("mods")

func all() -> Array:
	var out: Array = []
	for info in _core.mods.list():
		if not _disabled.has(info.id) and not _removed.has(info.id):
			out.append(info)
	out.append_array(_disabled.values())
	out.append_array(_enabled.values())
	out.append_array(_removed.values().map(func(entry: Dictionary): return entry.info))
	out.sort_custom(func(a, b) -> bool: return a.title().naturalnocasecmp_to(b.title()) < 0)
	return out

func info(id: String):
	if _removed.has(id):
		return _removed[id].info
	return _disabled.get(id, _enabled.get(id, _core.mods.info(id)))

func is_removed(id: String) -> bool:
	return _removed.has(id)

func restart_needed() -> bool:
	return not pending.is_empty() or _removed.keys().any(func(id: String) -> bool: return _core.mods.has(id))

func is_disabled(id: String) -> bool:
	return _disabled.has(id)

func can_disable(id: String) -> bool:
	return not id in REQUIRED

func settings_file(id: String) -> String:
	return _core.mods.root().path_join("configs/%s.toml" % id)

func uninstall(id: String, settings: bool = false) -> String:
	var info = info(id)
	if info == null or _removed.has(id):
		return ""
	if not can_disable(id):
		return "%s is part of AVaSt and can't be uninstalled." % info.title()
	_core.updater.available.erase(id)
	if not _core.mods.has(id):
		_remove_tree(info.dir)
		if DirAccess.dir_exists_absolute(info.dir):
			_core.warn("library: couldn't delete %s" % info.dir)
			return "Couldn't delete %s. Close other programs using the mod's files and try again." % info.dir
		if settings:
			DirAccess.remove_absolute(settings_file(id))
		_core.info("library: uninstalled %s, deleted %s (it wasn't loaded)%s" % [id, info.dir, " and its settings" if settings else ""])
		_enabled.erase(id)
		_disabled.erase(id)
		pending.erase(id)
		_core.updater.changed.erase(id)
		_core.updater.status.erase(id)
		_core.updater.installed_updates.erase(id)
		return ""
	var trash: String = _core.mods.root().path_join("avast/updates/trash/%d-removed/%s" % [int(Time.get_unix_time_from_system()), id])
	var from: String = info.dir
	var error := _move_tree(from, trash)
	if not error.is_empty():
		_core.warn("library: uninstalling %s failed: %s" % [id, error])
		return error
	var kept := ""
	if settings and FileAccess.file_exists(settings_file(id)) and DirAccess.rename_absolute(settings_file(id), trash + ".toml") == OK:
		kept = trash + ".toml"
	_core.info("library: uninstalled %s, moved %s to %s%s" % [id, from, trash, " with its settings" if not kept.is_empty() else ""])
	info.dir = trash
	_disabled.erase(id)
	_enabled.erase(id)
	pending.erase(id)
	_removed[id] = {"info": info, "from": from, "settings": kept}
	return ""

func reinstalled(id: String) -> void:
	_removed.erase(id)

func undo_uninstall(id: String) -> String:
	if not _removed.has(id):
		return ""
	var entry: Dictionary = _removed[id]
	var error := _move_tree(entry.info.dir, entry.from)
	if not error.is_empty():
		_core.warn("library: restoring %s failed: %s" % [id, error])
		return error
	if not str(entry.get("settings", "")).is_empty():
		DirAccess.rename_absolute(entry.settings, settings_file(id))
	_core.info("library: restored %s to %s" % [id, entry.from])
	entry.info.dir = entry.from
	_removed.erase(id)
	if entry.from.begins_with(disabled_dir()):
		_disabled[id] = entry.info
		_switched(id, true)
	elif not _core.mods.has(id):
		_enabled[id] = entry.info
	return ""

static func categories(info) -> Array[String]:
	var avast: Variant = info.manifest.get("avast", {}) if info != null else {}
	var value: Variant = avast.get("categories", avast.get("category", [])) if avast is Dictionary else []
	var out: Array[String] = []
	for category in (value if value is Array else [value]):
		if not str(category).is_empty():
			out.append(str(category).to_lower())
	return out

static func plain_gdpatch(info) -> bool:
	if info == null or info.manifest.get("avast") is Dictionary:
		return false
	var gdpatch: Node = Game.gdpatch()
	var node: Node = gdpatch.mod_instances.get(info.id) if gdpatch != null else null
	if node != null:
		var script: Script = node.get_script()
		while script != null:
			if script.resource_path == _API_SCRIPT:
				return false
			script = script.get_base_script()
		return true
	var path: String = info.dir.path_join("data/gdpatch/mods/%s/mod.gd" % info.id)
	return not (FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).contains("res://avast/api/"))

static func category_name(id: String) -> String:
	return CATEGORIES[id][0] if CATEGORIES.has(id) else id.capitalize()

static func category_icon(id: String) -> Texture2D:
	return load(CATEGORIES[id][1] if CATEGORIES.has(id) else CATEGORIES.other[1])

func disable(id: String) -> String:
	var info = info(id)
	if info == null or _disabled.has(id):
		return ""
	if not can_disable(id):
		return "%s is part of AVaSt and can't be disabled." % info.title()
	var target := disabled_dir().path_join(id)
	_remove_tree(target)
	var error := _move_tree(info.dir, target)
	if not error.is_empty():
		_core.warn("library: disabling %s failed: %s" % [id, error])
		return error
	_core.info("library: disabled %s, moved to %s" % [id, target])
	info.dir = target
	_enabled.erase(id)
	_disabled[id] = info
	_switched(id, true)
	return ""

func enable(id: String) -> String:
	var info = _disabled.get(id)
	if info == null:
		return ""
	var target := mods_dir().path_join(id)
	if DirAccess.dir_exists_absolute(target) and not _walk(target, "").is_empty():
		return "The mods folder already has a '%s' folder." % id
	var error := _move_tree(info.dir, target)
	if not error.is_empty():
		_core.warn("library: enabling %s failed: %s" % [id, error])
		return error
	_core.info("library: enabled %s, moved back to %s" % [id, target])
	info.dir = target
	_disabled.erase(id)
	if not _core.mods.has(id):
		_enabled[id] = info
	_switched(id, false)
	return ""

func _switched(id: String, disabled: bool) -> void:
	var loaded: bool = _core.mods.has(id)
	if loaded == not disabled:
		pending.erase(id)
	else:
		pending[id] = disabled

func _scan() -> void:
	if not DirAccess.dir_exists_absolute(disabled_dir()):
		return
	for folder in DirAccess.get_directories_at(disabled_dir()):
		var info = _read(disabled_dir().path_join(folder), folder)
		if info != null:
			_disabled[info.id] = info

func installed_now(id: String) -> void:
	if _core.mods.has(id) or _disabled.has(id):
		return
	var info = _read(mods_dir().path_join(id), id)
	if info != null:
		_enabled[id] = info

static func _read(dir: String, folder: String):
	var manifest := Toml.parse(FileAccess.get_file_as_string(dir.path_join("gdpatch_mod.toml")))
	if manifest.is_empty():
		return null
	var info := ModInfo.new()
	info.id = str(manifest.get("id", folder))
	info.dir = dir
	info.manifest = manifest
	var meta: Dictionary = manifest.get("meta", {}) if manifest.get("meta") is Dictionary else {}
	info.name = str(meta.get("name", info.id))
	info.version = str(meta.get("version", ""))
	info.description = str(meta.get("description", ""))
	info.website = str(meta.get("website", ""))
	info.authors.assign(Array(meta.get("authors", []) if meta.get("authors") is Array else []).map(func(a: Variant) -> String: return str(a)))
	var avast: Dictionary = manifest.get("avast", {}) if manifest.get("avast") is Dictionary else {}
	info.links = avast.get("links", {}) if avast.get("links") is Dictionary else {}
	info.dependencies.assign(Array(avast.get("dependencies", []) if avast.get("dependencies") is Array else []).map(func(dep: Variant) -> String: return str(dep)))
	return info

static func _move_tree(from: String, to: String) -> String:
	var moved: Array[String] = []
	for rel in _walk(from, ""):
		DirAccess.make_dir_recursive_absolute(to.path_join(rel).get_base_dir())
		if DirAccess.rename_absolute(from.path_join(rel), to.path_join(rel)) != OK:
			for done in moved:
				DirAccess.rename_absolute(to.path_join(done), from.path_join(done))
			return "Couldn't move %s. Close other programs using the mod's files and try again." % rel
		moved.append(rel)
	_remove_tree(from)
	return ""

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
