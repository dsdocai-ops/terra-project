class_name HitSpark
extends Node2D
## A short burst of lines at the point a hit landed (SPEC-combat-core "Hit
## feedback"): small for a light hit, large for a heavy one. Placeholder art
## drawn with _draw() until AR-3. Owned by combat-core. Sync: none, local only;
## spawned on every peer by `CombatFeedback`.

const SMALL_RAYS: int = 5
const LARGE_RAYS: int = 8
const SMALL_LENGTH_PX: float = 9.0
const LARGE_LENGTH_PX: float = 16.0
const LIFETIME_SECONDS: float = 0.14
const DEFAULT_COLOR: Color = Color(1.0, 0.95, 0.7, 1.0)

var large: bool = false
var color: Color = DEFAULT_COLOR
var progress: float = 0.0


## Spawns a spark at world position `at` under `parent`.
static func spawn(parent: Node, at: Vector2, is_large: bool, spark_color: Color = DEFAULT_COLOR) -> HitSpark:
	var spark := HitSpark.new()
	spark.large = is_large
	spark.color = spark_color
	spark.z_index = 90
	parent.add_child(spark)
	spark.global_position = at
	return spark


func _ready() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "progress", 1.0, LIFETIME_SECONDS)
	tween.tween_callback(queue_free)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var rays: int = LARGE_RAYS if large else SMALL_RAYS
	var length: float = LARGE_LENGTH_PX if large else SMALL_LENGTH_PX
	var faded := Color(color.r, color.g, color.b, 1.0 - progress)
	for index: int in rays:
		var dir: Vector2 = Vector2.RIGHT.rotated(TAU * float(index) / float(rays))
		draw_line(dir * length * progress * 0.4, dir * length * (0.4 + progress * 0.6), faded, 2.0 if large else 1.0)
