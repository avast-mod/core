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
# the AVaSt window. opens from the start menu like the games own windows, looks like an old
# download manager: the browser menu bar, toolbar (Installed, Featured, Discover), mod list on the
# left with search and pages of 25, the selected mod on the right and a status bar.
#
# mod page is icon, name, author, category chips and links over the faded banner, then the
# install/update bar with downloads, date, size, then Readme and Changelog tabs.
# installed tab: checkbox turns a mod on/off, yellow bar shows waiting updates.
# biggest file in core, sorry

extends VBoxContainer

const Markdown := preload("res://gdpatch/mods/avast_core/markdown.gd")
const Palette := preload("res://avast/api/ui/palette.gd")
const Marquee := preload("res://avast/api/ui/progress_bar.gd")
const Library := preload("res://gdpatch/mods/avast_core/library.gd")
const Icons := preload("res://gdpatch/mods/avast_core/ui/icons.gd")
const Settings := preload("res://gdpatch/mods/avast_core/settings.gd")
const Form := preload("res://avast/api/ui/form.gd")
const Fields := preload("res://avast/api/ui/fields.gd")
const ModSettings := preload("res://avast/api/settings.gd")

const SIZE := Vector2(680, 420)
const _LIST_WIDTH := 220
const _PAGE_WIDTH := 400.0
const _PER_PAGE := 25
const _CHROME := "res://scenes/ui/Window/browser_chrome.tscn"
const _ROW := "res://scenes/ui/folder_tree_row.tscn"
const _BUTTON := "res://scenes/ui/standard_button/standard_button.tscn"
const _MOD_ICON := "res://assets/icons/beanz32.png"
const _VIEWS := [
	["installed", "Installed", "res://assets/icons/levelup32.png"],
	["featured", "Featured", "assets/icons/star.png"],
	["discover", "Discover", "res://scenes/ability/search_ability/searchtrial-export24.png"],
]
const _RELOAD_ICON := "res://assets/icons/refreshrate-export 24.png"
const _UPDATE_ICON := "res://assets/icons/levelup32.png"
const _WARNING_ICON := "res://scenes/game_object/enemies/wizard_enemy/critical-24.png"
const _OFFLINE_ICON := "res://scenes/game_object/enemies/basic_enemy/errortrial-export 24.png"
const _INFO_ICON := "res://assets/icons/info24.png"
const _DOWNLOADS_ICON := "res://assets/icons/vapidshare24.png"
const _HOURGLASS := "res://assets/ui/hourglass-Sheet.png"
const _SORTS := [["popular", "Popular"], ["new", "Newest"], ["name", "A-Z"]]
const _HEADING_FONT := "res://inter-600.tres"
const _FOLDER_ICON := "res://scenes/game_object/folder/empty folder-dither.png"
const _RECYCLE_ICON := "res://scenes/game_object/bosses/recycle_bin_boss/recycler-32-dithered.png"
const _ALERT := "res://scenes/ui/new_alert.tscn"
const _WEB_ICON := "res://assets/icons/internetcruiser24.png"
const _LINK_ICONS := {
	"website": "res://assets/icons/internetcruiser24.png",
	"discord": "res://scenes/game_object/folder/discord32.png",
	"source": "res://assets/icons/copy icon-export 24.png",
	"docs": "res://assets/icons/info24.png",
	"help": "res://assets/icons/info24.png",
	"wiki": "res://assets/icons/info24.png",
}
const _GREEN := Color(0.22, 0.56, 0.18)
const _GOLD := Color(0.8, 0.58, 0.05)
const _RED := Color(0.7, 0.19, 0.15)
const _GREY := Color(0.42, 0.45, 0.48)
const _UNINSTALL := Color(0.5, 0.26, 0.22)
const _TAB_TOP := Color(0.98, 0.76, 0.24)
const _MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var _core: Node
var _pal := {}
var _view := "installed"
var _pick := {"installed": "", "featured": "", "discover": ""}
var _page := "readme"
var _category := ""
var _sort := 0
var _discover_total := 0
var _remote := {}
var _remote_lists := {"featured": [], "discover": []}
var _remote_error := {"featured": "", "discover": ""}
var _loaded := {"featured": false, "discover": false}
var _details := {}
var _list_page := {"installed": 0, "featured": 0, "discover": 0}
var _last_click := {"id": "", "at": 0}
var _list_token := 0
var _page_token := 0
var _search_timer: SceneTreeTimer
var _page_list: Array = []
var _rows := {}

var _tools := {}
var _restart_tool: Button
var _updates_alert: Control
var _tabs: HBoxContainer
var _search: LineEdit
var _filter_row: HBoxContainer
var _category_button: Button
var _sort_button: Button
var _update_bar: PanelContainer
var _list_frame: PanelContainer
var _list_scroll: ScrollContainer
var _list: VBoxContainer
var _list_overlay: CenterContainer
var _pager: HBoxContainer
var _dropdown: PanelContainer
var _header: PanelContainer
var _actions: HBoxContainer
var _info: VBoxContainer
var _page_frame: PanelContainer
var _page_scroll: ScrollContainer
var _page_body: MarginContainer
var _update_box: PanelContainer
var _update_top: HBoxContainer
var _status: Label
var _status_marquee: Control
var _server_label: Label
var _styled: Array = []

func _init(core: Node) -> void:
	_core = core
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)

func _ready() -> void:
	_pal = Palette.current()
	add_child(_chrome())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	add_child(body)
	body.add_child(_left_pane())
	var divider := Panel.new()
	divider.custom_minimum_size.x = 2
	divider.theme_type_variation = &"DivVertical"
	body.add_child(divider)
	body.add_child(_right_pane())
	add_child(_status_bar())
	_dropdown = _make_dropdown()
	add_child(_dropdown)
	_restyle()

	_core.updater.checked.connect(_refresh)
	_core.updater.status_changed.connect(_on_mod_status)
	_core.store.status_changed.connect(_on_store_status)
	AppearanceManager.appearance_changed.connect(_on_appearance_changed)
	_refresh()
	_fetch_stats()

func _exit_tree() -> void:
	_core.updater.checked.disconnect(_refresh)
	_core.updater.status_changed.disconnect(_on_mod_status)
	_core.store.status_changed.disconnect(_on_store_status)
	AppearanceManager.appearance_changed.disconnect(_on_appearance_changed)

func _chrome() -> Control:
	var chrome: Control = load(_CHROME).instantiate()
	chrome.set_script(null)
	chrome.get_node("Rows/MenuPad/MenuRow/Favorites").text = "Tools"
	chrome.get_node("Rows/AddressPad").hide()
	var toolbar: HBoxContainer = chrome.get_node("Rows/ToolbarPad/ToolbarRow")
	for child in toolbar.get_children():
		toolbar.remove_child(child)
		child.free()
	toolbar.add_theme_constant_override("separation", 2)
	for view in _VIEWS:
		_tools[view[0]] = _tool(view[1], view[2], _open_view.bind(view[0]))
		toolbar.add_child(_tools[view[0]])
	_updates_alert = _update_alert()
	_tools.installed.get_node("Row/Picture").add_child(_updates_alert)
	var divider := Panel.new()
	divider.custom_minimum_size = Vector2(2, 0)
	divider.theme_type_variation = &"DivVertical"
	toolbar.add_child(divider)
	_tools["reload"] = _tool("Reload", _RELOAD_ICON, _reload)
	toolbar.add_child(_tools["reload"])
	_tools["thanks"] = _tool("Thanks!", "res://assets/icons/healthcheckplus.png", _core.open_thanks)
	toolbar.add_child(_tools["thanks"])
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	_restart_tool = _restart_button()
	toolbar.add_child(_restart_tool)
	return chrome

func _left_pane() -> Control:
	var pad := MarginContainer.new()
	pad.custom_minimum_size.x = _LIST_WIDTH
	_margins(pad, 6, 6)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	pad.add_child(column)
	_search = LineEdit.new()
	_search.placeholder_text = "Search for mods..."
	_search.text_changed.connect(_on_search_changed)
	_search.text_submitted.connect(func(_text: String) -> void: _search.release_focus())
	Fields.hold_keys_while_typing(_search)
	column.add_child(_search)
	_filter_row = HBoxContainer.new()
	_filter_row.add_theme_constant_override("separation", 4)
	_category_button = _button("All categories", _toggle_dropdown)
	_category_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_category_button.clip_text = true
	_category_button.add_theme_constant_override("icon_max_width", 12)
	var arrow := TextureRect.new()
	arrow.name = "Arrow"
	arrow.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	arrow.offset_left = -12
	arrow.offset_right = -5
	arrow.offset_top = -2
	arrow.offset_bottom = 2
	arrow.texture = Icons.arrow("down")
	arrow.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	arrow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_category_button.add_child(arrow)
	_filter_row.add_child(_category_button)
	_sort_button = _button(_SORTS[0][1], _cycle_sort)
	_sort_button.custom_minimum_size.x = 56
	_filter_row.add_child(_sort_button)
	column.add_child(_filter_row)
	_update_bar = _make_update_bar()
	column.add_child(_update_bar)
	_list_frame = PanelContainer.new()
	_list_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_list_frame)
	_list_scroll = _scroller()
	_list_frame.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	_list_scroll.add_child(_list)
	_list_overlay = _overlay()
	_list_frame.add_child(_list_overlay)
	_pager = HBoxContainer.new()
	_pager.alignment = BoxContainer.ALIGNMENT_CENTER
	_pager.add_theme_constant_override("separation", 1)
	column.add_child(_pager)
	return pad

