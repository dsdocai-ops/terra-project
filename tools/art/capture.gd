extends SceneTree
## In-engine review screenshot (SPEC-art-audio): builds a small test room from the
## real tileset, scenes and sprites and saves the viewport to a PNG.
##   godot --path . -s tools/art/capture.gd -- <out.png>
## Needs a window (not --headless): the headless renderer draws nothing.

const WORLD_SCENE := "res://scenes/main/world.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const PROPS: Array[Dictionary] = [
	{"scene": "res://scenes/dungeon/interactables/chest.tscn", "cell": Vector2i(2, 2)},
	{"scene": "res://scenes/dungeon/interactables/shrine.tscn", "cell": Vector2i(5, 2)},
	{"scene": "res://scenes/dungeon/interactables/rope.tscn", "cell": Vector2i(2, 5)},
	{"scene": "res://scenes/dungeon/interactables/breakable.tscn", "cell": Vector2i(6, 5)},
	{"scene": "res://scenes/dungeon/interactables/mining_node.tscn", "cell": Vector2i(4, 6)},
	{"scene": "res://scenes/pickups/pickup.tscn", "cell": Vector2i(3, 3)},
]

var _out_path: String = "user://capture.png"
## Second user arg: the biome whose tileset to show (default collapsed_mines).
var _biome: String = "collapsed_mines"
## Third user arg: comma separated enemy ids to line up on the floor.
var _enemies: PackedStringArray = PackedStringArray()
var _frames: int = 0
var _world: Node2D


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_path = args[0]
	if args.size() > 1:
		_biome = args[1]
	if args.size() > 2:
		_enemies = args[2].split(",")


func _build() -> void:
	_world = (load(WORLD_SCENE) as PackedScene).instantiate() as Node2D
	root.add_child(_world)
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(960, 540)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var floor_layer := _world.get_node("Floor") as TileMapLayer
	var walls := _world.get_node("Walls") as TileMapLayer
	var tiles_path: String = "res://assets/tilesets/placeholder_iso.tres" if _biome == "collapsed_mines" else "res://assets/tilesets/%s_iso.tres" % _biome
	floor_layer.tile_set = load(tiles_path) as TileSet
	walls.tile_set = floor_layer.tile_set
	for x: int in range(-1, 9):
		for y: int in range(-1, 9):
			var edge: bool = x == -1 or y == -1 or x == 8 or y == 8
			if edge:
				walls.set_cell(Vector2i(x, y), Tiles.SOURCE, Tiles.WALL)
			elif x == 7 and y == 7:
				floor_layer.set_cell(Vector2i(x, y), Tiles.SOURCE, Tiles.PIT)
			else:
				floor_layer.set_cell(Vector2i(x, y), Tiles.SOURCE, Tiles.FLOOR)
	var entities: Node2D = _world.get_node("Entities")
	for prop: Dictionary in PROPS:
		var node := (load(prop["scene"] as String) as PackedScene).instantiate() as Node2D
		node.position = floor_layer.map_to_local(prop["cell"] as Vector2i)
		entities.add_child(node)
	for index: int in _enemies.size():
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = load("res://assets/sprites/enemies/%s_frames.tres" % _enemies[index]) as SpriteFrames
		sprite.position = floor_layer.map_to_local(Vector2i(1 + index, 1 + index % 3)) + Vector2(0, -20)
		entities.add_child(sprite)
		sprite.play(&"walk_s")
	var camera := Camera2D.new()
	camera.position = floor_layer.map_to_local(Vector2i(4, 4))
	_world.add_child(camera)
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Node2D
	player.position = floor_layer.map_to_local(Vector2i(4, 4))
	_world.get_node("Players").add_child(player)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_build()
	if _frames == 25:
		var image: Image = root.get_texture().get_image()
		image.save_png(_out_path)
		print("captured %s" % _out_path)
		quit()
	return false
