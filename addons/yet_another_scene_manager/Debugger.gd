extends Node

class LogMessage extends RefCounted:
  enum Level {
    Message,
    Warning,
    Error,
    Critical
  }
  var level: Level
  var message: String

  func _init(log_level: Level, log_message: String):
    self.level = log_level
    self.message = log_message

  func _to_string():
    match level:
      Level.Message:
        return message
      Level.Warning:
        return "[WRN] " + message
      Level.Error:
        return "[ERR] " + message
      Level.Critical:
        return "!CRI! " + message
    return "{???} " + message

var logs: Array[LogMessage] = []

func log_generic(level: LogMessage.Level, message: String) -> int:
  logs.append(LogMessage.new(level, message))
  return logs.size() - 1

func log_message(message: String) -> int:
  var id := log_generic(LogMessage.Level.Message, message)
  print(logs[id].to_string())
  new_log.emit(id)
  return id

func log_warning(message: String) -> int:
  var id := log_generic(LogMessage.Level.Warning, message)
  push_warning(logs[id].to_string())
  new_log.emit(id)
  return id

func log_error(message: String, show_alert := false) -> int:
  var id := log_generic(LogMessage.Level.Error, message)
  push_error(logs[id].to_string())
  new_log.emit(id)
  if show_alert:
    OS.alert(message, str(ProjectSettings.get_setting("application/config/name", "???")) + ": An error occurred")
  return id

func log_critical(message: String):
  var id := log_generic(LogMessage.Level.Critical, message)
  push_error(logs[id].to_string())
  new_log.emit(id)
  if not OS.has_feature("Server"):
    OS.alert(message, "Critical failure!")
  if EngineDebugger.is_active():
    breakpoint

  OS.kill(OS.get_process_id())
  log_critical("{Failed to kill process; killing through infinite recursion}")

func get_log(id: int) -> LogMessage:
  return logs[id] if id < logs.size() else null

func get_recent_logs_as_string(count: int, include_id := false, bbcode := false) -> String:
  var log_str := ""
  var format_line_number: Callable
  var format_line: Callable
  if include_id:
    format_line_number = func (line: int) -> String: return "[" + str(line).pad_zeros(5) + "] "
  else:
    format_line_number = func (_line: int) -> String: return ""
  if bbcode:
    format_line = func (line: int, log_msg: String) -> String:
      var bbcode_index := 0
      match log_msg.substr(0, 5):
        "[WRN]":
          bbcode_index = 1
        "[ERR]":
          bbcode_index = 2
        "!CRI!":
          bbcode_index = 3
      const OPEN_BBCODE: PackedStringArray = ["", "[color=yellow]", "[color=red]", "[color=red][shake]"]
      const CLOSE_BBCODE: PackedStringArray = ["", "[/color]", "[/color]", "[/shake][/color]"]
      return "{0}{1}{2}{3}".format([format_line_number.call(line), OPEN_BBCODE[bbcode_index], log_msg, CLOSE_BBCODE[bbcode_index]])
  else:
    format_line = func (line: int, log_msg: String) -> String: return format_line_number.call(line) + log_msg
  if count == -1:
    count = logs.size()
  for i in range(logs.size() - count, logs.size()):
    if not log_str.is_empty():
      log_str += "\n"
    log_str += format_line.call(i, get_log(i).to_string())
  return log_str

# Emitted when any message is logged. Contains the `id` of that message within `logs`
signal new_log(id: int)