func _right_pane() -> Control:
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_margins(pad, 6, 6)
	_page_frame = PanelContainer.new()
	pad.add_child(_page_frame)
	_page_scroll = _scroller()
	_page_frame.add_child(_page_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	_page_scroll.add_child(column)
	_header = PanelContainer.new()
	_header.clip_contents = true
	column.add_child(_header)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	column.add_child(_padded(_actions))
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 4)
	column.add_child(_padded(_info))
	_update_box = PanelContainer.new()
	column.add_child(_padded(_update_box))
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 0)
	column.add_child(_tabs)
	_page_body = MarginContainer.new()
	_page_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_body.add_theme_constant_override("margin_left", 12)
	_page_body.add_theme_constant_override("margin_right", 14)
	_page_body.add_theme_constant_override("margin_top", 0)
	_page_body.add_theme_constant_override("margin_bottom", 12)
	column.add_child(_page_body)
	return pad

func _padded(part: Control) -> MarginContainer:
	var pad := MarginContainer.new()
	_margins(pad, 10, 0)
	pad.add_child(part)
	return pad

func _tidy_page() -> void:
	_header.visible = _header.get_child_count() > 0
	_actions.get_parent().visible = _actions.get_child_count() > 0
	_info.get_parent().visible = _info.get_children().any(func(child: Control) -> bool: return child.visible)
	_update_box.get_parent().visible = _update_box.get_child_count() > 0

func _status_bar() -> Control:
	var bar := PanelContainer.new()
	bar.set_meta(&"style", "status")
	_styled.append(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	_status = _label("", false)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	row.add_child(_status)
	_status_marquee = Marquee.new(60, 12)
	_status_marquee.hide()
	row.add_child(_status_marquee)
	var divider := Panel.new()
	divider.custom_minimum_size = Vector2(2, 0)
	divider.theme_type_variation = &"DivVertical"
	row.add_child(divider)
	_server_label = _label("", false)
	row.add_child(_server_label)
	return bar

func _make_dropdown() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.top_level = true
	panel.z_index = 20
	panel.visible = false
	panel.set_meta(&"style", "field")
	_styled.append(panel)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 0)
	panel.add_child(grid)
	return panel

func _overlay() -> CenterContainer:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.visible = false
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	center.add_child(column)
	return center

func _scroller() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.get_v_scroll_bar().value_changed.connect(func(_value: float) -> void: _clip.call_deferred(scroll))
	scroll.resized.connect(_clip.bind(scroll))
	return scroll

func _tool(text: String, icon_path: String, on_click: Callable) -> Button:
	var tool := _button("")
	var row := HBoxContainer.new()
	row.name = "Row"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)
	var picture := TextureRect.new()
	picture.name = "Picture"
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picture.texture = _texture(icon_path)
	picture.custom_minimum_size = Vector2(24, 24)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(picture)
	var caption := Label.new()
	caption.text = text
	caption.theme_type_variation = &"ThemeLabel"
	row.add_child(caption)
	tool.add_child(row)
	var width := caption.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, caption.get_theme_font_size("font_size")).x
	tool.custom_minimum_size = Vector2(width + 46, 32)
	tool.clicked.connect(on_click)
	return tool

func _update_alert() -> Control:
	var alert: Control = load(_ALERT).instantiate()
	alert.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	alert.offset_left = -12
	alert.offset_top = -12
	alert.offset_right = 0
	alert.offset_bottom = 0
	alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert.hide()
	return alert

func _texture(path: String) -> Texture2D:
	if path.begins_with("res://"):
		return load(path)
	var resource: Resource = _core.asset(path)
	return resource if resource is Texture2D else null

func _restart_button() -> Button:
	var button := _button("Restart now", _core.restart_game)
	button.icon = Icons.texture("power_big")
	button.add_theme_constant_override("h_separation", 8)
	button.add_theme_font_override("font", load(_HEADING_FONT))
	button.add_theme_font_size_override("font_size", 13)
	button.custom_minimum_size = Vector2(118, 32)
	button.tooltip = "Saves your profile and starts the game again, so mod changes apply."
	var styles := {
		"normal": _colored(_RED), "hover": _colored(_RED.lightened(0.15)), "focus": _colored(_RED.lightened(0.15)),
		"pressed": _colored(_RED.darkened(0.15)), "hover_pressed": _colored(_RED.darkened(0.15)), "disabled": _colored(_RED),
	}
	for state in styles:
		styles[state].content_margin_left = 10
		styles[state].content_margin_right = 12
		button.add_theme_stylebox_override(state, styles[state])
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(key, Color.WHITE)
	button.add_theme_color_override("font_outline_color", _RED.darkened(0.6))
	button.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return button

