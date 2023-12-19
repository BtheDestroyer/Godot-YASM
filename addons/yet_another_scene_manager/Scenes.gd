# Written by Bryce Dixon
# Released under the MIT License
# Special thanks to "TheDex" (https://github.com/AnidemDex) for helping solve some memory leak issues
@icon("./icon.svg")
extends Node

## Useful for debugging. Stores the last provided path to `load_scene`.
var last_loaded_path: String
## Useful for debugging. Stores the last generated error message.
var last_error: String
var _path_being_loaded: String
var _awaited_signals: Array[Signal] = []
var _awaited_signal_handlers: Array[Callable] = []
var _preload_emitted := false
const Debugger := preload("./Debugger.gd")
const DummyDebugger := preload("./DummyDebugger.gd")
## Useful for debugging. Has nice functions and stores a list of log messages. Disabled in non-debug builds.
@onready var debugger = Debugger.new() if OS.is_debug_build() else DummyDebugger.new()
@onready var tree := get_tree()
@onready var root := tree.get_root()
@onready var _current_scene := tree.current_scene
@onready var _main_scene_path: String = ProjectSettings.get_setting("application/run/main_scene")
@onready var _loading_scene_path: String = ProjectSettings.get_setting("application/scenes/loading_scene_path", "")
@onready var _error_scene_path: String = ProjectSettings.get_setting("application/scenes/error_scene_path")
var _loading_scene: Node
@onready var scene_out_animation_player := AnimationPlayer.new()
@onready var scene_in_animation_player := AnimationPlayer.new()
@onready var _old_scene_viewport := SubViewport.new()
@onready var _new_scene_viewport := SubViewport.new()
@onready var _old_scene_sprite := Sprite2D.new()
@onready var _new_scene_sprite := Sprite2D.new()
var scene_out_transition: String:
  set(value):
    if not value.is_empty() and not scene_out_animation_player.has_animation(value):
      debugger.log_error("[YASM] Missing 'out' animation of name: " + value)
      return
    scene_out_transition = value
var scene_in_transition: String:
  set(value):
    if not value.is_empty() and not scene_in_animation_player.has_animation(value):
      debugger.log_error("[YASM] Missing 'in' animation of name: " + value)
      return
    scene_in_transition = value

## Removes an AnimationLibrary from both scene transition AnimationPlayers of the given name (if it exists)
func remove_animation_libraries(library_name: String):
  if scene_out_animation_player.has_animation_library(library_name):
    scene_out_animation_player.remove_animation_library(library_name)
  if scene_in_animation_player.has_animation_library(library_name):
    scene_in_animation_player.remove_animation_library(library_name)

## Adds (or replaces) an AnimationLibrary of the given name from both scene transition AnimationPlayers
func add_animation_libraries(library_name: String, out_transitions: AnimationLibrary, in_transitions := out_transitions):
  remove_animation_libraries(library_name)
  scene_out_animation_player.add_animation_library(library_name, out_transitions)
  scene_in_animation_player.add_animation_library(library_name, in_transitions)

## Adds (or replaces) the default AnimationLibrary of the given name from both scene transition AnimationPlayers
func set_default_animation_libraries(out_transitions: AnimationLibrary, in_transitions := out_transitions):
  add_animation_libraries("", out_transitions, in_transitions)

func _ready():
  add_child(scene_out_animation_player)
  scene_out_animation_player.animation_finished.connect(func(_x): out_transition_done.emit())
  add_child(scene_in_animation_player)
  scene_in_animation_player.animation_finished.connect(func(_x): in_transition_done.emit())
  if not _loading_scene_path.is_empty():
    var loading_packed_scene := load(_loading_scene_path)
    if not is_instance_valid(loading_packed_scene):
      debugger.log_critical("[YASM] Failed to load 'loading' packed scene!")
    _loading_scene = loading_packed_scene.instantiate()
    if not is_instance_valid(_loading_scene):
      debugger.log_critical("[YASM] Failed to instantiate 'loading' scene!")
    add_child(_loading_scene)
    if not _loading_scene.has_method("set_visible"):
      debugger.log_critical("[YASM] Can't manage visibility of 'loading' scene!")
    _loading_scene.set_visible(false)
    _loading_scene.process_mode = Node.PROCESS_MODE_DISABLED
  add_child(_old_scene_viewport)
  _old_scene_viewport.size = get_viewport().get_visible_rect().size
  _old_scene_viewport.own_world_3d = true
  _old_scene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
  add_child(_new_scene_viewport)
  _new_scene_viewport.size = get_viewport().get_visible_rect().size
  _new_scene_viewport.own_world_3d = true
  _new_scene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
  add_child(_old_scene_sprite)
  _old_scene_sprite.name = "OldScene"
  _old_scene_sprite.set_visible(false)
  _old_scene_sprite.texture = _old_scene_viewport.get_texture()
  _old_scene_sprite.position = _old_scene_sprite.texture.get_size() * 0.5
  add_child(_new_scene_sprite)
  _new_scene_sprite.name = "NewScene"
  _new_scene_sprite.set_visible(false)
  _new_scene_sprite.texture = _new_scene_viewport.get_texture()
  _new_scene_sprite.position = _old_scene_sprite.texture.get_size() * 0.5

