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
# renders README and changelog markdown kinda like github does, but as Controls in the games look.
# headings, lists, tables, quotes, code blocks with simple highlighting, alerts ([!NOTE] and co),
# images, and the bits of html readmes usualy use (img, a, details, align=center...).
#
# web images are PNG/JPEG from known hosts only (see safety.gd), anything else shows its alt text.
# nesting too deep just turns into plain text so no readme can hang the game.

extends RefCounted

const Markdown := preload("res://gdpatch/mods/avast_core/markdown.gd")
const Palette := preload("res://avast/api/ui/palette.gd")

const _BASE_FONT := "res://tahoma8_cjk_fallback.tres"
const _MONO_FONT := "res://gdpatch/mods/avast_core/assets/fonts/CozetteVector.ttf"
const _MONO_FALLBACK := "res://resources/theme/Tamzen5x9r.ttf"
const _HEADING_FONT := "res://inter-600.tres"
const _FONTS_DIR := "res://gdpatch/mods/avast_core/assets/fonts/"
const _BUTTON := "res://scenes/ui/standard_button/standard_button.tscn"
const Icons := preload("res://gdpatch/mods/avast_core/ui/icons.gd")
const Safety := preload("res://gdpatch/mods/avast_core/safety.gd")
const _MAX_DEPTH := 16
const _MAX_IMAGES := 50
const _MAX_CACHED := 300
const _HEADING_SIZES: Array[int] = [0, 16, 14, 12, 11, 10, 10]
const _MONO_SIZE := 13
const _IMAGE_SCALE := 0.5
const _ALERTS := {
	"note": ["Note", Color(0.035, 0.41, 0.85)],
	"tip": ["Tip", Color(0.1, 0.5, 0.22)],
	"important": ["Important", Color(0.51, 0.31, 0.87)],
	"warning": ["Warning", Color(0.6, 0.4, 0.0)],
	"caution": ["Caution", Color(0.82, 0.14, 0.18)],
}
const _KEYWORDS := [
	"func", "var", "const", "extends", "class", "class_name", "if", "elif", "else", "for", "while",
	"return", "match", "signal", "await", "static", "enum", "pass", "break", "continue", "in", "is",
	"as", "and", "or", "not", "self", "super", "preload", "load", "def", "import", "from", "let",
	"function", "new", "this", "export", "local", "end", "then", "do", "true", "false", "null",
	"None", "True", "False", "nil",
]
const _HASH_COMMENTS := ["gdscript", "gd", "python", "py", "toml", "ini", "cfg", "sh", "bash", "shell", "yaml", "yml", "ruby", "rb", "conf"]
const _PLAIN_CODE := ["", "text", "txt", "plain", "plaintext", "console", "output", "log", "md", "markdown"]
const _BLOCK_TAGS := [
	"p", "div", "center", "details", "summary", "h1", "h2", "h3", "h4", "h5", "h6", "hr", "picture",
	"source", "table", "thead", "tbody", "tr", "td", "th", "ul", "ol", "li", "pre", "blockquote",
	"dl", "dt", "dd",
]
const _ENTITIES := {
	"amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "copy": "©",
	"reg": "®", "trade": "™", "mdash": "—", "ndash": "–", "hellip": "…", "middot": "·",
	"times": "×", "rarr": "→", "larr": "←", "check": "✓",
}

const _FENCE := "^( {0,3})(`{3,}|~{3,})[ \\t]*([^`\\s]*)"
const _HEADING := "^ {0,3}(#{1,6})(?:[ \\t]+(.*?))?(?:[ \\t]+#+)?[ \\t]*$"
const _HR := "^ {0,3}([-*_])(?:[ \\t]*\\1){2,}[ \\t]*$"
const _QUOTE := "^ {0,3}> ?(.*)$"
const _LIST := "^( {0,3})(?:([-*+])|(\\d{1,9})([.)]))(?:([ \\t]+)(.*))?$"
const _SETEXT := "^ {0,3}(=+|-+)[ \\t]*$"
const _TABLE_SEP := "^ {0,3}\\|?[ \\t]*:?-+:?[ \\t]*(?:\\|[ \\t]*:?-+:?[ \\t]*)*\\|?[ \\t]*$"
const _HTML := "^ {0,3}<(/?)([a-zA-Z][a-zA-Z0-9-]*)"
const _REF := "^ {0,3}\\[([^\\]]+)\\]:[ \\t]*<?([^\\s>]+)>?(?:[ \\t]+(?:\"[^\"]*\"|'[^']*'|\\([^)]*\\)))?[ \\t]*$"
const _ALERT := "(?i)^\\[!(note|tip|important|warning|caution)\\][ \\t]*$"
const _TASK := "^\\[([ xX])\\](?:[ \\t]+|$)(.*)$"
const _PIC := "\uE002(\\d+)\uE003"
const _TOKEN := "\uE000(\\d+)\uE001"
const _LINK_TITLE := "(?:\\s+(?:\"[^\"]*\"|'[^']*'|\\([^)]*\\)))?"

static var _patterns := {}
static var _fonts := {}
static var _web_images := {}
static var _local_images := {}

var _doc: VBoxContainer
var _base := ""
var _width := 300.0
var _refs := {}
var _tokens: Array[String] = []
var _pics: Array[Dictionary] = []
var _headings := {}
var _pal := {}
var _open_url := Callable()
var _hover_key: Area2D
var _depth := 0
var _mark_depth := 0
var _images := 0