func _style_flat(button: Button, active: bool) -> void:
	var picked := Palette.box(_pal.picked, _pal.border)
	var hover_picked := Palette.box(_pal.picked.lightened(0.1), _pal.border)
	for state in ["normal", "pressed", "hover", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, picked if active else StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", hover_picked if active else Palette.box(_pal.hover, _pal.border))

func _button(text: String, on_click: Callable = Callable()) -> Button:
	var button: Button = load(_BUTTON).instantiate()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	button.custom_minimum_size = Vector2(52, 22)
	if on_click.is_valid():
		button.clicked.connect(on_click)
	return button

func _small_button(text: String, on_click: Callable) -> Button:
	var button := _button(text, on_click)
	button.custom_minimum_size = Vector2(20, 18)
	return button

func _label(text: String, wrap: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"ThemeLabel"
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _icon(texture: Texture2D, edge: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(edge, edge)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _margins(container: MarginContainer, horizontal: int, vertical: int) -> void:
	for side in ["left", "right"]:
		container.add_theme_constant_override("margin_" + side, horizontal)
	for side in ["top", "bottom"]:
		container.add_theme_constant_override("margin_" + side, vertical)

func _restyle() -> void:
	_pal = Palette.current()
	var field := Palette.box(_pal.field, _pal.border)
	_list_frame.add_theme_stylebox_override("panel", field)
	_page_frame.add_theme_stylebox_override("panel", field)
	var search := Palette.box(_pal.field, _pal.border, 1, 3)
	search.content_margin_left = 4
	for state in ["normal", "focus", "read_only"]:
		_search.add_theme_stylebox_override(state, search)
	_search.add_theme_color_override("font_color", _pal.text)
	_search.add_theme_color_override("font_placeholder_color", _pal.muted)
	_search.add_theme_color_override("caret_color", _pal.text)
	for node in _styled:
		if node.get_meta(&"style") == "field":
			node.add_theme_stylebox_override("panel", Palette.box(_pal.field, _pal.border))
		else:
			var line := StyleBoxFlat.new()
			line.bg_color = Color(0, 0, 0, 0)
			line.border_color = _pal.border
			line.border_width_top = 1
			line.content_margin_left = 4
			line.content_margin_right = 4
			line.content_margin_top = 1
			line.content_margin_bottom = 1
			node.add_theme_stylebox_override("panel", line)
	var theme: Resource = AppearanceManager.active_theme
	_category_button.get_node("Arrow").modulate = theme.button_text_color if theme != null else _pal.text
	_refresh_toolbar()

func _clip(scroll: ScrollContainer) -> void:
	if not is_instance_valid(scroll) or not scroll.is_inside_tree():
		return
	var covered := _dropdown.get_global_rect() if _dropdown.visible else Rect2()
	for button in scroll.find_children("*", "StandardButton", true, false):
		var shape: CollisionShape2D = button.collision_shape_2d
		if shape != null:
			shape.disabled = not Fields.shown(button) or (_dropdown.visible and covered.intersects(button.get_global_rect()))

func _set_title(text: String) -> void:
	var node := get_parent()
	while node != null:
		if node.has_node("MarginContainer2/Label"):
			node.get_node("MarginContainer2/Label").text = text
			return
		node = node.get_parent()

func _on_appearance_changed(_a = null, _b = null) -> void:
	_restyle()
	_refresh()

func _on_mod_status(_id: String) -> void:
	_refresh()

func _on_store_status() -> void:
	_show_status()
	for id in _core.store.progress:
		var row = _rows.get(id)
		if is_instance_valid(row):
			_row_progress(row, _core.store.progress[id])
	if _view != "installed":
		_show_progress_only()
	elif is_instance_valid(_update_top) and _update_top.has_node("Progress"):
		var old: Control = _update_top.get_node("Progress")
		var entry: Dictionary = _core.store.progress.get(_pick.installed, {})
		if not entry.is_empty():
			var fresh := _download_progress(entry, 170)
			_update_top.add_child(fresh)
			_update_top.move_child(fresh, old.get_index())
			_update_top.remove_child(old)
			old.queue_free()
			fresh.name = "Progress"

func _open_view(view: String) -> void:
	_close_dropdown()
	if _view == view:
		return
	_view = view
	_page = "readme"
	_search.set_block_signals(true)
	_search.text = ""
	_search.set_block_signals(false)
	_category = ""
	_refresh()
	if view != "installed" and not _loaded[view]:
		_fetch(view)
	elif view == "discover":
		_fetch(view)

func show_mod(id: String) -> void:
	_open_view("discover")
	_category = ""
	_search.set_block_signals(true)
	_search.text = id
	_search.set_block_signals(false)
	_pick.discover = ""
	await _fetch("discover")
	if is_inside_tree() and _remote_lists.discover.any(func(m: Dictionary) -> bool: return m.id == id):
		_select(id)

func _select(id: String) -> void:
	_close_dropdown()
	var now := Time.get_ticks_msec()
	if _view != "installed" and _last_click.id == id and now - _last_click.at < 450:
		var mod: Dictionary = _remote.get(id, {})
		if not mod.is_empty() and _wants_install(mod) and _core.store.same_source(id) and not id in Library.REQUIRED \
				and _core.updater.status.get(id, "") != "downloading":
			_install_remote(mod)
	_last_click = {"id": id, "at": now}
	_pick[_view] = id
	_page = "readme"
	_refresh()

func _open_page(page: String) -> void:
	if _page == page:
		return
	_page = page
	_page_scroll.scroll_vertical = mini(_page_scroll.scroll_vertical, int(_tabs.position.y))
	_build_tabs(_page_list)
	if _view == "installed":
		var info = _core.library.info(_pick.installed)
		if info != null:
			_set_page(_installed_doc(info))
	elif _details.has(str(_pick[_view])):
		_render_remote(_details[str(_pick[_view])])

func _on_search_changed(_text: String) -> void:
	_list_page[_view] = 0
	if _view == "installed":
		_refresh_list()
		return
	if _view == "featured":
		_view = "discover"
		_refresh_toolbar()
	_search_timer = get_tree().create_timer(0.35)
	var timer := _search_timer
	await timer.timeout
	if timer == _search_timer and is_inside_tree():
		_fetch("discover")

func _cycle_sort() -> void:
	_sort = (_sort + 1) % _SORTS.size()
	_sort_button.text = _SORTS[_sort][1]
	_fetch("discover")

func _set_category(id: String) -> void:
	_close_dropdown()
	_category = id
	_list_page.installed = 0
	_list_page.discover = 0
	if _view == "installed":
		_refresh()
	else:
		if _view == "featured":
			_view = "discover"
		_refresh()
		_fetch("discover")

func _reload() -> void:
	_close_dropdown()
	_core.store.refresh()
	if _view == "installed":
		_core.mods.reload()
		_core.updater.check(true)
		_fetch_stats()
		_refresh()
	else:
		_details.clear()
		_fetch(_view)

func _toggle_dropdown() -> void:
	if _dropdown.visible:
		_close_dropdown()
		return
	var column: GridContainer = _dropdown.get_child(0)
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	var counts := {}
	if _view == "installed":
		for info in _core.library.all():
			for category in Library.categories(info):
				counts[category] = counts.get(category, 0) + 1
	column.add_child(_category_row("", "All categories", null, -1))
	for id in Library.CATEGORIES:
		column.add_child(_category_row(id, Library.category_name(id), Library.category_icon(id), counts.get(id, 0) if _view == "installed" else -1))
	for row in column.get_children():
		row.custom_minimum_size.x = 150
	_dropdown.size = Vector2.ZERO
	_dropdown.global_position = _category_button.global_position + Vector2(0, _category_button.size.y + 1)
	_dropdown.show()
	_clip(_list_scroll)
	_clip(_page_scroll)

func _category_row(id: String, text: String, icon: Texture2D, count: int) -> Button:
	var row := _row(icon, text, id == _category, _set_category.bind(id))
	if count >= 0:
		row.get_node("Row").add_child(_side_label(str(count), id == _category))
	return row

func _close_dropdown() -> void:
	if _dropdown != null and _dropdown.visible:
		_dropdown.hide()
		_clip(_list_scroll)
		_clip(_page_scroll)

func _refresh() -> void:
	if not is_inside_tree():
		return
	_set_title("%s - AVaSt" % _VIEWS.filter(func(v: Array) -> bool: return v[0] == _view)[0][1])
	_refresh_toolbar()
	_refresh_update_bar()
	_filter_row.visible = _view != "featured"
	_sort_button.visible = _view == "discover"
	_sort_button.text = _SORTS[_sort][1]
	_category_button.text = Library.category_name(_category) if not _category.is_empty() else "All categories"
	_category_button.icon = Library.category_icon(_category) if not _category.is_empty() else null
	_refresh_list()
	_show_selected()
	_show_status()

func _refresh_toolbar() -> void:
	for view in _tools:
		_style_flat(_tools[view], view == _view)
	var updates: int = _core.updater.available.size()
	_updates_alert.visible = updates > 0
	_restart_tool.visible = _core.updater.restart_needed or _core.library.restart_needed()

func _refresh_list() -> void:
	_clear(_list)
	_rows.clear()
	_list_overlay.hide()
	var items: Array = []
	if _view == "installed":
		items = _installed_matches()
		if (_pick.installed.is_empty() or _core.library.info(_pick.installed) == null) and not items.is_empty():
			_pick.installed = items[0].id
		if items.is_empty():
			_set_overlay(_list_overlay, "", "No installed mods match.", false)
	else:
		items = _remote_lists[_view]
		if not _remote_error[_view].is_empty():
			_set_overlay(_list_overlay, "offline" if _core.store.available() else "info", _remote_error[_view], true)
		elif not _loaded[_view]:
			_set_overlay(_list_overlay, "loading", "Connecting to the AVaSt server...", false)
		elif items.is_empty():
			_set_overlay(_list_overlay, "", "No mods found.", false)
		if _pick[_view].is_empty() and not items.is_empty():
			_pick[_view] = items[0].id
	var pages := maxi(1, ceili(items.size() / float(_PER_PAGE)))
	_list_page[_view] = clampi(_list_page[_view], 0, pages - 1)
	var first: int = _list_page[_view] * _PER_PAGE
	for item in items.slice(first, first + _PER_PAGE):
		_list.add_child(_installed_row(item) if _view == "installed" else _remote_row(item))
	_build_pager(pages)
	_clip.call_deferred(_list_scroll)

func _build_pager(pages: int) -> void:
	_clear(_pager)
	_pager.visible = pages > 1
	if pages <= 1:
		return
	var current: int = _list_page[_view]
	_pager.add_child(_page_button("<", current - 1, current > 0))
	var last := -1
	for page in range(pages):
		if page != 0 and page != pages - 1 and absi(page - current) > 1:
			continue
		if page - last > 1:
			_pager.add_child(_muted("..."))
		var button := _page_button(str(page + 1), page, true)
		if page == current:
			_style_flat(button, true)
		_pager.add_child(button)
		last = page
	_pager.add_child(_page_button(">", current + 1, current < pages - 1))

func _page_button(text: String, page: int, enabled: bool) -> Button:
	var button := _small_button(text, _go_to_page.bind(page))
	button.custom_minimum_size = Vector2(20, 20)
	button.disabled = not enabled
	return button

func _go_to_page(page: int) -> void:
	_list_page[_view] = page
	_refresh_list()
	_list_scroll.scroll_vertical = 0

func _installed_matches() -> Array:
	var query := _search.text.strip_edges().to_lower()
	return _core.library.all().filter(func(info) -> bool:
		if not _category.is_empty() and not _category in Library.categories(info):
			return false
		return query.is_empty() or info.title().to_lower().contains(query) or info.id.contains(query) \
			or info.authors_text().to_lower().contains(query))

func _row(icon: Texture2D, text: String, picked: bool, on_click: Callable) -> Button:
	var row: Button = load(_ROW).instantiate()
	var selected := Palette.box(_pal.select, _pal.select, 0, 0)
	selected.content_margin_left = 2
	selected.content_margin_right = 2
	var idle := StyleBoxEmpty.new()
	idle.content_margin_left = 2
	idle.content_margin_right = 2
	row.ready.connect(func() -> void:
		var shown: Texture2D = row.get_meta(&"icon") if row.has_meta(&"icon") else icon
		row.setup(0, -1, shown, text, picked, false, null, null, selected, idle, on_click)
		row.get_node("%Twist").hide()
		if not picked:
			var name_label: Label = row.get_node("%NameLabel")
			name_label.add_theme_color_override("font_color", row.get_meta(&"tint", _pal.text))
			name_label.add_theme_constant_override("outline_size", 0)
			name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		if row.has_meta(&"restart"):
			_restart_mark(row), CONNECT_ONE_SHOT)
	row.custom_minimum_size.y = 19
	row.get_node("%Icon").custom_minimum_size = Vector2(14, 14)
	row.get_node("Row").add_theme_constant_override("separation", 4)
	return row

func _restart_mark(row: Button) -> void:
	var name_label: Label = row.get_node("%NameLabel")
	var line: Control = name_label.get_parent()
	var mark := _icon(load(_RELOAD_ICON), 12)
	line.add_child(mark)
	line.move_child(mark, name_label.get_index() + 1)
	var spacer := _spacer()
	line.add_child(spacer)
	line.move_child(spacer, mark.get_index() + 1)
	name_label.size_flags_horizontal = Control.SIZE_FILL
	name_label.clip_text = true
	name_label.custom_minimum_size.x = 0
	var font := name_label.get_theme_font("font")
	var wanted := font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_label.get_theme_font_size("font_size")).x + 1
	var room: float = _list.size.x - line.get_combined_minimum_size().x - 6 if _list.size.x > 0 else 70.0
	name_label.custom_minimum_size.x = clampf(wanted, 0, maxf(room, 20))

func _row_progress(row: Button, entry: Dictionary) -> void:
	var fill: ColorRect = row.get_node_or_null("Fill")
	if fill == null:
		fill = ColorRect.new()
		fill.name = "Fill"
		fill.color = Color(0.3, 0.78, 0.25, 0.55)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.add_child(fill)
		row.move_child(fill, 0)
	var fraction: float = entry.get("fraction", 0.0)
	fill.anchor_right = fraction
	fill.offset_right = 0
	var side: Label = row.find_child("Side", true, false)
	if side != null:
		side.text = "%d%%" % int(fraction * 100) if int(entry.get("total", 0)) > 0 else "..."

func _needs_restart(id: String) -> bool:
	return _core.updater.changed.has(id) or _core.library.pending.has(id) or _core.library.is_removed(id)

func _side_label(text: String, picked: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"FuzzyType"
	label.add_theme_color_override("font_color", _pal.select_text if picked else _pal.muted)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_constant_override("shadow_outline_size", 0)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return label

func _checkbox(checked: bool, enabled: bool, on_click: Callable, tip: String) -> Control:
	if not enabled:
		var fixed := _icon(AppearanceManager.checkbox_texture(checked), 11)
		fixed.modulate.a = 0.5
		fixed.tooltip_text = tip
		fixed.mouse_filter = Control.MOUSE_FILTER_PASS
		return fixed
	var box := _button("", on_click)
	box.icon = AppearanceManager.checkbox_texture(checked)
	box.expand_icon = true
	box.custom_minimum_size = Vector2(13, 13)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.tooltip = tip
	for state in ["normal", "pressed", "hover", "hover_pressed", "focus", "disabled"]:
		box.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	return box

func _installed_row(info) -> Button:
	var picked: bool = info.id == _pick.installed
	var icon: Texture2D = info.icon()
	var row := _row(icon if icon != null else load(_MOD_ICON), info.title(), picked, _select.bind(info.id))
	_rows[info.id] = row
	if _needs_restart(info.id):
		row.set_meta(&"restart", true)
	var disabled: bool = _core.library.is_disabled(info.id)
	var removed: bool = _core.library.is_removed(info.id)
	if disabled or removed:
		row.get_node("%Icon").modulate.a = 0.4
		row.get_node("%NameLabel").modulate.a = 0.5
	var line: HBoxContainer = row.get_node("Row")
	if _core.updater.available.has(info.id):
		var update := _icon(load(_UPDATE_ICON), 11)
		update.tooltip_text = "Update to " + str(_core.updater.available[info.id].version)
		update.mouse_filter = Control.MOUSE_FILTER_PASS
		line.add_child(update)
	elif not _core.mods.problems(info.id).is_empty() and not disabled:
		line.add_child(_icon(load(_WARNING_ICON), 11))
	var side := _side_label("v" + info.version if not info.version.is_empty() else "", picked)
	side.name = "Side"
	line.add_child(side)
	if _core.store.progress.has(info.id):
		_row_progress(row, _core.store.progress[info.id])
	if removed:
		line.add_child(_icon(load(_RECYCLE_ICON), 13))
	else:
		line.add_child(_checkbox(not disabled, _core.library.can_disable(info.id), _toggle_mod.bind(info.id),
			("Turn off" if not disabled else "Turn on") if _core.library.can_disable(info.id) else "AVaSt needs this mod"))
	return row

func _remote_row(mod: Dictionary) -> Button:
	var picked: bool = mod.id == _pick[_view]
	var row := _row(load(_MOD_ICON), str(mod.name), picked, _select.bind(str(mod.id)))
	_rows[str(mod.id)] = row
	if _needs_restart(str(mod.id)):
		row.set_meta(&"restart", true)
	_core.store.texture(str(mod.get("icon", "")), func(texture: Texture2D) -> void:
		if not is_instance_valid(row) or texture == null:
			return
		row.set_meta(&"icon", texture)
		if row.is_node_ready():
			row.get_node("%Icon").texture = texture, row, 256)
	var line: HBoxContainer = row.get_node("Row")
	var installed = _core.library.info(str(mod.id))
	if installed != null and not _core.library.is_removed(str(mod.id)):
		_mark_row(row, _GREEN, "Installed", picked)
	elif mod.get("featured", false):
		_mark_row(row, _GOLD, "Featured", picked)
	var side := _side_label("v" + str(mod.get("version", "")), picked)
	side.name = "Side"
	line.add_child(side)
	if _core.store.progress.has(str(mod.id)):
		_row_progress(row, _core.store.progress[str(mod.id)])
	return row

func _mark_row(row: Button, color: Color, tip: String, picked: bool) -> void:
	row.set_meta(&"tint", Palette.readable(color, _pal).lightened(0.1 if _pal.dark else 0.0))
	row.tooltip = tip
	if picked:
		return
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color, 0.4 if _pal.dark else 0.32))
	gradient.set_color(1, Color(color, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 1
	var glow := TextureRect.new()
	glow.texture = texture
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.anchor_right = 0.75
	row.add_child(glow)
	row.move_child(glow, 0)

func _wants_install(mod: Dictionary) -> bool:
	var installed = _core.library.info(str(mod.id))
	if installed == null or _core.library.is_removed(str(mod.id)):
		return true
	return not _core.mods.version_at_least(installed.version, str(mod.get("version", "")))

func _show_status() -> void:
	var store: Node = _core.store
	var busy: bool = store.state == "loading" or _core.updater.checking
	var downloading: Array = store.progress.keys()
	_status_marquee.visible = busy or not downloading.is_empty()
	var batch: Dictionary = _core.updater.batch
	if not downloading.is_empty() and batch.is_empty():
		var first: String = downloading[0]
		var title: String = str(_remote.get(first, {}).get("name", first))
		_status.text = "Installing %s %d%%" % [title, int(store.progress[first].get("fraction", 0.0) * 100)] if downloading.size() == 1 else "Installing %d mods" % downloading.size()
	elif not batch.is_empty():
		var progress: Dictionary = _core.store.progress.get(batch.id, {})
		var name: String = _core.library.info(batch.id).title() if _core.library.info(batch.id) != null else batch.id
		_status.text = "Updating %d of %d: %s %d%%" % [batch.done + 1, batch.total, name, int(progress.get("fraction", 0.0) * 100)]
	elif busy:
		_status.text = "Checking for updates..." if _core.updater.checking and _view == "installed" else "Connecting to the AVaSt server..."
	elif _view == "installed":
		var all: Array = _core.library.all()
		var off := all.filter(func(i) -> bool: return _core.library.is_disabled(i.id)).size()
		_status.text = "%d mods installed" % all.size() + (", %d turned off" % off if off > 0 else "")
	elif not _remote_error[_view].is_empty():
		_status.text = _remote_error[_view]
	elif _view == "discover" and _loaded.discover:
		_status.text = "%s mod%s found" % [_count(_discover_total), "" if _discover_total == 1 else "s"]
	elif _loaded[_view]:
		_status.text = "%d featured mods" % _remote_lists.featured.size()
	else:
		_status.text = ""
	if not store.available():
		_set_server("Not set up", _pal.muted)
	elif store.state == "loading":
		_set_server("Connecting...", _pal.muted)
	elif store.state == "offline":
		_set_server("Offline", Palette.readable(Color(0.8, 0.2, 0.15), _pal))
	elif store.state == "ok":
		_set_server("Online", Palette.readable(Color(0.15, 0.55, 0.2), _pal))
	else:
		_set_server("Server", _pal.muted)

func _set_server(text: String, color: Color) -> void:
	_server_label.text = "● " + text
	_server_label.add_theme_color_override("font_color", color)
	_server_label.tooltip_text = _core.store.url()

func _set_overlay(overlay: CenterContainer, kind: String, text: String, retry: bool) -> void:
	var column: VBoxContainer = overlay.get_child(0)
	_clear(column)
	if kind == "loading":
		var marquee := Marquee.new(80)
		marquee.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(marquee)
	elif kind in ["offline", "info"]:
		var icon := _icon(load(_OFFLINE_ICON if kind == "offline" else _INFO_ICON), 24)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(icon)
	var label := _label(text)
	label.custom_minimum_size.x = 130
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", _pal.muted)
	column.add_child(label)
	if retry:
		var button := _button("Retry", func() -> void: _fetch(_view))
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(button)
	overlay.show()

func _show_selected() -> void:
	_page_scroll.scroll_vertical = 0
	if _view == "installed":
		_show_installed(_core.library.info(_pick.installed))
		return
	var mod: Dictionary = _remote.get(_pick[_view], {})
	if mod.is_empty():
		_empty_page("Pick a mod from the list." if _loaded[_view] and _remote_error[_view].is_empty() else "Mods from the AVaSt server show up here.")
		return
	_show_remote(mod)

func _empty_page(text: String) -> void:
	for part in [_header, _actions, _info, _update_box, _tabs]:
		_clear(part)
	_tidy_page()
	_page_message("", text)

func _head(icon: Variant, banner: Variant, title: String, version: String, author: String, author_link: Callable, categories: Array, stats: Array, links: Array, restart: bool) -> void:
	_clear(_header)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0)
	frame.border_color = _pal.line
	frame.border_width_bottom = 1
	frame.content_margin_bottom = 1
	_header.add_theme_stylebox_override("panel", frame)
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.modulate.a = 0.0
	_header.add_child(art)
	if banner != null:
		_put_texture(art, banner, func(texture: Texture2D) -> void: art.modulate.a = 1.0 if texture != null else 0.0)
	var fade := TextureRect.new()
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(_pal.field, 0.92))
	gradient.set_color(1, Color(_pal.field, 0.42))
	gradient.add_point(0.4, Color(_pal.field, 0.74))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 4
	fade.texture = texture
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	_header.add_child(fade)

	var pad := MarginContainer.new()
	_margins(pad, 10, 8)
	_header.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	pad.add_child(row)
	var picture := _icon(null, 40)
	picture.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_put_texture(picture, icon, func(found: Texture2D) -> void:
		if found == null:
			picture.texture = load(_MOD_ICON))
	row.add_child(picture)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 3)
	names.clip_contents = true
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	var name_label := _label(title, false)
	name_label.theme_type_variation = &"GroupTitle"
	name_label.add_theme_font_override("font", load(_HEADING_FONT))
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", _pal.text)
	title_row.add_child(name_label)
	if not version.is_empty():
		var version_label := _label(version, false)
		version_label.add_theme_color_override("font_color", _pal.muted)
		version_label.size_flags_vertical = Control.SIZE_SHRINK_END
		title_row.add_child(version_label)
	if restart:
		title_row.add_child(_icon(load(_RELOAD_ICON), 16))
	names.add_child(title_row)
	if not author.is_empty():
		var by := HBoxContainer.new()
		by.add_theme_constant_override("separation", 4)
		var prefix := _label("by", false)
		prefix.add_theme_color_override("font_color", _pal.text)
		by.add_child(prefix)
		by.add_child(_link(author, null, author_link) if author_link.is_valid() else _label(author, false))
		names.add_child(by)
	if not categories.is_empty():
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 3)
		chips.add_theme_constant_override("v_separation", 3)
		for category in categories:
			chips.add_child(_chip(str(category)))
		names.add_child(chips)
	row.add_child(names)
	if not stats.is_empty() or not links.is_empty():
		var column := VBoxContainer.new()
		column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		column.add_theme_constant_override("separation", 3)
		for stat: Array in stats:
			var line := HBoxContainer.new()
			line.alignment = BoxContainer.ALIGNMENT_END
			line.add_theme_constant_override("separation", 5)
			line.add_child(_icon(stat[0], 16))
			var label := _label(str(stat[1]), false)
			label.add_theme_color_override("font_color", _pal.text)
			line.add_child(label)
			column.add_child(line)
		for link: Array in links:
			var item := _link(str(link[0]), link[1], link[2])
			item.size_flags_horizontal = Control.SIZE_SHRINK_END
			column.add_child(item)
		row.add_child(column)

