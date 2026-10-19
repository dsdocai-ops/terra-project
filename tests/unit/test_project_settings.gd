extends GutTest
## Tests for project.godot values from the SPEC-foundation settings table and
## the SPEC-project folder tree. Owned by foundation.

const EXPECTED: Dictionary[String, Variant] = {
	"application/config/name": "Sinkhole",
	"application/run/main_scene": "res://scenes/main/main.tscn",
	"display/window/size/viewport_width": 960,
	"display/window/size/viewport_height": 540,
	"display/window/size/window_width_override": 1920,
	"display/window/size/window_height_override": 1080,
	"display/window/stretch/mode": "canvas_items",
	"display/window/stretch/aspect": "keep",
	"display/window/stretch/scale_mode": "integer",
	"rendering/renderer/rendering_method": "gl_compatibility",
	"rendering/renderer/rendering_method.mobile": "gl_compatibility",
	"rendering/textures/canvas_textures/default_texture_filter": 0,
	"rendering/2d/snap/snap_2d_transforms_to_pixel": true,
	"rendering/2d/snap/snap_2d_vertices_to_pixel": true,
	"physics/common/physics_ticks_per_second": 60,
	# Movement steps at 60 Hz; the renderer draws between ticks. Without
	# interpolation a body moves in uneven steps on any display not locked to
	# 60 Hz while the camera eases every frame, which reads as jitter.
	"physics/common/physics_interpolation": true,
	"debug/gdscript/warnings/untyped_declaration": 2,
	# Ignore, not Warn: the code style uses := everywhere and Warn would flag
	# every one of them (see SPEC-foundation settings table).
	"debug/gdscript/warnings/inferred_declaration": 0,
	"network/limits/debugger/max_chars_per_second": 131072,
}

const FOLDERS: Array[String] = [
	"res://scenes/main", "res://scenes/town", "res://scenes/dungeon", "res://scenes/player",
	"res://scenes/enemies", "res://scenes/bosses", "res://scenes/abilities", "res://scenes/projectiles",
	"res://scenes/pickups", "res://scenes/ui", "res://scenes/dialogue", "res://scenes/network",
	"res://scripts/autoload", "res://scripts/components", "res://scripts/data", "res://scripts/effects",
	"res://scripts/generation", "res://scripts/debug",
	"res://data/characters", "res://data/classes", "res://data/ascensions", "res://data/class_trees",
	"res://data/weapons", "res://data/mutations", "res://data/abilities", "res://data/relics",
	"res://data/synergies", "res://data/enemies", "res://data/bosses", "res://data/biomes",
	"res://data/skills", "res://data/dialogue", "res://data/lore",
	"res://assets/sprites", "res://assets/tilesets", "res://assets/vfx", "res://assets/audio/music",
	"res://assets/audio/sfx", "res://assets/fonts",
	"res://tests/unit", "res://tests/integration", "res://tests/helpers",
	"res://tools", "res://specs",
]

const PHYSICS_LAYERS: Dictionary[int, String] = {
	1: "world", 2: "player", 3: "enemy", 4: "hitbox_player", 5: "hitbox_enemy", 6: "interactable",
}


func test_settings_match_spec_table() -> void:
	for key: String in EXPECTED:
		assert_true(ProjectSettings.has_setting(key), "has %s" % key)
		assert_eq(ProjectSettings.get_setting(key), EXPECTED[key], key)


func test_features_declare_compatibility_renderer_and_version() -> void:
	var features: PackedStringArray = ProjectSettings.get_setting("application/config/features")
	assert_true(features.has("GL Compatibility"), "GL Compatibility feature")
	assert_true(features.has("4.7"), "4.7 feature")


func test_unsafe_warnings_are_enabled_as_warnings() -> void:
	for name: String in ["unsafe_property_access", "unsafe_method_access", "unsafe_cast", "unsafe_call_argument"]:
		assert_eq(ProjectSettings.get_setting("debug/gdscript/warnings/%s" % name), 1, name)


func test_physics_layer_names() -> void:
	for layer: int in PHYSICS_LAYERS:
		assert_eq(ProjectSettings.get_setting("layer_names/2d_physics/layer_%d" % layer), PHYSICS_LAYERS[layer], "layer %d" % layer)


func test_folder_tree_exists() -> void:
	for folder: String in FOLDERS:
		assert_true(DirAccess.dir_exists_absolute(folder), folder)
