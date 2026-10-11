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
# a mods settings. the [config.<section>.<option>] entries from its gdpatch_mod.toml and the
# values in GDPatch/configs/<id>.toml
#
# mods the game loaded go through GDPatch, it writes the file and answers the mods own config()
# calls with the new value right away. mods it didnt load (off at start, or installed this
# session) get their file read and written here and gdpatch picks it up when it loads them.

extends RefCounted

const Toml := preload("res://avast/api/lib/toml.gd")
const Game := preload("res://avast/api/lib/game.gd")

static func sections(info) -> Array:
	var config: Variant = info.manifest.get("config", {}) if info != null else {}
	var out: Array = []
	if not config is Dictionary:
		return out
	for section_id in config:
		var options: Variant = config[section_id]
		if not options is Dictionary:
			continue
		var meta: Variant = options.get("meta", {})
		var section := {"id": str(section_id), "description": str(meta.get("description", "")) if meta is Dictionary else "", "options": []}
		for option_id in options:
			var option: Variant = options[option_id]
			if option_id == "meta" or not option is Dictionary or option.get("hidden", false) and option.get("widget") != "button":
				continue
			var default: Variant = option.get("default")
			section.options.append({
				"section": str(section_id), "id": str(option_id),
				"name": str(option.get("name", str(option_id).capitalize())), "description": str(option.get("description", "")),
				"type": str(option.get("type", _type_of(default))), "default": default,
				"choices": option.get("choices", []) if option.get("choices") is Array else [],
				"widget": str(option.get("widget", "")),
				"min": option.get("min"), "max": option.get("max"), "step": option.get("step"),
			})
		if not section.options.is_empty():
			out.append(section)
	return out

static func value(core: Node, id: String, option: Dictionary) -> Variant:
	var current: Variant = null
	if core.mods.has(id):
		current = Game.gdpatch().get_config_option(id, option.section, option.id)
	else:
		var section: Variant = _read(core, id).get(option.section)
		current = section.get(option.id) if section is Dictionary else null
	if current == null:
		return option.default
	if current is float and option.default is int and current == floorf(current):
		return int(current)
	return current

static func is_set(core: Node, id: String, option: Dictionary) -> bool:
	return not same(value(core, id, option), option.default)

static func describe(item: Variant) -> String:
	return _literal(_whole(item))

static func _whole(item: Variant) -> Variant:
	if item is float and item == floorf(item) and absf(item) < 1e15:
		return int(item)
	if item is Array:
		return item.map(func(part: Variant) -> Variant: return _whole(part))
	if item is Dictionary:
		var out := {}
		for key in item:
			out[key] = _whole(item[key])
		return out
	return item

static func set_value(core: Node, id: String, option: Dictionary, new_value: Variant) -> void:
	if core.mods.has(id):
		Game.gdpatch().set_config_option(id, option.section, option.id, new_value)
		return
	var saved := _read(core, id)
	var section: Dictionary = saved.get(option.section, {}) if saved.get(option.section) is Dictionary else {}
	if new_value == null:
		section.erase(option.id)
	else:
		section[option.id] = new_value
	saved[option.section] = section
	var path: String = core.library.settings_file(id)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(_to_toml(saved))
		file.close()

static func same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not same(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not same(a[key], b[key]):
				return false
		return true
	return typeof(a) == typeof(b) and a == b

static func _read(core: Node, id: String) -> Dictionary:
	var path: String = core.library.settings_file(id)
	return Toml.parse(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}

static func _type_of(default: Variant) -> String:
	match typeof(default):
		TYPE_BOOL:
			return "boolean"
		TYPE_INT, TYPE_FLOAT:
			return "number"
		TYPE_ARRAY:
			return "array"
		TYPE_DICTIONARY:
			return "table"
	return "string"

static func _to_toml(data: Dictionary) -> String:
	var lines: Array[String] = []
	for section in data:
		if not data[section] is Dictionary or data[section].is_empty():
			continue
		lines.append("[%s]" % _key(str(section)))
		for key in data[section]:
			lines.append("%s = %s" % [_key(str(key)), _literal(data[section][key])])
		lines.append("")
	return "\n".join(lines)

static func _key(key: String) -> String:
	var bare := RegEx.create_from_string("^[A-Za-z0-9_-]+$")
	return key if bare.search(key) != null else JSON.stringify(key)

static func _literal(item: Variant) -> String:
	match typeof(item):
		TYPE_BOOL:
			return "true" if item else "false"
		TYPE_INT:
			return str(item)
		TYPE_FLOAT:
			var text := str(item)
			return text if text.contains(".") or text.contains("e") or text.contains("n") else text + ".0"
		TYPE_ARRAY:
			return "[%s]" % ", ".join(Array(item).map(func(part: Variant) -> String: return _literal(part)))
		TYPE_DICTIONARY:
			var pairs: Array[String] = []
			for key in item:
				pairs.append("%s = %s" % [_key(str(key)), _literal(item[key])])
			return "{ %s }" % ", ".join(pairs)
	return JSON.stringify(str(item))
