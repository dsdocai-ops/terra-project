class_name World
extends Node2D
## The Y-sorted gameplay root: tile layers, entity containers, camera, FX.
## Owned by foundation. Sync: loaded identically on every peer; nothing here
## holds game state. Players, enemies, pickups spawn under the containers
## through networking's MultiplayerSpawners.
##
## Other modules reach these nodes through GameState.world, never by path.

## Paints a square test floor on ready so week 1 has somewhere to walk.
## floor-generation turns this off when it starts painting real floors.
@export var debug_test_floor: bool = true
@export var debug_test_floor_size: int = 20

@onready var floor_layer: TileMapLayer = $Floor
@onready var walls_layer: TileMapLayer = $Walls
@onready var entities: Node2D = $Entities
@onready var players: Node2D = $Players
@onready var camera: Camera2D = $Camera
@onready var fx: Node2D = $FX


func _ready() -> void:
	if debug_test_floor:
		paint_test_floor(debug_test_floor_size)


## Clears both layers, paints a `size` x `size` floor from (0, 0) and a one
## tile wall ring around it.
func paint_test_floor(size: int) -> void:
	floor_layer.clear()
	walls_layer.clear()
	for x in size:
		for y in size:
			floor_layer.set_cell(Vector2i(x, y), Tiles.SOURCE, Tiles.FLOOR)
	for i in range(-1, size + 1):
		walls_layer.set_cell(Vector2i(i, -1), Tiles.SOURCE, Tiles.WALL)
		walls_layer.set_cell(Vector2i(i, size), Tiles.SOURCE, Tiles.WALL)
	for i in size:
		walls_layer.set_cell(Vector2i(-1, i), Tiles.SOURCE, Tiles.WALL)
		walls_layer.set_cell(Vector2i(size, i), Tiles.SOURCE, Tiles.WALL)


## True when the cell has a floor tile flagged walkable and no wall on top.
func is_walkable(tile: Vector2i) -> bool:
	if walls_layer.get_cell_source_id(tile) != -1:
		return false
	var data := floor_layer.get_cell_tile_data(tile)
	return data != null and bool(data.get_custom_data(Tiles.WALKABLE))
