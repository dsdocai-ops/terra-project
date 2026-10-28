class_name GroundCrackLine
extends Node2D
## The Pickaxe heavy's signature: a line of cracks struck across the ground in
## the swing's direction (SINKHOLE_SPEC section 7, Blades: "Heavy cracks the
## ground in a line"). Placeholder art drawn with `_draw()` until W2-A12.
## Owned by weapons. Sync: none, local presentation — every peer that runs the
## swing spawns its own from the same inputs, so nothing is replicated. It
## times itself out, like `DodgePing`.

const MARK_COUNT: int = 5
## Interior marks get a short branch tick every `BRANCH_STEP` marks.
const BRANCH_STEP: int = 2
const BRANCH_LENGTH_PX: float = 9.0
const LIFETIME_SECONDS: float = 0.7
## Half-width of the corridor the marks may wander across, either side of the
## line. The ends stay pinned: a crack starts under the feet and ends at the
## swing's full reach.
const MAX_JITTER_PX: float = 6.0
## Fixed perpendicular zigzag per mark (no RNG, so the same swing always draws
## the same crack). First and last are 0 to pin the ends.
const WAVE: Array[float] = [0.0, 1.0, -1.0, 0.6, 0.0]
const CRACK_COLOR: Color = Color(0.82, 0.74, 0.6, 1.0)
const LINE_WIDTH: float = 2.0
## Ground decal, drawn squashed like the other ground marks.
const SQUASH_Y: float = 0.55

var _seconds_left: float = 0.0
var _points: PackedVector2Array = PackedVector2Array()
var _branches: PackedVector2Array = PackedVector2Array()


## The crack marks along the line: `MARK_COUNT` points from `from` to
## `from + dir * length_px`, the interior ones wandering inside the jitter
## corridor on the fixed zigzag. Pure geometry, no RNG; tests read it directly.
static func crack_points(from: Vector2, dir: Vector2, length_px: float) -> PackedVector2Array:
	var along: Vector2 = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	var across := Vector2(-along.y, along.x)
	var points := PackedVector2Array()
	for mark: int in MARK_COUNT:
		var share: float = float(mark) / float(MARK_COUNT - 1)
		points.append(from + along * (share * length_px) + across * (MAX_JITTER_PX * WAVE[mark]))
	return points


## Branch ticks off the interior marks: a pair per branch (start, end), on the
## diagonal the crack would splinter along, alternating sides.
static func branch_pairs(dir: Vector2, length_px: float) -> PackedVector2Array:
	var points := crack_points(Vector2.ZERO, dir, length_px)
	var along: Vector2 = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	var across := Vector2(-along.y, along.x)
	var branches := PackedVector2Array()
	for mark: int in range(1, MARK_COUNT - 1, BRANCH_STEP):
		var side: float = 1.0 if (mark / BRANCH_STEP) % 2 == 0 else -1.0
		var splint: Vector2 = (along + across * side).normalized() * BRANCH_LENGTH_PX
		branches.append(points[mark])
		branches.append(points[mark] + splint)
	return branches


## Spawns a crack line striking from `at` along `dir` for `length_px`, under
## `parent`. Returns it for the caller and tests; it frees itself after
## `LIFETIME_SECONDS`.
static func spawn(parent: Node, at: Vector2, dir: Vector2, length_px: float) -> GroundCrackLine:
	var crack := GroundCrackLine.new()
	parent.add_child(crack)
	crack.global_position = at
	crack.play(dir, length_px)
	return crack


func _ready() -> void:
	z_index = 4
	scale = Vector2(1.0, SQUASH_Y)
	visible = false
	set_process(false)
	add_to_group(&"ground_cracks")


## Strikes the crack: local geometry along `dir` for `length_px`, then the
## fade-out clock runs.
func play(dir: Vector2, length_px: float) -> void:
	_points = crack_points(Vector2.ZERO, dir, length_px)
	_branches = branch_pairs(dir, length_px)
	_seconds_left = LIFETIME_SECONDS
	visible = true
	set_process(true)
	queue_redraw()


## Seconds left before it fades out entirely, for tests.
func seconds_left() -> float:
	return _seconds_left


## The local crack points, for tests (the node itself sits at the strike origin).
func points() -> PackedVector2Array:
	return _points


func _process(delta: float) -> void:
	step(delta)


## Advances the fade by real seconds. Public so tests can step it.
func step(delta: float) -> void:
	if _seconds_left <= 0.0:
		return
	_seconds_left -= delta
	if _seconds_left <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var fade: float = clampf(_seconds_left / LIFETIME_SECONDS, 0.0, 1.0)
	var color: Color = Color(CRACK_COLOR.r, CRACK_COLOR.g, CRACK_COLOR.b, CRACK_COLOR.a * fade)
	if _points.size() >= 2:
		draw_polyline(_points, color, LINE_WIDTH)
	for branch: int in range(0, _branches.size(), 2):
		draw_line(_branches[branch], _branches[branch + 1], color, LINE_WIDTH * 0.6)