func _exit_tree():
  _clean_up_loading_data()

## Used to track when awaited Signals are emitted while a scene is loading.
func _handle_signal(source_signal: Signal):
  _awaited_signals.erase(source_signal)

## Calls `queue_free()` on the 'current' scene (if one exists) and sets the 'current' scene to `null`.
func free_current_scene():
  if is_instance_valid(_current_scene) and not _current_scene.is_queued_for_deletion():
    _current_scene.queue_free()
  _current_scene = null

## Sets the "current" scene. Used internally.
func _set_current_scene(new_scene: Node):
  free_current_scene()
  if not root.is_node_ready():
    await root.ready
  if new_scene.get_parent() == null:
    root.add_child(new_scene)
  else:
    new_scene.reparent(root)
  _current_scene = new_scene

## Asyncronously loads a given PackedScene path. Optionally, will also await for a provided list of Signals before instantiating the scene.
func load_scene(path: String, awaited_signals: Array[Signal] = []):
  if path != _error_scene_path:
    last_loaded_path = path
  if is_loading():
    debugger.log_warning("[YASM] Attempted to load scene while another load is already in-progress.")
    await out_transition_done
  debugger.log_message("[YASM] Loading scene: " + path)
  if is_instance_valid(_loading_scene):
    debugger.log_message("[YASM] Making _loading_scene visible")
    _loading_scene.set_visible(true)
    _loading_scene.process_mode = Node.PROCESS_MODE_PAUSABLE
  if not scene_out_transition.is_empty():
    debugger.log_message("[YASM] Animating out...")
    _old_scene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _old_scene_sprite.set_visible(true)
    if _current_scene:
      debugger.log_message("[YASM] Moving current scene to old_scene_viewport...")
      _old_scene_sprite.visible = true
      RenderingServer.render_loop_enabled = false
      _current_scene.reparent(_old_scene_viewport)
      get_tree().process_frame.connect(RenderingServer.set_render_loop_enabled.bind(true), CONNECT_ONE_SHOT)
    if is_instance_valid(_loading_scene):
      debugger.log_message("[YASM] Playing out transition...")
      scene_out_animation_player.play(scene_out_transition)
      awaited_signals.append(scene_out_animation_player.animation_finished)
    else:
      debugger.log_message("[YASM] Prepping out transition for simultaneous playback...")
      scene_out_animation_player.play(scene_out_transition, -1, 0.0)
      scene_out_animation_player.stop()
      load_done.connect(func():
        debugger.log_message("[YASM] Playing out transition...")
        scene_out_animation_player.play()
        , CONNECT_ONE_SHOT)
    var old_scene := _current_scene
    scene_out_animation_player.animation_finished.connect(func(_x):
      _old_scene_sprite.set_visible(false)
      _old_scene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
      if is_instance_valid(old_scene):
        old_scene.queue_free()
      out_transition_done.emit()
      , CONNECT_ONE_SHOT)
  else:
    out_transition_done.emit()
    free_current_scene()
  _path_being_loaded = path
  match ResourceLoader.load_threaded_request(path, "PackedScene"):
    OK:
      pass
    var error:
      last_error = "Request to load scene on another thread failed! Error: " + error_string(error)
      debugger.log_error("[YASM] " + last_error + "\nScene path: `" + path + "`")
      cancel_scene_load()
      return
  _preload_emitted = false
  _awaited_signals.clear()
  debugger.log_message("[YASM] Awaiting {0} signal(s)".format([awaited_signals.size()]))
  if awaited_signals.size() > 0:
    for needed_signal in awaited_signals:
      await_additional_signal_for_load(needed_signal)

## Adds signal to the list necessary to finish loading. Will have no effect if not currently loading a scene
func await_additional_signal_for_load(new_signal: Signal):
  if _awaited_signals.has(new_signal):
    debugger.log_warning("[YASM] Awaiting the same signal multiple times will not have the intended effect")
    return
  _awaited_signals.append(new_signal)
  _awaited_signal_handlers.append(func(_a = null, _b = null, _c = null, _d = null, _e = null): _handle_signal(new_signal))
  new_signal.connect(_awaited_signal_handlers.back(), CONNECT_ONE_SHOT)