func _chip(category: String) -> Button:
	var chip := _button(Library.category_name(category), _set_category.bind(category))
	chip.icon = Library.category_icon(category)
	chip.tooltip = "Show all %s mods" % Library.category_name(category)
	chip.add_theme_constant_override("icon_max_width", 10)
	chip.add_theme_constant_override("h_separation", 3)
	chip.custom_minimum_size = Vector2(0, 16)
	var back := Palette.box(Color(_pal.accent, 0.14), Color(_pal.accent, 0.5), 1, 0)
	back.content_margin_left = 4
	back.content_margin_right = 5
	back.set_corner_radius_all(2)
	var hover := back.duplicate()
	hover.bg_color = Color(_pal.accent, 0.3)
	for state in ["normal", "pressed", "disabled"]:
		chip.add_theme_stylebox_override(state, back)
	for state in ["hover", "hover_pressed", "focus"]:
		chip.add_theme_stylebox_override(state, hover)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		chip.add_theme_color_override(key, _pal.text)
	return chip

func _link(text: String, icon: Variant, on_click: Callable) -> Button:
	var button := _button("", on_click)
	for state in ["normal", "pressed", "hover", "hover_pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	var width := 0.0
	var texture: Texture2D = icon if icon is Texture2D else (_texture(str(icon)) if icon != null else null)
	if texture != null:
		row.add_child(_icon(texture, 16))
		width += 20
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	var label := _label(text, false)
	label.add_theme_color_override("font_color", _pal.link)
	words.add_child(label)
	var underline := ColorRect.new()
	underline.color = _pal.link
	underline.custom_minimum_size.y = 1
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(underline)
	row.add_child(words)
	button.add_child(row)
	width += label.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	button.custom_minimum_size = Vector2(width + 2, 20)
	return button

func _put_texture(rect: TextureRect, source: Variant, done: Callable) -> void:
	if source == null or source is Texture2D:
		rect.texture = source
		if done.is_valid():
			done.call(source)
		return
	_core.store.texture(str(source), func(texture: Texture2D) -> void:
		if not is_instance_valid(rect):
			return
		rect.texture = texture
		if done.is_valid():
			done.call(texture), rect)

func _action(text: String, glyph: String, color: Color, on_click: Callable = Callable()) -> Button:
	var button := _button(text, on_click)
	button.icon = Icons.texture(glyph)
	button.add_theme_constant_override("h_separation", 5)
	var styles := {
		"normal": _colored(color), "hover": _colored(color.lightened(0.15)), "focus": _colored(color.lightened(0.15)),
		"pressed": _colored(color.darkened(0.15)), "hover_pressed": _colored(color.darkened(0.15)),
		"disabled": _colored(Color(color.lerp(Color(0.5, 0.5, 0.5), 0.5), 0.6)),
	}
	for state in styles:
		button.add_theme_stylebox_override(state, styles[state])
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(key, Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.65))
	button.add_theme_color_override("font_outline_color", color.darkened(0.55))
	button.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return button

