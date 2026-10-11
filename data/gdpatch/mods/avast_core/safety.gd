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
# checks for everything coming from outside the players computer: the AVaSt server, github,
# the update servers mods point at, and the zips and images all of them send.
#
# installing a mod runs its code from the next start anyway, so this guards whats before that:
# looking at a mod page (icon, banner, readme, notes) and where an install is allowed to write.
# image sizes are read from the header before decoding, a tiny file can claim a giant picture

extends RefCounted

const ID := "^[a-z0-9_]{2,40}$"
const VERSION := "^[0-9A-Za-z.+-]{1,32}$"
const REPO := "^(?:[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}|/v1/t/[a-z0-9_]{2,40})$"

const MAX_SIDE := 2048
const MAX_IMAGE_BYTES := 4 * 1024 * 1024
const MAX_TEXT := 256 * 1024
const MAX_ZIP_FILES := 10000
const MAX_ZIP_FILE := 128 * 1024 * 1024
const MAX_ZIP_BYTES := 512 * 1024 * 1024

const IMAGE_HOSTS := [
	"raw.githubusercontent.com", "github.com", "user-images.githubusercontent.com",
	"private-user-images.githubusercontent.com", "camo.githubusercontent.com", "avatars.githubusercontent.com",
	"img.shields.io", "raster.shields.io", "i.imgur.com",
]

static var _hosts := {}
static var _patterns := {}

static func is_id(text: Variant) -> bool:
	return text is String and _re(ID).search(text) != null

static func is_version(text: Variant) -> bool:
	return text is String and _re(VERSION).search(text) != null

static func is_repo(text: Variant) -> bool:
	return text is String and _re(REPO).search(text) != null

static func is_secure_url(link: String) -> bool:
	if link.begins_with("https://"):
		return not host(link).is_empty()
	return link.begins_with("http://127.0.0.1:") or link.begins_with("http://127.0.0.1/") or link.begins_with("http://localhost:")

static func host(link: String) -> String:
	var at := link.find("://")
	if at < 0:
		return ""
	var rest := link.substr(at + 3)
	for stop in ["/", "?", "#", "\\"]:
		rest = rest.get_slice(stop, 0)
	rest = rest.get_slice("@", rest.count("@"))
	return rest.get_slice(":", 0).to_lower()

static func allow_host(link: String) -> void:
	if not host(link).is_empty():
		_hosts[host(link)] = true

static func is_image_url(link: String) -> bool:
	return is_secure_url(link) and (host(link) in IMAGE_HOSTS or _hosts.has(host(link)))

static func image(bytes: PackedByteArray, max_side: int = MAX_SIDE) -> Image:
	if bytes.size() > MAX_IMAGE_BYTES:
		return null
	var jpeg := false
	var size := _png_size(bytes)
	if size == Vector2i.ZERO:
		size = _jpg_size(bytes)
		jpeg = true
	if size.x <= 0 or size.y <= 0 or size.x > max_side or size.y > max_side:
		return null
	var picture := Image.new()
	var error := picture.load_jpg_from_buffer(bytes) if jpeg else picture.load_png_from_buffer(bytes)
	if error != OK or picture.get_width() != size.x or picture.get_height() != size.y:
		return null
	return picture

static func _png_size(bytes: PackedByteArray) -> Vector2i:
	if bytes.size() < 24 or bytes.slice(0, 8) != PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) \
			or bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
		return Vector2i.ZERO
	return Vector2i(_u32_be(bytes, 16), _u32_be(bytes, 20))

static func _jpg_size(bytes: PackedByteArray) -> Vector2i:
	if bytes.size() < 4 or bytes[0] != 0xFF or bytes[1] != 0xD8:
		return Vector2i.ZERO
	var i := 2
	while i + 9 < bytes.size():
		if bytes[i] != 0xFF:
			return Vector2i.ZERO
		var marker := bytes[i + 1]
		if marker == 0xFF:
			i += 1
			continue
		if marker == 0x01 or (marker >= 0xD0 and marker <= 0xD8):
			i += 2
			continue
		if marker >= 0xC0 and marker <= 0xCF and not marker in [0xC4, 0xC8, 0xCC]:
			return Vector2i((bytes[i + 7] << 8) | bytes[i + 8], (bytes[i + 5] << 8) | bytes[i + 6])
		if marker == 0xD9 or marker == 0xDA:
			return Vector2i.ZERO
		i += 2 + ((bytes[i + 2] << 8) | bytes[i + 3])
	return Vector2i.ZERO

static func _u32_be(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]

static func zip_problem(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	var end := -1
	for i in range(bytes.size() - 22, maxi(bytes.size() - 65558, -1), -1):
		if bytes.decode_u32(i) == 0x06054b50:
			end = i
			break
	if end < 0:
		return "The download isn't a zip file."
	var count := bytes.decode_u16(end + 10)
	if count > MAX_ZIP_FILES:
		return "The zip has more than %d files." % MAX_ZIP_FILES
	var at := bytes.decode_u32(end + 16)
	var total := 0
	for _entry in count:
		if at + 46 > bytes.size() or bytes.decode_u32(at) != 0x02014b50:
			return "The zip is damaged."
		var size := bytes.decode_u32(at + 24)
		if size > MAX_ZIP_FILE:
			return "A file in the zip is bigger than %d MB." % (MAX_ZIP_FILE / 1048576)
		total += size
		if total > MAX_ZIP_BYTES:
			return "The zip unpacks to more than %d MB." % (MAX_ZIP_BYTES / 1048576)
		at += 46 + bytes.decode_u16(at + 28) + bytes.decode_u16(at + 30) + bytes.decode_u16(at + 32)
	return ""

static func is_zip_path(rel: String) -> bool:
	return not rel.is_empty() and not rel.ends_with("/") and not rel.begins_with("/") and not rel.contains("\\") \
		and not rel.contains(":") and not rel.split("/").has("..") and not rel.split("/").has(".")

static func text(value: String) -> String:
	if value.length() > MAX_TEXT:
		value = value.substr(0, MAX_TEXT)
	for c in ["", "", "", ""]:
		value = value.replace(c, "")
	return value

static func _re(pattern: String) -> RegEx:
	if not _patterns.has(pattern):
		_patterns[pattern] = RegEx.create_from_string(pattern)
	return _patterns[pattern]
