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
# AVaSt Core itself. start menu entry, the AVaSt window, mod updates, crash reports, debug tools.
# most of the real work lives in the other files, this one just wires everything together
# and handles --avast-mod=<id> when steam starts the game from the website.

extends "res://avast/api/mod.gd"

const Reporter := preload("res://gdpatch/mods/avast_core/crash/reporter.gd")
const Updater := preload("res://gdpatch/mods/avast_core/updater.gd")
const Store := preload("res://gdpatch/mods/avast_core/store.gd")
const Library := preload("res://gdpatch/mods/avast_core/library.gd")
const Manager := preload("res://gdpatch/mods/avast_core/ui/manager.gd")
const CrashDialog := preload("res://gdpatch/mods/avast_core/ui/crash_dialog.gd")
const DebugPanel := preload("res://gdpatch/mods/avast_core/ui/debug_panel.gd")
const Thanks := preload("res://gdpatch/mods/avast_core/ui/thanks.gd")
const StatsOverlay := preload("res://gdpatch/mods/avast_core/ui/stats_overlay.gd")
const Link := preload("res://gdpatch/mods/avast_core/link.gd")
const Demo := preload("res://gdpatch/mods/avast_core/demo.gd")
const Gamepad := preload("res://gdpatch/mods/avast_core/gamepad.gd")
const Overlay := preload("res://gdpatch/mods/avast_core/ui/overlay.gd")

const _QUESTION_ICON := "res://assets/icons/info24.png"

var reporter: Reporter
var updater: Updater
var store: Store
var library: Library
var link: Link

var _manager
var _manager_view
var _debug
var _thanks
var _crash
var _stats
var _ignored := {}
var _desktop_seen := false
var _pending_mod := ""

func _ready() -> void:
	Demo.check(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	reporter = Reporter.new(self)
	reporter.start()
	reporter.capture.on_error = _on_error
	add_child(Gamepad.new())
	get_viewport().size_changed.connect(_fit_manager)
	var game_settings: Node = Game.autoload("Settings")
	if game_settings != null and game_settings.has_signal("settings_changed"):
		game_settings.settings_changed.connect(func() -> void: _fit_manager.call_deferred())
	updater = Updater.new()
	updater.name = "Updater"
	add_child(updater)
	updater.setup(self, reporter.dir)
	store = Store.new()
	store.name = "Store"
	add_child(store)
	store.setup(self)
	library = Library.new(self)
	link = Link.new()
	link.name = "Link"
	add_child(link)
	link.setup(self)
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--avast-mod=") and RegEx.create_from_string("^[a-z0-9_]{2,40}$").search(arg.trim_prefix("--avast-mod=")):
			_pending_mod = arg.trim_prefix("--avast-mod=")
	updater.checked.connect(_update_alert)
	updater.status_changed.connect(_update_alert)

	desktop.add_start_item(StartItem.new("avast", "AVaSt").icon("assets/icon.png").pinned().on_open(open_manager))
	events.on(Events.MAIN_MENU, _on_desktop)
	if config("debug", "stats_overlay", false):
		set_stats_overlay(true)

func _exit_tree() -> void:
	reporter.stop()

func open_manager() -> void:
	if not is_instance_valid(_manager):
		_manager_view = Manager.new(self)
		_manager_view.add_to_group(&"avast_ui")
		_manager = windows.open(_manager_view, "AVaSt", Manager.SIZE, Callable(), 0)
		_fit_manager.call_deferred()

func _fit_manager() -> void:
	if not is_instance_valid(_manager) or _manager.get_child_count() == 0:
		return
	var window: Control = _manager.get_child(0)
	var size: Vector2 = window.size if window.size != Vector2.ZERO else Manager.SIZE
	window.pivot_offset = size / 2
	window.scale = Vector2.ONE * Overlay.screen_fit(size, Vector2(16, 46))

func can_show_mods() -> bool:
	return Game.main_menu() != null

func show_mod(id: String) -> bool:
	if not can_show_mods():
		return false
	if not _desktop_seen:
		_pending_mod = id
		return true
	open_manager()
	if is_instance_valid(_manager_view):
		_manager_view.show_mod(id)
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_request_attention()
	return true

func restart_game() -> void:
	info("restarting the game to apply mod changes")
	StatTracker.flush()
	SaveManager.save_profile()
	var args := OS.get_cmdline_args()
	if not OS.get_cmdline_user_args().is_empty():
		args.append("--")
		args.append_array(OS.get_cmdline_user_args())
	OS.unset_environment("GDPATCH_INIT")
	OS.set_restart_on_exit(true, args)
	get_tree().quit()

func open_link(url: String) -> void:
	var domain := link_domain(url)
	var lower := url.strip_edges().to_lower()
	if domain.is_empty() or not (lower.begins_with("https://") or lower.begins_with("http://") or lower.begins_with("mailto:")):
		warn("link: refused %s, only web and mailto links open" % url)
		return
	var trusted: Array = config("links", "trusted", [])
	if trusted.any(func(d: Variant) -> bool: return domain == str(d) or domain.ends_with("." + str(d))):
		info("link: opening %s (trusted)" % url)
		OS.shell_open(url)
		return
	info("link: asking before opening %s" % url)
	var trust := {"on": false}
	var holder := {}
	var question := TextureRect.new()
	question.texture = load(_QUESTION_ICON)
	question.custom_minimum_size = Vector2(28, 28)
	question.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	question.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 4)
	var ask := Label.new()
	ask.text = "This link opens in your web browser. Do you want to go there?"
	ask.theme_type_variation = &"ThemeLabel"
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(ask)
	var address := Label.new()
	address.text = url
	address.theme_type_variation = &"GroupTitle"
	address.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	texts.add_child(address)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var answer := func(go: bool) -> void:
		windows.close(holder.window)
		if not go:
			info("link: cancelled %s" % url)
			return
		if trust.on:
			var list: Array = config("links", "trusted", []).duplicate()
			if not domain in list:
				list.append(domain)
			set_config("links", "trusted", list)
			info("link: now trusting %s" % domain)
		info("link: opening %s" % url)
		OS.shell_open(url)
	holder.window = windows.form("Open link", [
		Component.row([Component.custom(question), Component.custom(texts)]),
		Component.checkbox("Always trust %s" % domain, false, func(on: bool) -> void: trust.on = on),
		Component.separator(),
		Component.row([Component.custom(spacer), Component.button("Open", answer.bind(true)), Component.button("Cancel", answer.bind(false))]),
	], Vector2(340, 112))