func _colored(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.darkened(0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 7
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style

func _build_tabs(pages: Array) -> void:
	_page_list = pages
	_clear(_tabs)
	if pages.is_empty():
		return
	_tabs.add_child(_tab_rule(10))
	for page in pages:
		_tabs.add_child(_tab(str(page)))
		_tabs.add_child(_tab_rule(2))
	_tabs.get_child(_tabs.get_child_count() - 1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clip.call_deferred(_page_scroll)

func _tab(page: String) -> Button:
	var open := page == _page
	var tab := _button(page.capitalize(), _open_page.bind(page))
	tab.custom_minimum_size = Vector2(70, 22 if open else 20)
	tab.size_flags_vertical = Control.SIZE_SHRINK_END
	var back: Color = _pal.field if open else _pal.body.lerp(_pal.field, 0.45)
	for state in ["normal", "pressed", "disabled", "hover", "hover_pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = back if open or not state in ["hover", "hover_pressed", "focus"] else back.lerp(_pal.field, 0.6)
		style.border_color = _pal.border
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 0 if open else 1
		style.corner_radius_top_left = 3
		style.corner_radius_top_right = 3
		style.content_margin_left = 12
		style.content_margin_right = 12
		tab.add_theme_stylebox_override(state, style)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		tab.add_theme_color_override(key, _pal.text if open or key != "font_color" else _pal.muted)
	if open:
		var top := ColorRect.new()
		top.color = _TAB_TOP
		top.set_anchors_preset(Control.PRESET_TOP_WIDE)
		top.offset_left = 1
		top.offset_right = -1
		top.offset_bottom = 2
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab.add_child(top)
	return tab

func _tab_rule(width: int) -> Panel:
	var rule := Panel.new()
	rule.custom_minimum_size.x = width
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = _pal.border
	style.border_width_bottom = 1
	rule.add_theme_stylebox_override("panel", style)
	return rule

func _stats(downloads: int, day: int) -> Array:
	var stats: Array = []
	if downloads >= 0:
		stats.append([load(_DOWNLOADS_ICON), "%s download%s" % [_count(downloads), "" if downloads == 1 else "s"]])
	if day > 0:
		var date := Time.get_date_dict_from_unix_time(day * 86400)
		var hourglass := AtlasTexture.new()
		hourglass.atlas = load(_HOURGLASS)
		hourglass.region = Rect2(0, 0, 24, 24)
		stats.append([hourglass, "Updated %s %d, %d" % [_MONTHS[date.month - 1], date.day, date.year]])
	return stats

func _muted(text: String) -> Label:
	var label := _label(text, false)
	label.add_theme_color_override("font_color", _pal.muted)
	return label

func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer

func _status_line(text: String, color: Color = Color(0, 0, 0, 0)) -> void:
	var line := _label(text)
	if color.a > 0:
		line.add_theme_color_override("font_color", color)
	_info.add_child(line)

func _show_installed(info) -> void:
	if info == null:
		_empty_page("No mods installed." if _core.library.all().is_empty() else "No installed mods match.")
		return
	_clear(_info)
	var id: String = info.id
	var disabled: bool = _core.library.is_disabled(id)
	var removed: bool = _core.library.is_removed(id)
	var author_link: Callable = _core.open_link.bind(info.website) if not info.website.is_empty() else Callable()
	_head(info.icon() if info.icon() != null else load(_MOD_ICON), info.banner(), info.title(), "v" + info.version if not info.version.is_empty() else "",
		info.authors_text(), author_link, Library.categories(info), _stats(int(_core.store.downloads.get(id, -1)), 0), _installed_links(info), _needs_restart(id))
	_clear(_actions)
	_mod_buttons(id)
	var needed: Dictionary = _core.store.needs(id)
	if not removed and (not needed.mods.is_empty() or not needed.off.is_empty()):
		_actions.add_child(_action("Install what it needs", "download", _GREEN, _install_needs.bind(id)))
	var warn := Palette.readable(Color(0.75, 0.1, 0.1), _pal)
	if not disabled and not removed:
		for problem in _core.mods.problems(id):
			_status_line("⚠ " + problem, warn)
	if Library.plain_gdpatch(info):
		_status_line("⚠ Made for GDPatch alone, not for AVaSt. It works, but AVaSt can't update it or check what it needs.", Palette.readable(Color(0.72, 0.45, 0.0), _pal))
	var state: String = _core.updater.status.get(id, "")
	if not state.is_empty() and not state in ["downloading", "installed"]:
		_status_line(state, warn)
	if removed:
		_clear(_update_box)
	else:
		_show_update(id)
	_tidy_page()
	_build_tabs(_pages(info, not info.changelog().is_empty()))
	_set_page(_installed_doc(info))

func _installed_links(info) -> Array:
	var links: Array = []
	for key in info.links:
		links.append([str(key).capitalize(), _LINK_ICONS.get(str(key).to_lower(), _WEB_ICON), _core.open_link.bind(str(info.links[key]))])
	if not info.website.is_empty() and not info.links.values().has(info.website):
		links.append(["Website", _WEB_ICON, _core.open_link.bind(info.website)])
	links = links.slice(0, 2)
	if not info.dir.is_empty() and not _core.library.is_removed(info.id):
		links.append(["Folder", _FOLDER_ICON, OS.shell_open.bind(info.dir)])
	return links

func _mod_buttons(id: String) -> void:
	if _core.library.is_removed(id):
		_actions.add_child(_action("Undo uninstall", "undo", _GREEN, _undo_uninstall.bind(id)))
	elif _core.library.can_disable(id):
		if _core.library.is_disabled(id):
			_actions.add_child(_action("Turn on", "power", _GREEN, _toggle_mod.bind(id)))
		else:
			_actions.add_child(_action("Turn off", "power", _GREY, _toggle_mod.bind(id)))
		_actions.add_child(_action("Uninstall", "trash", _UNINSTALL, _ask_uninstall.bind(id)))

func _pages(info, changelog: bool) -> Array:
	var pages := ["readme"]
	if changelog:
		pages.append("changelog")
	if info != null and not _core.library.is_removed(info.id) and not Settings.sections(info).is_empty():
		pages.append("settings")
	return pages

func _settings_doc(info) -> Control:
	var id: String = info.id
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	var changed := false
	for section: Dictionary in Settings.sections(info):
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", 10)
		var title := _label(section.description if not section.description.is_empty() else str(section.id).capitalize(), false)
		title.theme_type_variation = &"GroupTitle"
		title.add_theme_font_override("font", load(_HEADING_FONT))
		title.add_theme_font_size_override("font_size", 13)
		title.add_theme_color_override("font_color", _pal.text)
		group.add_child(title)
		var rule := ColorRect.new()
		rule.color = _pal.line
		rule.custom_minimum_size.y = 1
		group.add_child(rule)
		for option: Dictionary in section.options:
			group.add_child(_setting(id, option))
			changed = changed or Settings.is_set(_core, id, option)
		column.add_child(group)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	var path: String = _core.library.settings_file(id)
	if FileAccess.file_exists(path):
		footer.add_child(_link("Open settings file", _FOLDER_ICON, OS.shell_open.bind(path)))
	if changed:
		footer.add_child(_link("Reset all", null, _reset_settings.bind(info)))
	if footer.get_child_count() > 0:
		column.add_child(footer)
	return column

func _setting(id: String, option: Dictionary) -> Control:
	if option.widget == "button":
		return _setting_button(id, option)
	var current: Variant = Settings.value(_core, id, option)
	var on: bool = current is bool and current
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	if option.type == "boolean":
		var toggle := _button(str(option.name), _change_setting.bind(id, option, not on))
		toggle.icon = AppearanceManager.checkbox_texture(on)
		toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		toggle.add_theme_constant_override("h_separation", 6)
		toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		for state in ["normal", "pressed", "hover", "hover_pressed", "focus", "disabled"]:
			toggle.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			toggle.add_theme_color_override(key, _pal.text)
		head.add_child(toggle)
	else:
		var title := _label(str(option.name), false)
		title.add_theme_color_override("font_color", _pal.text)
		head.add_child(title)
	head.add_child(_spacer())
	if Settings.is_set(_core, id, option):
		head.add_child(_link("Reset", null, _change_setting.bind(id, option, null)))
	box.add_child(head)
	var control := _setting_control(id, option, current)
	if control != null:
		box.add_child(control)
	if not str(option.description).is_empty():
		var about := _label(str(option.description))
		about.add_theme_color_override("font_color", _pal.muted)
		box.add_child(about)
	if option.type == "table":
		box.add_child(_muted("Change this one in the settings file."))
	return box

func _setting_button(id: String, option: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var button := _button(str(option.name), func() -> void: ModSettings.press(id, option.section, option.id))
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.custom_minimum_size.x = maxf(90, button.get_theme_font("font").get_string_size(str(option.name)).x + 24)
	button.disabled = not ModSettings.has_button(id, option.section, option.id)
	box.add_child(button)
	if not str(option.description).is_empty():
		var about := _label(str(option.description))
		about.add_theme_color_override("font_color", _pal.muted)
		box.add_child(about)
	if button.disabled:
		box.add_child(_muted("Works once the game has loaded the mod."))
	return box

func _setting_control(id: String, option: Dictionary, current: Variant) -> Control:
	var form := Form.new()
	form.mod = _core
	var choices: Array = option.choices
	var save := func(value: Variant) -> void: _change_setting(id, option, value)
	match option.type:
		"boolean":
			return null
		"table":
			var table := _label(Settings.describe(current if current != null else {}), true)
			table.add_theme_color_override("font_color", _pal.text)
			return table
		"array":
			if not choices.is_empty():
				var picked: Array = range(choices.size()).filter(func(i: int) -> bool: return current is Array and current.any(func(v: Variant) -> bool: return Settings.same(v, choices[i])))
				form.add_listbox("", choices, picked, true, mini(choices.size(), 6), func(indices: Array) -> void: save.call(indices.map(func(i: int) -> Variant: return choices[i])))
			else:
				form.add_input("", _setting_text(current), "", func(text: String) -> void: _commit_setting(id, option, text))
		_:
			if not choices.is_empty():
				var index := range(choices.size()).filter(func(i: int) -> bool: return Settings.same(current, choices[i]))
				form.add_combo("", choices, index[0] if not index.is_empty() else 0, func(i: int, _text: String) -> void: save.call(choices[i]))
			elif option.widget == "color":
				form.add_color("", Color.html(str(current)) if Color.html_is_valid(str(current)) else Color.WHITE, func(color: Color) -> void: save.call("#" + color.to_html(false)))
			elif option.type == "number":
				var whole: bool = option.default is int or option.default == null
				var step: float = float(option.step) if option.step != null else (1.0 if whole else 0.1)
				form.add_number("", float(current) if current != null else 0.0, float(option.min) if option.min != null else -1e9,
					float(option.max) if option.max != null else 1e9, step, func(value: Variant) -> void: save.call(int(value) if whole else float(value)))
			elif option.widget == "multiline":
				form.add_text_area("", str(current) if current != null else "", 4, func(text: String) -> void: save.call(text))
			else:
				form.add_input("", str(current) if current != null else "", "", func(text: String) -> void: save.call(text))
	return form

static func _setting_text(current: Variant) -> String:
	if current == null:
		return ""
	if current is Array:
		return ", ".join(current.map(func(part: Variant) -> String: return _setting_text(part)))
	if current is float and current == floorf(current) and absf(current) < 1e15:
		return str(int(current))
	return str(current)

func _commit_setting(id: String, option: Dictionary, text: String) -> void:
	text = text.strip_edges()
	var parsed: Variant = text
	if option.type == "number":
		if text.is_valid_int():
			parsed = float(text) if option.default is float else int(text)
		elif text.is_valid_float():
			parsed = float(text)
		else:
			parsed = null
	elif option.type == "array":
		var numbers: bool = option.default is Array and not option.default.is_empty() and option.default.all(func(part: Variant) -> bool: return part is int or part is float)
		parsed = [] if text.is_empty() else Array(text.split(",")).map(func(part: String) -> Variant:
			part = part.strip_edges()
			if numbers and part.is_valid_int():
				return int(part)
			if numbers and part.is_valid_float():
				return float(part)
			return part)
	if parsed != null:
		Settings.set_value(_core, id, option, parsed)
	_refresh_settings()

func _change_setting(id: String, option: Dictionary, new_value: Variant) -> void:
	Settings.set_value(_core, id, option, new_value)
	_refresh_settings()

func _reset_settings(info) -> void:
	for section: Dictionary in Settings.sections(info):
		for option: Dictionary in section.options:
			if Settings.is_set(_core, info.id, option):
				Settings.set_value(_core, info.id, option, null)
	_refresh_settings()

func _refresh_settings() -> void:
	var info = _core.library.info(_pick.installed if _view == "installed" else str(_pick[_view]))
	if info == null or _page != "settings" or not is_inside_tree():
		return
	var scroll := _page_scroll.scroll_vertical
	_set_page(_settings_doc(info))
	_page_scroll.set_deferred("scroll_vertical", scroll)

func _installed_doc(info) -> Control:
	if _page == "settings":
		return _settings_doc(info)
	var text: String = info.changelog() if _page == "changelog" else info.readme()
	if text.is_empty():
		text = info.summary()
	return Markdown.render(text, info.dir, _PAGE_WIDTH, _core.open_link)

func _show_update(id: String) -> void:
	var update: Dictionary = _core.updater.available.get(id, {})
	var done: Dictionary = _core.updater.installed_updates.get(id, {})
	var state: String = _core.updater.status.get(id, "")
	_clear(_update_box)
	if update.is_empty() and done.is_empty():
		return
	var shown: Dictionary = update if not update.is_empty() else done
	var finished := update.is_empty()
	_update_box.add_theme_stylebox_override("panel", Palette.box(Color(_GREEN, 0.12), Color(_GREEN, 0.8), 1, 8))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_update_box.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	if not finished:
		top.add_child(_icon(load(_UPDATE_ICON), 24))
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 2)
	var title := _label("Updated to %s" % shown.version if finished else "Update available", false)
	title.theme_type_variation = &"GroupTitle"
	title.add_theme_font_override("font", load(_HEADING_FONT))
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Palette.readable(_GREEN, _pal).lightened(0.1 if _pal.dark else 0.0))
	words.add_child(title)
	if not finished:
		var from := str(shown.get("from", _core.library.info(id).version if _core.library.info(id) != null else ""))
		var detail := "%s  →  %s" % [from, shown.version]
		if int(shown.get("size", 0)) > 0:
			detail += "   (%s)" % _core.store.size_text(int(shown.size))
		words.add_child(_label(detail, false))
	top.add_child(words)
	_update_top = top
	if state == "downloading":
		var progress := _download_progress(_core.store.progress.get(id, {}), 170)
		progress.name = "Progress"
		top.add_child(progress)
	elif not update.is_empty():
		var button := _action("Update to " + str(update.version), "update", _GREEN, _install_update.bind(id))
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.disabled = not _core.updater.batch.is_empty()
		top.add_child(button)
	column.add_child(top)
	var notes := str(shown.get("notes", "")).strip_edges()
	if not notes.is_empty() and not finished:
		var rule := ColorRect.new()
		rule.color = Color(_GREEN, 0.35)
		rule.custom_minimum_size.y = 1
		column.add_child(rule)
		var heading := _label("What's new in %s" % shown.version, false)
		heading.add_theme_color_override("font_color", _pal.muted)
		column.add_child(heading)
		column.add_child(Markdown.render(notes, "", _PAGE_WIDTH - 40, _core.open_link))

func _install_update(id: String) -> void:
	await _core.updater.install(id)
	if is_inside_tree():
		_refresh()

func _ask_uninstall(id: String) -> void:
	var info = _core.library.info(id)
	if info == null:
		return
	var choice := {"settings": false}
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var top := HBoxContainer.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 12)
	var picture := _icon(load(_RECYCLE_ICON), 32)
	picture.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(picture)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 6)
	var users: Array = _core.library.all().filter(func(other) -> bool: return other.id != id and not _core.library.is_removed(other.id) and other.dependencies.has(id))
	var text: String = "Remove %s?" % info.title() if _core.mods.has(id) else "Remove %s? Its files are deleted right away." % info.title()
	if not users.is_empty():
		text += " %s %s it." % [_and(users.map(func(other) -> String: return other.title())), "needs" if users.size() == 1 else "need"]
	var question := _label(text)
	question.custom_minimum_size.y = 32
	question.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	words.add_child(question)
	var has_settings := FileAccess.file_exists(_core.library.settings_file(id))
	if has_settings:
		var box := _button("Remove settings of this mod")
		box.icon = AppearanceManager.checkbox_texture(false)
		box.alignment = HORIZONTAL_ALIGNMENT_LEFT
		box.add_theme_constant_override("h_separation", 6)
		box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		for state in ["normal", "pressed", "hover", "hover_pressed", "focus", "disabled"]:
			box.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		box.clicked.connect(func() -> void:
			choice.settings = not choice.settings
			box.icon = AppearanceManager.checkbox_texture(choice.settings))
		words.add_child(box)
	top.add_child(words)
	body.add_child(top)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 6)
	var yes := _button("Uninstall")
	yes.custom_minimum_size = Vector2(64, 22)
	row.add_child(yes)
	var no := _button("Cancel")
	no.custom_minimum_size = Vector2(64, 22)
	row.add_child(no)
	body.add_child(row)
	var window: Control = _core.windows.open(body, "Uninstall %s" % info.title(), Vector2(330, 150 if has_settings else 130))
	yes.clicked.connect(func() -> void:
		_core.windows.close(window)
		_uninstall(id, choice.settings))
	no.clicked.connect(func() -> void: _core.windows.close(window))