static func render(markdown: String, base_dir: String = "", max_width: float = 300.0, open_url: Callable = Callable()) -> VBoxContainer:
	var doc := VBoxContainer.new()
	doc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doc.add_theme_constant_override("separation", 9)
	var renderer := Markdown.new()
	renderer._doc = doc
	renderer._width = max_width
	renderer._open_url = open_url
	renderer._pal = Palette.current()
	doc.set_meta(&"markdown", renderer)
	doc.tree_exiting.connect(renderer._release_hover)
	renderer._show(markdown, base_dir)
	return doc

func _show(markdown: String, base_dir: String) -> void:
	_base = base_dir
	_images = 0
	_refs.clear()
	_tokens.clear()
	_pics.clear()
	_headings.clear()
	for child in _doc.get_children():
		if child is Control:
			_doc.remove_child(child)
			child.queue_free()
	var text := Safety.text(markdown).replace("\r\n", "\n").replace("\r", "\n").replace("\t", "    ")
	text = _re("<!--[\\s\\S]*?-->").sub(text, "", true)
	var blocks := _blocks(Array(text.split("\n")))
	if blocks.is_empty():
		blocks = [{"type": "paragraph", "text": "*No description.*"}]
	_build(blocks, _doc, {"color": _pal.text, "align": HORIZONTAL_ALIGNMENT_LEFT, "depth": 0})

func _nested(lines: Array) -> Array:
	if _depth >= _MAX_DEPTH:
		return [{"type": "code", "lang": "", "text": "\n".join(lines)}]
	_depth += 1
	var out := _blocks(lines)
	_depth -= 1
	return out

func _blocks(lines: Array) -> Array:
	var out := []
	var i := 0
	var n := lines.size()
	while i < n:
		var line: String = lines[i]
		if line.strip_edges().is_empty():
			i += 1
			continue
		var m := _re(_FENCE).search(line)
		if m != null:
			var indent := m.get_string(1).length()
			var fence := m.get_string(2)
			var code: Array[String] = []
			i += 1
			while i < n:
				var inner: String = lines[i]
				var closing := inner.strip_edges()
				i += 1
				if _indent(inner) < 4 and closing.length() >= fence.length() and closing == fence[0].repeat(closing.length()):
					break
				code.append(inner.substr(mini(indent, _indent(inner))))
			out.append({"type": "code", "lang": m.get_string(3).to_lower(), "text": "\n".join(code)})
			continue
		if _indent(line) >= 4:
			var code: Array[String] = []
			while i < n and (str(lines[i]).strip_edges().is_empty() or _indent(lines[i]) >= 4):
				code.append(str(lines[i]).substr(4))
				i += 1
			while not code.is_empty() and code.back().strip_edges().is_empty():
				code.pop_back()
			out.append({"type": "code", "lang": "", "text": "\n".join(code)})
			continue
		m = _re(_HEADING).search(line)
		if m != null:
			out.append({"type": "heading", "level": m.get_string(1).length(), "text": m.get_string(2).strip_edges()})
			i += 1
			continue
		if _matches(_HR, line):
			out.append({"type": "hr"})
			i += 1
			continue
		if _matches(_QUOTE, line):
			i = _quote_block(lines, i, out)
			continue
		if _matches(_LIST, line):
			i = _list_block(lines, i, out)
			continue
		if i + 1 < n and line.contains("|") and str(lines[i + 1]).contains("-") and _matches(_TABLE_SEP, lines[i + 1]) \
				and _cells(line).size() == _cells(lines[i + 1]).size():
			i = _table_block(lines, i, out)
			continue
		if _html_block(line):
			i = _html_blocks(lines, i, out)
			continue
		m = _re(_REF).search(line)
		if m != null:
			_refs[m.get_string(1).strip_edges().to_lower()] = m.get_string(2)
			i += 1
			continue
		var paragraph: Array[String] = []
		while i < n:
			var text: String = lines[i]
			if text.strip_edges().is_empty():
				break
			if not paragraph.is_empty():
				var setext := _re(_SETEXT).search(text)
				if setext != null:
					out.append({"type": "heading", "level": 1 if setext.get_string(1)[0] == "=" else 2, "text": " ".join(paragraph).strip_edges()})
					paragraph.clear()
					i += 1
					break
				if _interrupts(text):
					break
			paragraph.append(text.lstrip(" "))
			i += 1
		if not paragraph.is_empty():
			out.append({"type": "paragraph", "text": "\n".join(paragraph)})
	return out

func _quote_block(lines: Array, i: int, out: Array) -> int:
	var inner: Array[String] = []
	while i < lines.size():
		var line: String = lines[i]
		var m := _re(_QUOTE).search(line)
		if m != null:
			inner.append(m.get_string(1))
		elif not line.strip_edges().is_empty() and not inner.is_empty() and not inner.back().strip_edges().is_empty() and not _starts_block(line):
			inner.append(line)
		else:
			break
		i += 1
	var alert := ""
	if not inner.is_empty():
		var m := _re(_ALERT).search(inner[0].strip_edges())
		if m != null:
			alert = m.get_string(1).to_lower()
			inner.remove_at(0)
	out.append({"type": "quote", "alert": alert, "children": _nested(Array(inner))})
	return i

