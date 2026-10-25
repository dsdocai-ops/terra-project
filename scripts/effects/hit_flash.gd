class_name HitFlash
extends Node
## Whole-sprite hit flash (SPEC-combat-core "Hit feedback"): puts the
## hit_flash.gdshader material on its target canvas items and ramps the overlay
## from full to nothing over a few physics frames. Owned by combat-core. Sync:
## none, purely local presentation; `CombatFeedback` calls `flash` on every
## peer from the replicated feedback RPC. Deliberately ignores TimeManager so a
## hit-stopped entity still flashes while it is frozen.

const SHADER: Shader = preload("res://scripts/effects/hit_flash.gdshader")
const DEFAULT_FRAMES: int = 4
const WHITE: Color = Color(1.0, 1.0, 1.0, 1.0)
const GOLD: Color = Color(1.0, 0.82, 0.2, 1.0)
const RED: Color = Color(1.0, 0.25, 0.2, 1.0)

var _materials: Array[ShaderMaterial] = []
var _frames_total: int = DEFAULT_FRAMES
var _frames_left: int = 0


## Adds a HitFlash named "HitFlash" under `owner_node` flashing `items`. Each
## item gets its own ShaderMaterial so flashes never bleed between sprites.
static func attach(owner_node: Node, items: Array[CanvasItem]) -> HitFlash:
	var existing: HitFlash = owner_node.get_node_or_null("HitFlash") as HitFlash
	if existing != null:
		return existing
	var flash := HitFlash.new()
	flash.name = "HitFlash"
	owner_node.add_child(flash)
	for item: CanvasItem in items:
		flash.add_target(item)
	return flash


func _ready() -> void:
	set_physics_process(_frames_left > 0)


func add_target(item: CanvasItem) -> void:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"flash_amount", 0.0)
	item.material = material
	_materials.append(material)


func is_flashing() -> bool:
	return _frames_left > 0


## Current overlay strength, 0 when idle.
func amount() -> float:
	return float(_frames_left) / float(_frames_total) if _frames_left > 0 else 0.0


## Starts (or restarts) a flash of `frames` physics frames in `color`.
func flash(color: Color = WHITE, frames: int = DEFAULT_FRAMES) -> void:
	_frames_total = maxi(frames, 1)
	_frames_left = _frames_total
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(&"flash_color", color)
	_apply()
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	step()


## One frame of the ramp. Public so tests can step it without the engine tick.
func step() -> void:
	if _frames_left <= 0:
		return
	_frames_left -= 1
	_apply()
	if _frames_left <= 0:
		set_physics_process(false)


func _apply() -> void:
	var value: float = amount()
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(&"flash_amount", value)
