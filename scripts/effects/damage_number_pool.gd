class_name DamageNumberPool
extends Node
## Recycles the `DamageNumber` labels hit feedback spawns (SPEC-combat-core
## "Hit feedback", a provided interface). Owned by combat-core. Sync: none,
## local presentation; `CombatFeedback.setup` attaches one under World/FX on
## every peer and routes every number and word pop through it.
##
## Idle labels wait hidden under this node. An acquired one moves into the FX
## root (so its `position` stays world-relative, exactly like a direct
## `DamageNumber.spawn`), and hands itself back here when its tween ends.
## Nothing is freed mid-run, so a long fight never grows the node count.

## Labels created up front so the first hits of a fight never allocate.
const WARM_INSTANCES: int = 8

## How many labels this pool has made in its life (tests count this).
var created_count: int = 0

var _fx_root: Node = null
var _free: Array[DamageNumber] = []


## Attaches one pool named "DamageNumberPool" under `fx_root`, reusing an
## existing one (same pattern as HitFlash.attach).
static func attach(fx_root: Node) -> DamageNumberPool:
	var existing: DamageNumberPool = fx_root.get_node_or_null("DamageNumberPool") as DamageNumberPool
	if existing != null:
		return existing
	var pool := DamageNumberPool.new()
	pool.name = "DamageNumberPool"
	fx_root.add_child(pool)
	return pool


func _ready() -> void:
	_fx_root = get_parent()
	for _instance in WARM_INSTANCES:
		var number := _make()
		add_child(number)
		_free.append(number)


## A damage number at world position `at`, styled like `DamageNumber.spawn`
## (crits larger and gold, a hurt player's own number red).
func spawn_number(at: Vector2, amount: int, crit: bool, on_player: bool) -> DamageNumber:
	var number := _acquire()
	number.setup_number(at, amount, crit, on_player)
	number.play()
	return number


## A word pop (the "STAGGER" text) through the same pool.
func spawn_text(at: Vector2, word: String, color: Color = DamageNumber.STAGGER_COLOR) -> DamageNumber:
	var number := _acquire()
	number.setup_text(at, word, color)
	number.play()
	return number


## Hands a finished number back. Called by DamageNumber when its tween ends.
func release(number: DamageNumber) -> void:
	number.get_parent().remove_child(number)
	add_child(number)
	number.visible = false
	_free.append(number)


func _make() -> DamageNumber:
	created_count += 1
	var number := DamageNumber.new()
	number.pool = self
	number.visible = false
	return number


func _acquire() -> DamageNumber:
	var number: DamageNumber = _free.pop_back() if not _free.is_empty() else _make()
	if number.get_parent() != null:
		number.get_parent().remove_child(number)
	_fx_root.add_child(number)
	number.visible = true
	return number
