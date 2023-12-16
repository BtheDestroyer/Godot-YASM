# ![Icon](https://raw.githubusercontent.com/BtheDestroyer/Godot-YASM/main/addons/yet_another_scene_manager/icon.svg) Yet Another Scene Manager

Add-on for Godot 4 which aids in loading scenes asynchronously (aka: in the background) which allows for animated/interactable loading screens and transition animations.

## Usage

First, add the `res://addons` folder of this repository to your project and enable the plugin in your Project Settings.

From there, you can access the autoload singleton by the name `YASM`. Eg: `YASM.load_scene("res://my_cool_level.tscn")`

This plugin comes with a default "loading" scene, but you can set your own by modifying the "application/scenes/loading_scene_path" Project Setting.

### Pre-load Signals

If you would like to `await` specific `Signal`(s) before switching to a scene after loading it, you can provide it/them in an optional `Array` to `YASM.load_scene(...)`

This is useful if you'd like to wait for all players to be ready in an online game or to allow the player to stay on the "loading" screen until they're ready.

For example, your loading screen may be a playable mini-game or training room where players could opt to stay and play/practice. It could also features lore or tutorials/hints which your player may want to be able to read for longer.

```
# Load instantly
YASM.load_scene("res://overworld.tscn")
# Same as above
YASM.load_scene("res://overworld.tscn", [])
# Wait for a minimum of 5 seconds before finishing loading
YASM.load_scene("res://overworld.tscn", [get_tree().create_timer(5.0).timeout])
# Wait for a custom 'player_ready' signal in a custom loading scene
YASM.load_scene("res://overworld.tscn", [YASM._loading_scene.player_ready])
# Wait for a custom 'player_ready' signal in a custom loading scene
YASM.load_scene("res://overworld.tscn", [get_tree().create_timer(5.0).timeout, YASM._loading_scene.player_ready])

# Start loading with no extra condition...
YASM.load_scene("res://overworld.tscn")
# ...then the player presses the "stay in mini-game" button
YASM.await_additional_signal_for_load(YASM._loading_scene.player_ready)
```

### Transitions

Scene transitions are handled via Godot's `Animation`s on two `AnimationPlayers` within the `YASM` singleton.

To play a scene transition, first create your "out" and "in" `Animaiton`s in an `AnimationLibrary` (or two separate ones if you'd like to keep them organized).

"Out" `Animation`s are run on the old scene being unloaded while "in" `Animation`s are run on the newly loaded scene. As such, your "out" `Animation`s should modify the properties of a `Sprite2D` called "OldScene" and your "in" `Animation`s should modify the properties of a `Sprite2D` called "NewScene".

Once you've created your transitions, you can call `YASM.set_default_animation_libraries(...)` to provide your `AnimationLibrary`(s) to `YASM` and set `YASM.scene_out_transition` and `YASM.scene_in_transition` to the `Animation` name you'd like to use for each.

The transition animations can be set once at the start of your game and they will always be re-used or you can manually adjust them for different methods of scene transition (eg: opening a door vs walking off screen).

### Available Signals

If you would like your code to react to different phases of loading a scene (eg: a multiplayer game would like to tell the server when a player is loaded), the following signals are available in `YASM`:

- `out_transition_done`: Emitted after the previous scene's "out" transition is done (or during `load_scene` if there is no "out" transition)

- `preload_done`: Emitted when resource loading is complete, but before all awaited signals are emitted or the new scene is instantiated

- `load_done`: Emitted after the new scene is instantiated

- `in_transition_done`: Emitted after the new scene's "in" transition is done (or immediately after `load_done` if there is no "in" transition set)

### Cancelling a Load

If something goes wrong while doing some manual work during the loading of a scene, you can call `YASM.cancel_scene_load()` (after optionally setting `YASM.last_error`) to immediately cancel loading the next scene and go to the "error" scene instead. A default "error" scene is provided with this plugin, but you can also make your own and provide the file path as "application/scenes/error_scene_path" in your Project Settings.

This can be useful if in an online multiplayer game the server disconnected during loading or if a scene was being procedurally generated and something failed.
