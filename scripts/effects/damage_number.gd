class_name DamageNumber
extends Label
## A floating damage number (SPEC-combat-core "Hit feedback"): pops, drifts up
## and fades. Local presentation only. Crits are larger and gold. Owned by
## combat-core. Sync: none. Placeholder look: plain label text.
##
## Numbers usually come from the `DamageNumberPool` under World/FX: the pool
## sets `pool`, recycles the label through `play()` when its tween ends, and
## nothing is freed mid-run. A number with no pool (direct `spawn`) frees
## itself as before.

const RISE_PX: float = 26.0
const LIFETIME_SECONDS: float = 0.7
const NORMAL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const CRIT_COLOR: Color = Color(1.0, 0.85, 0.2, 1.0)
const STAGGER_COLOR: Color = Color(1.0, 0.75, 0.2, 1.0)
const PLAYER_HURT_COLOR: Color = Color(1.0, 0.35, 0.3, 1.0)

## The pool that recycles this number, or null for a spawn-and-free one.
var pool: DamageNumberPool = null


## Spawns a number at world position `at` under `parent`.
static func spawn(parent: Node, at: Vector2, amount: int, crit: bool, on_player: bool) -> DamageNumber:
	var number := DamageNumber.new()
	number.setup_number(at, amount, crit, on_player)
	parent.add_child(number)
	return number


## Spawns a short word (the "STAGGER" pop) at world position `at`.
static func spawn_text(parent: Node, at: Vector2, word: String, color: Color = STAGGER_COLOR) -> DamageNumber:
	var number := DamageNumber.new()
	number.setup_text(at, word, color)
	parent.add_child(number)
	return number


func _ready() -> void:
	if pool == null:
		play()


## Styles the label for one amount (the pool calls this before `play`).
func setup_number(at: Vector2, amount: int, crit: bool, on_player: bool) -> void:
	text = str(amount)
	z_index = 100
	position = at - Vector2(8.0, 0.0)
	var color: Color = CRIT_COLOR if crit else (PLAYER_HURT_COLOR if on_player else NORMAL_COLOR)
	add_theme_color_override(&"font_color", color)
	add_theme_font_size_override(&"font_size", 16 if crit else 11)


## Styles the label for one word (the pool calls this before `play`).
func setup_text(at: Vector2, word: String, color: Color = STAGGER_COLOR) -> void:
	text = word
	z_index = 100
	position = at - Vector2(float(word.length()) * 3.0, 0.0)
	add_theme_color_override(&"font_color", color)
	add_theme_font_size_override(&"font_size", 13)


## Runs the pop-drift-fade. A fresh unpooled number plays from `_ready`; the
## pool calls it on every reuse.
func play() -> void:
	modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - RISE_PX, LIFETIME_SECONDS)
	tween.tween_property(self, "modulate:a", 0.0, LIFETIME_SECONDS)
	tween.chain().tween_callback(_finish)


## The tween's end: back to the pool, or freed when there is none.
func _finish() -> void:
	if pool != null:
		pool.release(self)
	else:
		queue_free()