func _uninstall(id: String, settings: bool) -> void:
	var error: String = _core.library.uninstall(id, settings)
	if not error.is_empty():
		_core.windows.popup("AVaSt", error)
	_refresh()

func _undo_uninstall(id: String) -> void:
	var error: String = _core.library.undo_uninstall(id)
	if not error.is_empty():
		_core.windows.popup("AVaSt", error)
	_refresh()

func _make_update_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	var style := Palette.box(Color(1, 1, 0.88), Color(0.6, 0.55, 0.3), 1, 4)
	bar.add_theme_stylebox_override("panel", style)
	bar.hide()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	bar.add_child(row)
	row.add_child(_icon(load(_UPDATE_ICON), 14))
	var text := Label.new()
	text.name = "Text"
	text.theme_type_variation = &"FuzzyType"
	text.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	text.add_theme_constant_override("outline_size", 0)
	text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.clip_text = true
	row.add_child(text)
	var all := _small_button("Update all", _install_all)
	all.name = "All"
	all.custom_minimum_size = Vector2(62, 16)
	row.add_child(all)
	return bar

func _refresh_update_bar() -> void:
	var count: int = _core.updater.available.size()
	var batch: Dictionary = _core.updater.batch
	_update_bar.visible = _view == "installed" and (count > 0 or not batch.is_empty())
	var text: Label = _update_bar.find_child("Text", true, false)
	var all: Button = _update_bar.find_child("All", true, false)
	if not batch.is_empty():
		text.text = "Updating %d of %d..." % [batch.done + 1, batch.total]
		all.hide()
	else:
		text.text = "%d update%s available" % [count, "" if count == 1 else "s"]
		all.show()