## Cancels the current scene load and loads the "error scene" instead.
func cancel_scene_load():
  debugger.log_message("[YASM] Scene load cancelled")
  if _path_being_loaded in [_error_scene_path, _loading_scene_path]:
    # Panic backup; we're cancelling loading the main menu so something may have gone wrong
    debugger.log_warning("[YASM] Cancelling loading the error or loading scene means something likely went wrong; instantiating it directly")
    var error_scene: Node = load(_error_scene_path).instantiate()
    if error_scene == null:
      debugger.log_critical("[YASM] Failed to change to error scene!")
    _set_current_scene(error_scene)
    debugger.log_message("[YASM] Returned to error scene")
    return
  _clean_up_loading_data()
  load_scene(_error_scene_path)

## Returns `true` if a scene is currently being loaded.
func is_loading() -> bool:
  return not _path_being_loaded.is_empty()

## Returns the scene file path currently being loaded.
func get_current_path_being_loaded() -> String:
  return _path_being_loaded

## Returns `true` if there are signals being `await`ed on before `load_done` is emitted.
func is_loading_waiting_for_signals():
  return _awaited_signals.size() > 0

## Called after `preload_done` and all awaited signals are emitted. Called internally.
func _instantiate_loaded_scene():
  if not is_loading():
    last_error = "No load was being performed when _instantiate_loaded_scene() was called"
    debugger.log_error("[YASM] " + last_error)
    return
  var loaded_scene := ResourceLoader.load_threaded_get(_path_being_loaded)
  _path_being_loaded = ""
  var new_scene: Node = loaded_scene.instantiate()
  load_done.emit()
  if not scene_in_transition.is_empty():
    _new_scene_viewport.add_child(new_scene)
    _new_scene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    debugger.log_message("[YASM] Playing in transition...")
    scene_in_animation_player.play(scene_in_transition)
    # Ensures the Sprite2D has been moved before showing it
    await get_tree().process_frame
    _new_scene_sprite.set_visible(true)
    await scene_in_animation_player.animation_finished
    _new_scene_sprite.set_visible(false)
    _new_scene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
  else:
    in_transition_done.emit()
  if is_instance_valid(_loading_scene):
    _loading_scene.set_visible(false)
    _loading_scene.process_mode = Node.PROCESS_MODE_DISABLED
  _set_current_scene(new_scene)
  _clean_up_loading_data()

## Cleans up potentially hanging data. Called internally.
func _clean_up_loading_data():
  debugger.log_message("[YASM] Cleaning up loading data...")
  if is_loading():
    match ResourceLoader.load_threaded_get_status(_path_being_loaded):
      ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, ResourceLoader.THREAD_LOAD_FAILED:
        pass
      ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_IN_PROGRESS:
        ResourceLoader.load_threaded_get(_path_being_loaded) # cast to the aether
    _path_being_loaded = ""
  for needed_signal in _awaited_signals:
    for handler in _awaited_signal_handlers:
      if needed_signal.is_connected(handler):
        needed_signal.disconnect(handler)
        break
  _awaited_signals.clear()
  _awaited_signal_handlers.clear()
  debugger.log_message("[YASM] All clean")

func _process(_delta):
  if is_loading():
    match ResourceLoader.load_threaded_get_status(_path_being_loaded):
      ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
        debugger.log_warning("[YASM] Scenes thought it was loading the following path when no scene was being loaded: " + _path_being_loaded)
        _path_being_loaded = ""
      ResourceLoader.THREAD_LOAD_FAILED:
        debugger.log_error("[YASM] ResourceLoader failed to load the following scene: " + _path_being_loaded)
        last_error = "ResourceLoader failed to load the scene"
        cancel_scene_load()
      ResourceLoader.THREAD_LOAD_IN_PROGRESS:
        pass
      ResourceLoader.THREAD_LOAD_LOADED:
        if not _preload_emitted:
          preload_done.emit()
          _preload_emitted = true
        if not is_loading_waiting_for_signals():
          _instantiate_loaded_scene()

## Returns the 'current' scene or `null` if there is no 'current' scene
func get_current_scene() -> Node:
  if not is_instance_valid(_current_scene):
    _current_scene = null
  return _current_scene

## Emitted after scene 'out' transition (during `load_scene(...)` with no 'out' transition set)
signal out_transition_done()
## Emitted when resource loading is complete before scene instantiation
signal preload_done()
## Emitted after scene instantiation
signal load_done()
## Emitted after scene 'in' transition (immediately after `load_done` with no 'in' transition set)
signal in_transition_done()
