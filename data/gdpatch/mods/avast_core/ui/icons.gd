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
# AVaSt's own little icons, the pngs in assets/icons. white glyphs with a soft shadow for the
# colored buttons (download, update, power, trash, undo...) and the two arrow triangles,
# those get tinted with the themes text color wherever they're used

extends RefCounted

const _DIR := "res://gdpatch/mods/avast_core/assets/icons/"

static var _cache := {}

static func texture(name: String) -> Texture2D:
	if not _cache.has(name):
		var image := Image.new()
		var loaded := image.load_png_from_buffer(FileAccess.get_file_as_bytes(_DIR + name + ".png"))
		_cache[name] = ImageTexture.create_from_image(image) if loaded == OK else null
	return _cache[name]

static func arrow(direction: String) -> Texture2D:
	return texture("arrow_" + direction)