func _toggle_mod(id: String) -> void:
	var error: String = _core.library.enable(id) if _core.library.is_disabled(id) else _core.library.disable(id)
	if not error.is_empty():
		_core.windows.popup("AVaSt", error)
	_refresh()

func _show_remote(mod: Dictionary) -> void:
	_clear(_info)
	_clear(_update_box)
	var id := str(mod.id)
	var repo := str(mod.get("repo", ""))
	var on_github := not repo.is_empty() and not repo.begins_with("/")
	var author_link: Callable = _core.open_link.bind("https://github.com/" + repo.get_slice("/", 0)) if on_github else Callable()
	_head(mod.get("icon"), mod.get("banner"), str(mod.name), "v" + str(mod.get("version", "")), ", ".join(mod.get("authors", [])), author_link,
		mod.get("categories", []), _stats(int(mod.get("downloads", -1)), int(mod.get("updated", 0))), _remote_links(mod), _needs_restart(id))
	_fill_actions(mod)
	if _details.has(id):
		_remote_tabs(_details[id])
		_render_remote(_details[id])
		return
	_page = "readme"
	_clear(_tabs)
	_page_message("loading", "Loading the mod's page...")
	_page_token += 1
	var token := _page_token
	var data: Dictionary = await _core.store.details(id)
	if token != _page_token or not is_inside_tree():
		return
	if data.has("error"):
		_page_message("offline", _core.store.last_error)
		return
	_details[id] = data
	_remote_tabs(data)
	_render_remote(data)