func _list_block(lines: Array, i: int, out: Array) -> int:
	var first := _re(_LIST).search(lines[i])
	var ordered := not first.get_string(3).is_empty()
	var marker := first.get_string(4) if ordered else first.get_string(2)
	var items := []
	while i < lines.size():
		var m := _re(_LIST).search(lines[i])
		if m == null or (not m.get_string(3).is_empty()) != ordered or (m.get_string(4) if ordered else m.get_string(2)) != marker:
			break
		var gap := m.get_string(5).length()
		var pad := m.get_string(1).length() + m.get_string(2).length() + m.get_string(3).length() + m.get_string(4).length() + (gap if gap in range(1, 5) else 1)
		var body: Array[String] = [m.get_string(6)]
		i += 1
		var blank := false
		while i < lines.size():
			var line: String = lines[i]
			if line.strip_edges().is_empty():
				blank = true
				body.append("")
				i += 1
			elif _indent(line) >= pad:
				body.append(line.substr(pad))
				blank = false
				i += 1
			elif not blank and not _starts_block(line):
				body.append(line.strip_edges())
				i += 1
			else:
				break
		while body.size() > 1 and body.back().is_empty():
			body.pop_back()
		var task := -1
		var t := _re(_TASK).search(body[0])
		if t != null:
			task = 0 if t.get_string(1) == " " else 1
			body[0] = t.get_string(2)
		items.append({"task": task, "children": _nested(Array(body))})
	out.append({"type": "list", "ordered": ordered, "start": int(first.get_string(3)) if ordered else 1, "items": items})
	return i

