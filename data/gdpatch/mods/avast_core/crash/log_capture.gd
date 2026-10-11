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
# grabs every line and error godot logs. keeps the recent ones in memory and writes all of
# them to a session log, so it's still there after a crash.
# godot calls this from any thread!! errors from game or mod code get passed to the main thread.
# release builds dont report most gdscript mistakes, so engine errors coming from script code
# count aswell. a few known harmless ones are ignored

extends Logger

const MAX_LINES := 400
const MAX_ERRORS := 100
const ERROR_NAMES := ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"]

var on_error := Callable()

const IGNORED := ["Not supported by this display server"]

var _mutex := Mutex.new()
var _lines: Array[String] = []
var _errors: Array[Dictionary] = []
var _file: FileAccess

func _init(log_path: String) -> void:
	_file = FileAccess.open(log_path, FileAccess.WRITE)

func _log_message(message: String, error: bool) -> void:
	_add(("ERROR: " if error else "") + message.strip_edges(false, true))

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
		error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var frames: Array[Dictionary] = []
	for backtrace in script_backtraces:
		for i in backtrace.get_frame_count():
			frames.append({
				"function": backtrace.get_frame_function(i),
				"file": backtrace.get_frame_file(i),
				"line": backtrace.get_frame_line(i),
			})
	var record := {
		"time": Time.get_datetime_string_from_system(false, true),
		"type": error_type,
		"message": rationale if not rationale.is_empty() else code,
		"code": code,
		"function": function,
		"file": file,
		"line": line,
		"frames": frames,
	}
	var text := "%s: %s\n   at: %s (%s:%d)" % [ERROR_NAMES[clampi(error_type, 0, 3)], record.message, function, file, line]
	for i in frames.size():
		text += "\n   [%d] %s (%s:%d)" % [i, frames[i].function, frames[i].file, frames[i].line]
	if _mutex.try_lock():
		_errors.append(record)
		if _errors.size() > MAX_ERRORS:
			_errors.pop_front()
		_mutex.unlock()
	_add(text)
	var from_code := error_type == ERROR_TYPE_SCRIPT or (error_type == ERROR_TYPE_ERROR and (not frames.is_empty() or file.begins_with("res://")))
	if from_code and on_error.is_valid() and not IGNORED.any(func(text: String) -> bool: return record.message.contains(text)):
		on_error.call_deferred(record)

func lines(count: int = MAX_LINES) -> Array[String]:
	_mutex.lock()
	var out := _lines.slice(maxi(0, _lines.size() - count))
	_mutex.unlock()
	return out

func errors() -> Array[Dictionary]:
	_mutex.lock()
	var out := _errors.duplicate(true)
	_mutex.unlock()
	return out

func add_line(text: String) -> void:
	_add(text)

func close() -> void:
	_mutex.lock()
	if _file != null:
		_file.close()
		_file = null
	_mutex.unlock()

func _add(text: String) -> void:
	var stamped := "%s %s" % [Time.get_time_string_from_system(), text]
	if not _mutex.try_lock():
		if _file != null:
			_file.store_line(stamped)
			_file.flush()
		return
	_lines.append(stamped)
	if _lines.size() > MAX_LINES:
		_lines.pop_front()
	if _file != null:
		_file.store_line(stamped)
		_file.flush()
	_mutex.unlock()