func _remote_tabs(data: Dictionary) -> void:
	_build_tabs(_pages(_core.library.info(str(data.get("id", ""))), not str(data.get("changelog", "")).is_empty()))

func _render_remote(data: Dictionary) -> void:
	var info = _core.library.info(str(data.get("id", "")))
	if _page == "settings" and info != null:
		_set_page(_settings_doc(info))
		return
	var text := str(data.get("changelog" if _page == "changelog" else "readme", ""))
	if text.is_empty():
		text = str(data.get("summary", ""))
	_set_page(Markdown.render(text, str(data.get("base", "")), _PAGE_WIDTH, _core.open_link))

func _show_progress_only() -> void:
	var mod: Dictionary = _remote.get(_pick.get(_view, ""), {})
	if not mod.is_empty():
		_fill_actions(mod)

func _fill_actions(mod: Dictionary) -> void:
	_clear(_actions)
	var errors: VBoxContainer = _info.get_node_or_null("Notes")
	if errors == null:
		errors = VBoxContainer.new()
		errors.name = "Notes"
		_info.add_child(errors)
	_clear(errors)
	var id := str(mod.id)
	var state: String = _core.updater.status.get(id, "")
	var installed = _core.library.info(id)
	var version := str(mod.get("version", ""))
	if state == "downloading":
		_actions.add_child(_download_progress(_core.store.progress.get(id, {}), 240))
	elif installed == null:
		_actions.add_child(_action("Install", "download", _GREEN, _install_remote.bind(mod)))
		if int(mod.get("size", 0)) > 0:
			_actions.add_child(_muted(_core.store.size_text(int(mod.size))))
		_note_needs(errors, id)
	elif not _core.library.is_removed(id) and not _core.mods.version_at_least(installed.version, version) and _core.store.same_source(id) \
			and not id in Library.REQUIRED:
		_actions.add_child(_action("Update to " + version, "update", _GREEN, _install_remote.bind(mod)))
		_actions.add_child(_muted("%s installed" % installed.version))
		_note_needs(errors, id)
	else:
		_mod_buttons(id)
	if not state.is_empty() and not state in ["downloading", "installed"]:
		var error := _label(state)
		error.add_theme_color_override("font_color", Palette.readable(Color(0.75, 0.1, 0.1), _pal))
		errors.add_child(error)
	errors.visible = errors.get_child_count() > 0
	_tidy_page()
	_clip.call_deferred(_page_scroll)

func _note_needs(box: VBoxContainer, id: String) -> void:
	var needed: Dictionary = _core.store.needs(id)
	if not needed.mods.is_empty():
		box.add_child(_muted_wrap("Depends on %s." % _and(needed.mods.map(func(dep: Dictionary) -> String: return str(dep.name)))))
	if not needed.off.is_empty():
		box.add_child(_muted_wrap("Turns on %s, which it needs." % _and(needed.off.map(func(dep: String) -> String: return _core.library.info(dep).title()))))
	if not needed.unknown.is_empty():
		var missing := _label("It needs %s, which the AVaSt library doesn't have." % _and(needed.unknown))
		missing.add_theme_color_override("font_color", Palette.readable(Color(0.75, 0.1, 0.1), _pal))
		box.add_child(missing)

func _muted_wrap(text: String) -> Label:
	var label := _label(text)
	label.add_theme_color_override("font_color", _pal.muted)
	return label

static func _and(names: Array) -> String:
	if names.size() < 2:
		return "".join(names)
	return ", ".join(names.slice(0, -1)) + " and " + str(names[-1])

func _install_needs(id: String) -> void:
	for dep: Dictionary in _core.store.needs(id).mods:
		await _core.store.install(dep)
		if not is_inside_tree():
			return
	for dep: String in _core.store.needs(id).off:
		_core.library.enable(dep)
	if is_inside_tree():
		_refresh()

func _remote_links(mod: Dictionary) -> Array:
	var links: Array = []
	var website := str(mod.get("website", ""))
	if not website.is_empty():
		var key := "discord" if website.contains("discord.") else "website"
		links.append([key.capitalize(), _LINK_ICONS[key], _core.open_link.bind(website)])
	var repo := str(mod.get("repo", ""))
	if not repo.is_empty() and not repo.begins_with("/"):
		links.append(["Source", _LINK_ICONS.source, _core.open_link.bind("https://github.com/" + repo)])
	var installed = _core.library.info(str(mod.id))
	if installed != null and not installed.dir.is_empty() and not _core.library.is_removed(str(mod.id)):
		links.append(["Folder", _FOLDER_ICON, OS.shell_open.bind(installed.dir)])
	return links

func _download_progress(entry: Dictionary, width: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.custom_minimum_size.x = width
	var bytes: int = entry.get("bytes", 0)
	var total: int = entry.get("total", 0)
	var speed: float = entry.get("speed", 0.0)
	var bar := Marquee.new(width, 16)
	bar.value = float(entry.get("fraction", 0.0)) if total > 0 else -1.0
	box.add_child(bar)
	var parts: Array[String] = []
	if total > 0:
		parts.append("%d%%" % int(bar.value * 100))
		parts.append("%s of %s" % [_core.store.size_text(bytes), _core.store.size_text(total)])
	else:
		parts.append("Downloading %s" % _core.store.size_text(bytes))
	if speed > 0:
		parts.append("%s/s" % _core.store.size_text(int(speed)))
		if total > 0:
			parts.append("%s left" % _duration((total - bytes) / speed))
	else:
		parts.append("Connecting...")
	box.add_child(_label(", ".join(parts), false))
	return box

static func _duration(seconds: float) -> String:
	var s := int(ceilf(seconds))
	return "%d s" % s if s < 60 else "%d min %d s" % [s / 60, s % 60]

func _install_remote(mod: Dictionary) -> void:
	await _core.store.install(mod)
	if is_inside_tree():
		_refresh()

func _set_page(doc: Control) -> void:
	_clear(_page_body)
	_page_body.add_child(doc)
	doc.resized.connect(func() -> void: _clip.call_deferred(_page_scroll))
	_clip.call_deferred(_page_scroll)

func _page_message(kind: String, text: String) -> void:
	var center := _overlay()
	center.custom_minimum_size.y = 130
	_set_page(center)
	if not text.is_empty():
		_set_overlay(center, kind, text, false)

func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _fetch(view: String) -> void:
	_list_token += 1
	var token := _list_token
	_remote_error[view] = ""
	_loaded[view] = false
	_remote_lists[view] = []
	_list_page[view] = 0
	if view == _view:
		_refresh()
	var data: Dictionary
	if view == "featured":
		data = await _core.store.featured()
	else:
		data = await _core.store.search(_search.text.strip_edges(), _category, _SORTS[_sort][0], 1, 1000000)
	if token != _list_token or not is_inside_tree():
		return
	_loaded[view] = true
	if data.has("error"):
		_remote_error[view] = _core.store.last_error
	else:
		var mods: Array = data.get("mods", [])
		for mod in mods:
			_remote[str(mod.id)] = mod
		_remote_lists[view] = mods
		if view == "discover":
			_discover_total = mods.size()
		if not mods.any(func(m: Dictionary) -> bool: return m.id == _pick[view]):
			_pick[view] = ""
	if view == _view:
		_refresh()

func _fetch_stats() -> void:
	if not _core.store.available():
		return
	await _core.store.stats(_core.library.all().map(func(info) -> String: return info.id))
	if is_inside_tree() and _view == "installed":
		_show_selected()

func _install_all() -> void:
	var done: int = await _core.updater.install_all()
	if is_inside_tree():
		_refresh()
		_status.text = "%d updated" % done

static func _count(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out