static func link_domain(url: String) -> String:
	var rest := url.strip_edges()
	if rest.begins_with("mailto:"):
		return rest.get_slice("@", 1).get_slice("?", 0).to_lower()
	if not rest.contains("://"):
		return ""
	rest = rest.get_slice("://", 1)
	for stop in ["/", "?", "#", "\\"]:
		rest = rest.get_slice(stop, 0)
	rest = rest.get_slice("@", rest.count("@"))
	return rest.get_slice(":", 0).to_lower().trim_prefix("www.")

func open_thanks() -> void:
	if not is_instance_valid(_thanks):
		_thanks = Thanks.new(self)
		add_child(_thanks)

func open_debug() -> void:
	if not is_instance_valid(_debug):
		_debug = DebugPanel.new(self)
		add_child(_debug)

func stats_overlay_visible() -> bool:
	return is_instance_valid(_stats)

func set_stats_overlay(on: bool) -> void:
	if on and not is_instance_valid(_stats):
		_stats = StatsOverlay.new(self)
		add_child(_stats)
	elif not on and is_instance_valid(_stats):
		_stats.queue_free()
	set_config("debug", "stats_overlay", on if on else null)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		get_viewport().set_input_as_handled()
		if is_instance_valid(_debug):
			_debug.close()
		else:
			open_debug()

func _on_desktop(_menu: Node) -> void:
	if _desktop_seen:
		return
	_desktop_seen = true
	var menu := Game.main_menu()
	if menu != null and menu.boot_tween != null and menu.boot_tween.is_running():
		await menu.boot_tween.finished
	await get_tree().create_timer(1.0).timeout
	if not reporter.previous_crash.is_empty():
		_show_crash({})
	if not _pending_mod.is_empty():
		show_mod(_pending_mod)
		_pending_mod = ""
	var failed: Array = mods.list().filter(func(info) -> bool: return not info.is_loaded())
	if not failed.is_empty():
		ui.toast("%d mod%s failed to load" % [failed.size(), "" if failed.size() == 1 else "s"],
			", ".join(failed.map(func(info) -> String: return info.title())) + ". Open AVaSt for details.")
	if config("updates", "check", true):
		await updater.check()
		_after_check()

func _update_alert(_id: String = "") -> void:
	desktop.show_start_alert("avast", not updater.available.is_empty())

func _after_check() -> void:
	var count := updater.available.size()
	if count == 0:
		return
	if config("updates", "auto_install", false):
		var done: int = await updater.install_all()
		if done > 0:
			ui.toast("AVaSt updated %d mod%s" % [done, "" if done == 1 else "s"])
	else:
		ui.toast("%d update%s available" % [count, "" if count == 1 else "s"], "Open AVaSt from the start menu to install.")

func _on_error(record: Dictionary) -> void:
	var file := str(record.get("file", ""))
	if _ignored.has(file) or _ignored.has("%s:%s" % [file, record.get("line")]) or not config("debug", "error_popups", true):
		return
	_ignored["%s:%s" % [file, record.get("line")]] = true
	if not is_instance_valid(_crash):
		_show_crash(record)

func _show_crash(record: Dictionary) -> void:
	_crash = CrashDialog.new(reporter, record)
	_crash.on_ignore = func(r: Dictionary) -> void: _ignored[str(r.get("file", ""))] = true
	add_child(_crash)
