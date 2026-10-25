class_name ChargeRing
extends Node2D
## The ring at a player's feet that fills while a heavy charges (combat v2 C3).
## It flashes when the charge is full. Placeholder art drawn with _draw() until
## AR-3. Owned by combat-core. Sync: none, purely local presentation; the
## HeavyCharge state drives it.

const RADIUS_PX: float = 16.0
const SQUASH_Y: float = 0.5
const FLASH_SECONDS: float = 0.18
const FILL_COLOR: Color = Color(0.95, 0.85, 0.4, 0.9)
const FULL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)

## 0..1, how much of the ring is filled.
var fill: float = 0.0:
	set(value):
		fill = clampf(value, 0.0, 1.0)
		queue_redraw()

var _flash_left: float = 0.0


func _ready() -> void:
	visible = false
	z_index = 4
	scale = Vector2(1.0, SQUASH_Y)
	set_process(false)


func show_ring() -> void:
	fill = 0.0
	_flash_left = 0.0
	visible = true


func hide_ring() -> void:
	visible = false
	_flash_left = 0.0
	set_process(false)


## The full-charge flash.
func flash() -> void:
	_flash_left = FLASH_SECONDS
	set_process(true)
	queue_redraw()


func is_flashing() -> bool:
	return _flash_left > 0.0


func _process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	if _flash_left <= 0.0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	draw_arc(Vector2.ZERO, RADIUS_PX, 0.0, TAU, 32, Color(0.0, 0.0, 0.0, 0.35), 3.0)
	if fill > 0.0:
		var color: Color = FULL_COLOR if _flash_left > 0.0 else FILL_COLOR
		draw_arc(Vector2.ZERO, RADIUS_PX, -PI * 0.5, -PI * 0.5 + TAU * fill, 32, color, 3.0 if _flash_left > 0.0 else 2.0)