func _table_block(lines: Array, i: int, out: Array) -> int:
	var header := _cells(lines[i])
	var aligns := []
	for cell in _cells(lines[i + 1]):
		var spec: String = cell.strip_edges()
		if spec.begins_with(":") and spec.ends_with(":"):
			aligns.append(HORIZONTAL_ALIGNMENT_CENTER)
		elif spec.ends_with(":"):
			aligns.append(HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			aligns.append(HORIZONTAL_ALIGNMENT_LEFT)
	i += 2
	var rows := []
	while i < lines.size() and not str(lines[i]).strip_edges().is_empty() and not _starts_block(lines[i]):
		rows.append(_cells(lines[i]))
		i += 1
	out.append({"type": "table", "header": header, "align": aligns, "rows": rows})
	return i

func _html_blocks(lines: Array, i: int, out: Array) -> int:
	var tag := _re(_HTML).search(lines[i]).get_string(2).to_lower()
	var chunk: Array[String] = []
	if tag == "details":
		var depth := 0
		while i < lines.size():
			var line: String = str(lines[i])
			depth += line.to_lower().count("<details") - line.to_lower().count("</details")
			chunk.append(line)
			i += 1
			if depth <= 0:
				break
		var text := "\n".join(chunk)
		var summary := "Details"
		var m := _re("(?is)<summary[^>]*>(.*?)</summary>").search(text)
		if m != null:
			summary = m.get_string(1).strip_edges()
			text = text.replace(m.get_string(0), "")
		text = _re("(?i)</?details[^>]*>").sub(text, "", true)
		out.append({"type": "details", "summary": summary, "children": _nested(Array(text.split("\n")))})
		return i
	while i < lines.size() and not str(lines[i]).strip_edges().is_empty():
		chunk.append(str(lines[i]))
		i += 1
	var text := "\n".join(chunk)
	var centered := _re("(?i)align\\s*=\\s*[\"']?center|<center").search(text) != null
	for level in range(1, 7):
		text = _re("(?is)<h%d\\b[^>]*>(.*?)</h%d>" % [level, level]).sub(text, "\n\n%s $1\n\n" % "#".repeat(level), true)
	text = _re("(?i)<hr\\b[^>]*>").sub(text, "\n\n---\n\n", true)
	text = _re("(?i)</?(?:%s)\\b[^>]*>" % "|".join(_BLOCK_TAGS)).sub(text, "\n\n", true)
	var blocks := _nested(Array(text.split("\n")))
	if centered:
		for block in blocks:
			block.align = HORIZONTAL_ALIGNMENT_CENTER
	out.append_array(blocks)
	return i

func _cells(line: String) -> Array[String]:
	var text := line.strip_edges()
	if text.begins_with("|"):
		text = text.substr(1)
	if text.ends_with("|") and not text.ends_with("\\|"):
		text = text.substr(0, text.length() - 1)
	var cells: Array[String] = []
	var cell := ""
	var in_code := false
	var k := 0
	while k < text.length():
		var ch := text[k]
		if ch == "\\" and k + 1 < text.length() and text[k + 1] == "|":
			cell += "|"
			k += 2
			continue
		if ch == "`":
			in_code = not in_code
		if ch == "|" and not in_code:
			cells.append(cell.strip_edges())
			cell = ""
		else:
			cell += ch
		k += 1
	cells.append(cell.strip_edges())
	return cells

func _starts_block(line: String) -> bool:
	return _matches(_FENCE, line) or _matches(_HEADING, line) or _matches(_HR, line) or _matches(_QUOTE, line) \
		or _matches(_LIST, line) or _html_block(line)

func _interrupts(line: String) -> bool:
	if _matches(_FENCE, line) or _matches(_HEADING, line) or _matches(_HR, line) or _matches(_QUOTE, line) or _html_block(line):
		return true
	var m := _re(_LIST).search(line)
	return m != null and not m.get_string(6).strip_edges().is_empty() and (m.get_string(3).is_empty() or m.get_string(3) == "1")

func _html_block(line: String) -> bool:
	var m := _re(_HTML).search(line)
	return m != null and m.get_string(2).to_lower() in _BLOCK_TAGS

static func _indent(line: String) -> int:
	return line.length() - line.lstrip(" ").length()

func _inline(text: String) -> String:
	var out := _mark(text)
	for _pass in 8:
		if not out.contains("\uE000"):
			break
		out = _each(_re(_TOKEN), out, func(m: RegExMatch) -> String: return _tokens[int(m.get_string(1))])
	return out.strip_edges()

func _mark(text: String) -> String:
	text = _each(_re("( {2,}|\\\\)\\n"), text, func(_m: RegExMatch) -> String: return _keep("\n"))
	text = _each(_re("\\\\([!-/:-@\\[-`{-~])"), text, func(m: RegExMatch) -> String: return _keep(_escape(m.get_string(1))))
	text = _each(_re("(`+)([\\s\\S]*?[^`])\\1(?!`)"), text, func(m: RegExMatch) -> String: return _keep(_code_span(m.get_string(2))))
	text = _each(_re("(?i)<br\\s*/?>"), text, func(_m: RegExMatch) -> String: return _keep("\n"))
	text = _each(_re("(?i)<img\\b[^>]*>"), text, _on_html_image)
	text = _each(_re("(?is)<a\\b([^>]*)>(.*?)</a>"), text, func(m: RegExMatch) -> String: return _link(_attr(m.get_string(1), "href"), m.get_string(2)))
	text = _each(_re("(?is)<(code|kbd|samp|tt)\\b[^>]*>(.*?)</\\1>"), text, func(m: RegExMatch) -> String: return _keep(_code_span(_entities(m.get_string(2)))))
	text = _each(_re("(?is)<(b|strong|i|em|s|del|strike|u|ins)\\b[^>]*>(.*?)</\\1>"), text, _on_html_style)
	text = _each(_re("(?i)<((?:https?|ftp)://[^>\\s]+|mailto:[^>\\s]+)>"), text, func(m: RegExMatch) -> String: return _link(m.get_string(1), m.get_string(1)))
	text = _each(_re("<([^@\\s<>]+@[^@\\s<>]+\\.[a-zA-Z]+)>"), text, func(m: RegExMatch) -> String: return _link("mailto:" + m.get_string(1), m.get_string(1)))
	text = _re("</?[a-zA-Z][a-zA-Z0-9-]*(?:\\s[^<>]*)?/?>").sub(text, "", true)
	text = _each(_re("!\\[([^\\]]*)\\]\\(\\s*<?([^\\s)>]*)>?" + _LINK_TITLE + "\\s*\\)"), text, func(m: RegExMatch) -> String: return _picture(m.get_string(2), m.get_string(1)))
	text = _each(_re("!\\[([^\\]]*)\\]\\[([^\\]]*)\\]"), text, _on_ref_image)
	text = _each(_re("\\[((?:[^\\[\\]]|\\[[^\\]]*\\])*)\\]\\(\\s*<?([^\\s)>]*)>?" + _LINK_TITLE + "\\s*\\)"), text, func(m: RegExMatch) -> String: return _link(m.get_string(2), m.get_string(1)))
	text = _each(_re("\\[([^\\]]+)\\]\\[([^\\]]*)\\]"), text, _on_ref_link)
	text = _each(_re("\\[([^\\]]+)\\](?![(\\[:])"), text, _on_ref_link)
	text = _each(_re("(?<![\\w/\"'=\\]])(https?://[^\\s<>\\[\\]]*[^\\s<>\\[\\].,:;\"')!?*_])"), text, func(m: RegExMatch) -> String: return _link(m.get_string(1), m.get_string(1)))
	text = _escape(_entities(text))
	text = _re("\\*\\*\\*(?=\\S)([\\s\\S]+?)(?<=\\S)\\*\\*\\*").sub(text, "[b][i]$1[/i][/b]", true)
	text = _re("\\*\\*(?=\\S)([\\s\\S]+?)(?<=\\S)\\*\\*").sub(text, "[b]$1[/b]", true)
	text = _re("(?<![\\w\\\\])__(?=\\S)([\\s\\S]+?)(?<=\\S)__(?!\\w)").sub(text, "[b]$1[/b]", true)
	text = _re("\\*(?=[^\\s*])([\\s\\S]+?)(?<=[^\\s*])\\*").sub(text, "[i]$1[/i]", true)
	text = _re("(?<![\\w\\\\])_(?=[^\\s_])([\\s\\S]+?)(?<=[^\\s_])_(?!\\w)").sub(text, "[i]$1[/i]", true)
	text = _re("~~(?=\\S)([\\s\\S]+?)(?<=\\S)~~").sub(text, "[s]$1[/s]", true)
	return text.replace("\n", " ")

func _mark_nested(text: String) -> String:
	if _mark_depth >= _MAX_DEPTH:
		return _escape(_entities(text))
	_mark_depth += 1
	var out := _mark(text)
	_mark_depth -= 1
	return out

func _keep(bbcode: String) -> String:
	_tokens.append(bbcode)
	return "\uE000%d\uE001" % (_tokens.size() - 1)

func _link(url: String, label: String) -> String:
	var inner := _escape(_entities(label)) if label == url else _mark_nested(label)
	for m in _re(_PIC).search_all(inner):
		_pics[int(m.get_string(1))].link = url
	if inner.strip_edges().is_empty():
		inner = _escape(url)
	return _keep("[url=%s][color=#%s]%s[/color][/url]" % [url.replace("]", "%5D"), _pal.link.to_html(false), inner])

func _picture(src: String, alt: String, width: float = 0.0, height: float = 0.0) -> String:
	_pics.append({"src": src, "alt": alt, "w": width, "h": height, "link": ""})
	return "\uE002%d\uE003" % (_pics.size() - 1)

func _code_span(code: String) -> String:
	if code.length() > 2 and code.begins_with(" ") and code.ends_with(" "):
		code = code.substr(1, code.length() - 2)
	return "[bgcolor=#%s][code]%s[/code][/bgcolor]" % [_pal.code_back.darkened(0.04 if not _pal.dark else -0.04).to_html(false), _escape(code)]

func _on_html_image(m: RegExMatch) -> String:
	var tag := m.get_string(0)
	var width := _attr(tag, "width")
	var height := _attr(tag, "height")
	return _picture(_attr(tag, "src"), _attr(tag, "alt"), float(width) if width.is_valid_float() else 0.0, float(height) if height.is_valid_float() else 0.0)

func _on_html_style(m: RegExMatch) -> String:
	var tag: String = {"strong": "b", "em": "i", "del": "s", "strike": "s", "ins": "u"}.get(m.get_string(1).to_lower(), m.get_string(1).to_lower())
	return _keep("[%s]%s[/%s]" % [tag, _mark_nested(m.get_string(2)), tag])

func _on_ref_image(m: RegExMatch) -> String:
	var key := (m.get_string(2) if not m.get_string(2).is_empty() else m.get_string(1)).to_lower()
	return _picture(_refs[key], m.get_string(1)) if _refs.has(key) else m.get_string(0)

func _on_ref_link(m: RegExMatch) -> String:
	var key := (m.get_string(2) if m.get_group_count() > 1 and not m.get_string(2).is_empty() else m.get_string(1)).strip_edges().to_lower()
	return _link(_refs[key], m.get_string(1)) if _refs.has(key) else m.get_string(0)

func _entities(text: String) -> String:
	return _each(_re("&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);"), text, func(m: RegExMatch) -> String:
		var name := m.get_string(1)
		if name.begins_with("#x") or name.begins_with("#X"):
			return String.chr(name.substr(2).hex_to_int())
		if name.begins_with("#"):
			return String.chr(int(name.substr(1)))
		return _ENTITIES.get(name, m.get_string(0)))

static func _attr(tag: String, name: String) -> String:
	var m := _re("(?i)\\b%s\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))" % name).search(tag)
	if m == null:
		return ""
	for group in [1, 2, 3]:
		if not m.get_string(group).is_empty():
			return m.get_string(group)
	return ""

static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")

static func _plain(text: String) -> String:
	text = _re("<[^>]+>|!?\\[|\\]\\([^)]*\\)|\\][^\\s]*|[*_`~#]").sub(text, "", true)
	return text.strip_edges()

func _build(blocks: Array, into: Container, ctx: Dictionary) -> void:
	for block in blocks:
		var inner := ctx.duplicate()
		if block.has("align"):
			inner.align = block.align
		var node: Control = null
		match block.type:
			"heading":
				node = _heading(block, inner)
			"paragraph":
				node = _paragraph(block.text, inner)
			"code":
				node = _code(block)
			"quote":
				node = _quote(block, inner)
			"list":
				node = _list(block, inner)
			"table":
				node = _table(block, inner)
			"hr":
				node = _rule(1)
			"details":
				node = _details(block, inner)
		if node != null:
			into.add_child(node)

func _rich(bbcode: String, ctx: Dictionary) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = true
	label.clip_contents = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = ctx.align
	label.add_theme_color_override("default_color", ctx.color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_constant_override("line_separation", 3)
	var text_size := label.get_theme_font_size(&"normal_font_size")
	for style in ["bold", "italics", "bold_italics"]:
		label.add_theme_font_override(style + "_font", _font(style))
		label.add_theme_font_size_override(style + "_font_size", text_size)
	label.add_theme_font_override("mono_font", _font("mono"))
	label.add_theme_font_size_override("mono_font_size", _MONO_SIZE)
	label.meta_clicked.connect(_follow)
	label.meta_hover_started.connect(_hover_link.bind(true))
	label.meta_hover_ended.connect(_hover_link.bind(false))
	_fill(label, bbcode)
	return label

func _fill(label: RichTextLabel, bbcode: String) -> void:
	var space := "[font_size=%d] [/font_size]" % label.get_theme_font_size(&"normal_font_size")
	bbcode = _re("(\\[/(?:b|i|code)\\](?:\\[/(?:b|i|s|u|color|url|bgcolor)\\])*) ").sub(bbcode, "$1" + space, true)
	var last := 0
	for m in _re(_PIC).search_all(bbcode):
		label.append_text(bbcode.substr(last, m.get_start() - last))
		var pic: Dictionary = _pics[int(m.get_string(1))]
		var texture := _local_texture(pic.src)
		if texture != null:
			var size := _picture_size(texture, pic)
			label.add_image(texture, int(size.x), int(size.y))
		else:
			label.append_text("[color=#%s]%s[/color]" % [_pal.muted.to_html(false), _escape(pic.alt)])
		last = m.get_end()
	label.append_text(bbcode.substr(last))

func _heading(block: Dictionary, ctx: Dictionary) -> Control:
	var level: int = block.level
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	if level <= 3 and _doc.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 4
		column.add_child(gap)
	var title := _rich(_inline(block.text), ctx)
	title.add_theme_font_override("normal_font", _font("heading"))
	title.add_theme_font_size_override("normal_font_size", _HEADING_SIZES[level])
	if level == 6:
		title.add_theme_color_override("default_color", _pal.muted)
	column.add_child(title)
	if level <= 2:
		column.add_child(_rule(1))
	_headings[_slug(block.text)] = column
	return column

func _paragraph(text: String, ctx: Dictionary) -> Control:
	var bbcode := _inline(text)
	if bbcode.is_empty():
		return null
	if _re("\\[/?(?:url|color)[^\\]]*\\]|\uE002\\d+\uE003|\\s").sub(bbcode, "", true).is_empty():
		return _picture_row(bbcode, ctx)
	return _rich(bbcode, ctx)

func _code(block: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(_pal.code_back, _pal.line, 1, 8))
	var label := _rich("", {"color": _pal.text, "align": HORIZONTAL_ALIGNMENT_LEFT})
	label.add_theme_font_override("normal_font", _font("mono"))
	label.add_theme_font_size_override("normal_font_size", _MONO_SIZE)
	label.add_theme_constant_override("line_separation", 1)
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.append_text(_highlight(block.text, block.lang))
	panel.add_child(label)
	return panel

func _quote(block: Dictionary, ctx: Dictionary) -> Control:
	var alert: String = block.alert
	var color: Color = Palette.readable(_ALERTS[alert][1], _pal) if not alert.is_empty() else _pal.line.darkened(0.1)
	var style := _box(Color(color, 0.07) if not alert.is_empty() else Color(0, 0, 0, 0), color, 0, 10)
	style.border_width_left = 3
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	var inner := ctx.duplicate()
	if alert.is_empty():
		inner.color = _pal.muted
	else:
		column.add_child(_rich("[b][color=#%s]%s[/color][/b]" % [color.to_html(false), _ALERTS[alert][0]], inner))
	_build(block.children, column, inner)
	return panel

func _list(block: Dictionary, ctx: Dictionary) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	var number: int = block.start
	var inner := ctx.duplicate()
	inner.depth = ctx.depth + 1
	inner.align = HORIZONTAL_ALIGNMENT_LEFT
	for item in block.items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		if item.task >= 0:
			var holder := Control.new()
			holder.custom_minimum_size = Vector2(11, 11)
			var box := TextureRect.new()
			box.texture = AppearanceManager.checkbox_texture(item.task == 1)
			box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			box.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			box.position = Vector2(1, 2)
			box.size = Vector2(9, 9)
			holder.add_child(box)
			row.add_child(holder)
		elif block.ordered:
			var label := _rich("%d." % number, {"color": ctx.color, "align": HORIZONTAL_ALIGNMENT_RIGHT})
			label.size_flags_horizontal = Control.SIZE_FILL
			label.custom_minimum_size.x = 14
			row.add_child(label)
		else:
			row.add_child(_bullet(ctx.depth, ctx.color))
		var content := VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 6)
		_build(item.children, content, inner)
		row.add_child(content)
		column.add_child(row)
		number += 1
	return column

func _bullet(depth: int, color: Color) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(9, 11)
	var dot := Panel.new()
	dot.add_theme_stylebox_override("panel", _box(color if depth % 2 == 0 else Color(0, 0, 0, 0), color, 1, 0))
	dot.position = Vector2(3, 5)
	dot.size = Vector2(3, 3)
	holder.add_child(dot)
	return holder

func _table(block: Dictionary, ctx: Dictionary) -> Control:
	var columns: int = block.header.size()
	var font := _font("base")
	var font_size := ThemeDB.fallback_font_size
	var widths: Array[float] = []
	for c in columns:
		var widest := 0.0
		for row in [block.header] + block.rows:
			if c < row.size():
				widest = maxf(widest, font.get_string_size(_plain(row[c]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		widths.append(minf(widest + 16, 160))
	var total := 0.0
	for w in widths:
		total += w
	if total > _width:
		for c in columns:
			widths[c] = floorf(widths[c] * _width / total)
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var outline := _box(Color(0, 0, 0, 0), _pal.line, 0, 0)
	outline.border_width_left = 1
	outline.border_width_top = 1
	frame.add_theme_stylebox_override("panel", outline)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	frame.add_child(grid)
	var rows: Array = [block.header] + block.rows
	for r in rows.size():
		for c in columns:
			var raw: String = rows[r][c] if c < rows[r].size() else ""
			var shade := Color.WHITE if _pal.dark else Color.BLACK
			var back := Color(shade, 0.06) if r == 0 else (Color(shade, 0.025) if r % 2 == 0 else Color(0, 0, 0, 0))
			var style := _box(back, _pal.line, 0, 7)
			style.border_width_right = 1
			style.border_width_bottom = 1
			style.content_margin_top = 4
			style.content_margin_bottom = 4
			var cell := PanelContainer.new()
			cell.custom_minimum_size.x = widths[c]
			cell.add_theme_stylebox_override("panel", style)
			var inner := ctx.duplicate()
			inner.align = block.align[c] if c < block.align.size() else HORIZONTAL_ALIGNMENT_LEFT
			var text := _inline(raw)
			cell.add_child(_rich("[b]%s[/b]" % text if r == 0 else text, inner))
			grid.add_child(cell)
	return frame

func _details(block: Dictionary, ctx: Dictionary) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	var toggle: Button = load(_BUTTON).instantiate()
	toggle.text = _plain(block.summary)
	toggle.icon = Icons.arrow("right")
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.autowrap_mode = TextServer.AUTOWRAP_OFF
	toggle.custom_minimum_size.y = 16
	toggle.add_theme_constant_override("h_separation", 5)
	toggle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for key in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
		toggle.add_theme_color_override(key, ctx.color)
	for state in ["normal", "pressed", "hover", "hover_pressed", "disabled", "focus"]:
		toggle.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	column.add_child(toggle)
	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 12)
	body.visible = false
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	body.add_child(inner)
	_build(block.children, inner, ctx)
	column.add_child(body)
	toggle.clicked.connect(func() -> void:
		body.visible = not body.visible
		toggle.icon = Icons.arrow("down" if body.visible else "right"))
	return column

func _rule(height: int) -> Control:
	var line := ColorRect.new()
	line.color = _pal.line
	line.custom_minimum_size.y = height
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

static func _box(back: Color, border: Color, border_width: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = back
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_content_margin_all(padding)
	return style

func _picture_row(bbcode: String, ctx: Dictionary) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	if ctx.align == HORIZONTAL_ALIGNMENT_CENTER:
		row.alignment = FlowContainer.ALIGNMENT_CENTER
	elif ctx.align == HORIZONTAL_ALIGNMENT_RIGHT:
		row.alignment = FlowContainer.ALIGNMENT_END
	for m in _re(_PIC).search_all(bbcode):
		row.add_child(_picture_control(_pics[int(m.get_string(1))], ctx))
	return row

func _picture_control(pic: Dictionary, ctx: Dictionary) -> Control:
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.tooltip_text = pic.alt
	if not str(pic.link).is_empty():
		rect.mouse_filter = Control.MOUSE_FILTER_STOP
		rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		rect.mouse_entered.connect(_hover_link.bind(pic.link, true))
		rect.mouse_exited.connect(_hover_link.bind(pic.link, false))
		rect.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_follow(pic.link))
	var src: String = pic.src
	if _base.contains("://") and not src.contains("://") and not src.begins_with("res://"):
		src = _base.path_join(src.trim_prefix("./").trim_prefix("/"))
	var alt := "[color=#%s]%s[/color]" % [_pal.muted.to_html(false), _escape(pic.alt)]
	if src.begins_with("http://") or src.begins_with("https://"):
		if not Safety.is_image_url(src) or _images >= _MAX_IMAGES or (_web_images.has(src) and _web_images[src] == null):
			rect.free()
			return _rich(alt, ctx)
		_images += 1
		if pic.w > 0 and pic.h > 0:
			rect.custom_minimum_size = (Vector2(pic.w, pic.h) * _IMAGE_SCALE).round()
		_download(src, func(texture: Texture2D) -> void:
			if not is_instance_valid(rect):
				return
			if texture == null:
				rect.replace_by(_rich(alt, ctx))
				rect.queue_free()
				return
			rect.texture = texture
			rect.custom_minimum_size = _picture_size(texture, pic))
		return rect
	var texture := _local_texture(src)
	if texture == null:
		rect.free()
		return _rich(alt, ctx)
	rect.texture = texture
	rect.custom_minimum_size = _picture_size(texture, pic)
	return rect

func _picture_size(texture: Texture2D, pic: Dictionary) -> Vector2:
	var width: float = pic.w
	var height: float = pic.h
	var ratio := float(texture.get_height()) / maxf(texture.get_width(), 1)
	if width <= 0 and height <= 0:
		width = texture.get_width()
		height = texture.get_height()
	elif width <= 0:
		width = height / maxf(ratio, 0.001)
	elif height <= 0:
		height = width * ratio
	var size := Vector2(width, height) * _IMAGE_SCALE
	if size.x > _width:
		size *= _width / size.x
	return size.round()

func _local() -> bool:
	return not _base.is_empty() and not _base.contains("://")

func _inside(target: String) -> String:
	if not _local():
		return ""
	var path := _base.path_join(target.trim_prefix("./").trim_prefix("/").uri_decode()).simplify_path()
	var root := _base.simplify_path()
	return path if path.begins_with(root.trim_suffix("/") + "/") else ""

func _local_texture(src: String) -> Texture2D:
	if src.is_empty() or not _local() or (src.contains("://") and not src.begins_with("res://")):
		return null
	var path := src if src.begins_with("res://") else _inside(src)
	if path.is_empty():
		return null
	if _local_images.has(path):
		return _local_images[path]
	var texture: Texture2D = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var res := load(path)
		texture = res if res is Texture2D else null
	elif FileAccess.file_exists(path):
		var image := Safety.image(FileAccess.get_file_as_bytes(path))
		if image != null:
			texture = ImageTexture.create_from_image(image)
	if _local_images.size() >= _MAX_CACHED:
		_local_images.clear()
	_local_images[path] = texture
	return texture

func _download(url: String, done: Callable) -> void:
	if _web_images.has(url):
		done.call(_web_images[url])
		return
	var fetch := url.replace("://img.shields.io/", "://raster.shields.io/")
	var request := HTTPRequest.new()
	request.timeout = 15.0
	request.body_size_limit = Safety.MAX_IMAGE_BYTES
	request.ready.connect(func() -> void: request.request(fetch), CONNECT_ONE_SHOT)
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		var texture: Texture2D = _decode(body) if result == HTTPRequest.RESULT_SUCCESS and code < 400 else null
		if _web_images.size() >= _MAX_CACHED:
			_web_images.clear()
		_web_images[url] = texture
		done.call(texture))
	_doc.add_child(request)

static func _decode(body: PackedByteArray) -> Texture2D:
	var image := Safety.image(body)
	return ImageTexture.create_from_image(image) if image != null else null

func _highlight(code: String, lang: String) -> String:
	if lang in ["diff", "patch"]:
		var lines: Array[String] = []
		for line in code.split("\n"):
			var kind := "added" if line.begins_with("+") else "removed" if line.begins_with("-") else "section" if line.begins_with("@@") else ""
			lines.append(_escape(line) if kind.is_empty() else "[color=#%s]%s[/color]" % [_pal.code[kind], _escape(line)])
		return "\n".join(lines)
	if lang in _PLAIN_CODE:
		return _escape(code)
	var hash_comments := lang in _HASH_COMMENTS
	var out := ""
	var last := 0
	var pattern := "(?m)(#[^\\n]*|//[^\\n]*|/\\*[\\s\\S]*?\\*/|\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'|\\b\\d+(?:\\.\\d+)?\\b|\\b[A-Za-z_]\\w*\\b|^[ \\t]*\\[[^\\]\\n]+\\][ \\t]*$)"
	for m in _re(pattern).search_all(code):
		out += _escape(code.substr(last, m.get_start() - last))
		var token := m.get_string(0)
		var kind := ""
		if token.begins_with("#"):
			kind = "comment" if hash_comments else ""
		elif token.begins_with("//") or token.begins_with("/*"):
			kind = "" if hash_comments else "comment"
		elif token.begins_with("\"") or token.begins_with("'"):
			kind = "string"
		elif token[0].is_valid_int():
			kind = "number"
		elif token in _KEYWORDS:
			kind = "keyword"
		elif token.strip_edges().begins_with("["):
			kind = "section"
		out += _escape(token) if kind.is_empty() else "[color=#%s]%s[/color]" % [_pal.code[kind], _escape(token)]
		last = m.get_end()
	return out + _escape(code.substr(last))

func _hover_link(meta: Variant, on: bool) -> void:
	var cursor: Node = GameEvents.active_cursor
	if not is_instance_valid(cursor):
		return
	if _hover_key == null:
		_hover_key = Area2D.new()
	if on:
		var target := str(meta)
		cursor.begin_hover(_hover_key, target if target.contains("://") or target.begins_with("mailto:") else "", true)
	else:
		cursor.end_hover(_hover_key)

func _release_hover() -> void:
	if _hover_key == null:
		return
	if is_instance_valid(GameEvents.active_cursor):
		GameEvents.active_cursor.end_hover(_hover_key)
	_hover_key.free()
	_hover_key = null

func _follow(meta: Variant) -> void:
	var target := str(meta)
	if target.begins_with("#"):
		var heading: Control = _headings.get(target.substr(1).to_lower())
		var scroll := _scroll()
		if heading != null and scroll != null:
			scroll.scroll_vertical = int(heading.global_position.y - _doc.global_position.y)
		return
	if _base.contains("://") and not target.contains("://") and not target.begins_with("mailto:"):
		target = _base.path_join(target.trim_prefix("./").trim_prefix("/"))
	if target.contains("://") or target.begins_with("mailto:"):
		if _open_url.is_valid():
			_open_url.call(target)
		elif target.begins_with("https://") or target.begins_with("http://") or target.begins_with("mailto:"):
			OS.shell_open(target)
		return
	var path := _inside(target.split("#")[0])
	if path.is_empty():
		return
	if path.get_extension().to_lower() in ["md", "markdown", "txt", ""] and FileAccess.file_exists(path):
		_show(FileAccess.get_file_as_string(path), path.get_base_dir())
		var scroll := _scroll()
		if scroll != null:
			scroll.scroll_vertical = 0
	elif DirAccess.dir_exists_absolute(path):
		OS.shell_open(path)

func _scroll() -> ScrollContainer:
	var node := _doc.get_parent()
	while node != null and not node is ScrollContainer:
		node = node.get_parent()
	return node as ScrollContainer

static func _slug(text: String) -> String:
	var plain := _plain(text).to_lower()
	plain = _re("[^\\w _-]").sub(plain, "", true)
	return plain.strip_edges().replace(" ", "-")

static func _font(key: String) -> Font:
	if _fonts.has(key):
		return _fonts[key]
	var font: Font
	match key:
		"base":
			font = load(_BASE_FONT)
		"bold", "italics", "bold_italics":
			var file_name: String = {"bold": "fs-tahoma-8px-bold.ttf", "italics": "fs-tahoma-8px-italic.ttf", "bold_italics": "fs-tahoma-8px-bold-italic.ttf"}[key]
			var bytes := FileAccess.get_file_as_bytes(_FONTS_DIR + file_name)
			if bytes.is_empty():
				font = load(_HEADING_FONT)
			else:
				var file := FontFile.new()
				file.data = bytes
				file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
				file.hinting = TextServer.HINTING_NONE
				file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
				file.fallbacks = load(_BASE_FONT).fallbacks
				font = file
		"mono":
			var bytes := FileAccess.get_file_as_bytes(_MONO_FONT)
			if bytes.is_empty():
				font = load(_MONO_FALLBACK)
			else:
				var file := FontFile.new()
				file.data = bytes
				file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
				file.hinting = TextServer.HINTING_NONE
				file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
				file.fallbacks = [load(_MONO_FALLBACK)]
				font = file
		"heading":
			font = load(_HEADING_FONT)
	_fonts[key] = font
	return font

static func _re(pattern: String) -> RegEx:
	if not _patterns.has(pattern):
		_patterns[pattern] = RegEx.create_from_string(pattern)
	return _patterns[pattern]

static func _matches(pattern: String, line: String) -> bool:
	return _re(pattern).search(line) != null

static func _each(re: RegEx, text: String, replace: Callable) -> String:
	var out := ""
	var last := 0
	for m in re.search_all(text):
		out += text.substr(last, m.get_start() - last) + str(replace.call(m))
		last = m.get_end()
	return out + text.substr(last)
