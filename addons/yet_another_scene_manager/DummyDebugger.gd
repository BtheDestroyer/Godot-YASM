extends Node

const Debugger := preload("./Debugger.gd")

func log_generic(_level: Debugger.LogMessage.Level, _message: String) -> int:
  return 0

func log_message(_message: String) -> int:
  return 0

func log_warning(_message: String) -> int:
  return 0

func log_error(_message: String, _show_alert := false) -> int:
  return 0

func log_critical(message: String):
  push_error(message)
  if not OS.has_feature("Server"):
    OS.alert(message, "Critical failure!")
  if EngineDebugger.is_active():
    breakpoint

  OS.kill(OS.get_process_id())
  log_critical("{Failed to kill process; killing through infinite recursion}")

func get_log(_id: int) -> Debugger.LogMessage:
  return null

func get_recent_logs_as_string(_count: int, _include_id := false, _bbcode := false) -> String:
  return ""

## Never emitted
signal new_log(id: int)
