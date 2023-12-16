@tool
extends EditorPlugin

func _enter_tree():
  add_autoload_singleton("YASM", "Scenes.gd")
  if ProjectSettings.get_setting("application/scenes/loading_scene_path") == null:
    ProjectSettings.set_setting("application/scenes/loading_scene_path", "res://addons/yet_another_scene_manager/Scenes/Loading.tscn")
  if ProjectSettings.get_setting("application/scenes/error_scene_path") == null:
    ProjectSettings.set_setting("application/scenes/error_scene_path", "res://addons/yet_another_scene_manager/Scenes/Error.tscn")

func _exit_tree():
  remove_autoload_singleton("YASM")
