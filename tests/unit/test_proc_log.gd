extends GutTest
## Tests for the proc record behind the `effects` overlay — effect-system, W4-B11
## (follow-up 5, goal G1).
##
## `ProcLog` keeps the last 20 procs delivered through `Effect.deal_damage`,
## newest first. The first half of this file pins the store on its own: the cap,
## the order, the copy semantics and the overlay's line format. The second half
## pins the production path: a hit delivered through `deal_damage` lands in the
## store with its source id, proc depth and damage, and a hit with no sink does
## not. The sink is `HurtboxStub`, which records the hit and leaves
## `final_damage` alone, so the test sets that field itself before the call.
##
## Sync: none under test. The store is host-only (see scripts/effects/proc_log.gd).

const HURTBOX_STUB_SCRIPT_PATH: String = "res://tests/helpers/hurtbox_stub.gd"

var _effects: Array[Effect] = []
var _players: Array[Node] = []


func before_each() -> void:
	ProcLog.clear()


func after_each() -> void:
	for effect: Effect in _effects:
		effect.detach()
	_effects.clear()
	for player: Node in _players:
		player.free()
	_players.clear()
	ProcLog.clear()


func _fill(count: int) -> void:
	for index: int in range(1, count + 1):
		ProcLog.record(&"fire_ring", index, index * 2)


## An effect attached to a bare Player with a HurtboxStub as its damage sink.
func _attach_to_stub_player(source_id: StringName) -> Effect:
	var player := Player.new()
	_players.append(player)
	var hurtbox := HurtboxStub.new()
	hurtbox.name = "Hurtbox"
	player.add_child(hurtbox)
	var content := ContentData.new()
	content.id = source_id
	var effect := Effect.new()
	player.add_child(effect)
	effect.attach(player, content, 1)
	_effects.append(effect)
	return effect


# --- the store -------------------------------------------------------------

func test_recording_twenty_five_keeps_the_newest_twenty() -> void:
	_fill(25)
	var entries: Array[Dictionary] = ProcLog.recent()
	assert_eq(entries.size(), ProcLog.CAPACITY, "the store holds CAPACITY procs")
	assert_eq(ProcLog.CAPACITY, 20, "the overlay is the last 20 procs")
	assert_eq(entries[0]["depth"], 25, "the newest proc is first")
	assert_eq(entries[19]["depth"], 6, "the oldest kept proc is the 6th, the first five are dropped")
	assert_eq(entries.filter(func(entry: Dictionary) -> bool: return entry["depth"] < 6).size(), 0, "depths 1 to 5 are gone from the store")


func test_recent_is_newest_first_with_every_field() -> void:
	ProcLog.record(&"chain_bolt", 1, 7)
	ProcLog.record(&"echo_blade", 2, 11)
	var entries: Array[Dictionary] = ProcLog.recent()
	assert_eq(entries.size(), 2, "two procs are kept")
	assert_eq(entries[0], {"source": &"echo_blade", "depth": 2, "damage": 11}, "newest first, all three fields")
	assert_eq(entries[1], {"source": &"chain_bolt", "depth": 1, "damage": 7}, "the older proc follows")


func test_recent_returns_a_copy_the_caller_cannot_use_to_change_the_store() -> void:
	_fill(3)
	var entries: Array[Dictionary] = ProcLog.recent()
	entries.clear()
	assert_eq(ProcLog.recent().size(), 3, "clearing the copy leaves the store alone")


func test_clear_empties_the_store() -> void:
	_fill(4)
	ProcLog.clear()
	assert_eq(ProcLog.recent().size(), 0, "clear() removes every entry")


# --- the overlay text ------------------------------------------------------

func test_format_lines_lists_the_newest_first_with_source_and_depth() -> void:
	ProcLog.record(&"chain_bolt", 1, 7)
	ProcLog.record(&"echo_blade", 2, 11)
	var text: String = ProcLog.format_lines(ProcLog.recent())
	var lines: PackedStringArray = text.split("\n")
	assert_eq(lines.size(), 2, "one line per proc")
	assert_eq(lines[0], "echo_blade  depth 2  dmg 11", "the newest proc is the first line")
	assert_eq(lines[1], "chain_bolt  depth 1  dmg 7", "the older proc follows")


func test_format_lines_says_so_when_there_are_no_procs() -> void:
	assert_eq(ProcLog.format_lines(ProcLog.recent()), "procs: none yet", "an empty store has a placeholder line")


# --- the production path ---------------------------------------------------

func test_deal_damage_records_the_proc_with_source_depth_and_damage() -> void:
	var effect: Effect = _attach_to_stub_player(&"test_relic")
	effect.trigger_depth = 2
	var hit := HitInfo.new()
	hit.final_damage = 9
	effect.deal_damage(effect.player, hit)
	var entries: Array[Dictionary] = ProcLog.recent()
	assert_eq(entries.size(), 1, "the delivered hit is recorded once")
	assert_eq(entries[0], {"source": &"test_relic", "depth": 3, "damage": 9}, "source id, depth trigger+1, final damage")


func test_deal_damage_with_no_sink_records_nothing() -> void:
	var effect: Effect = _attach_to_stub_player(&"test_relic")
	var bare := Node.new()
	effect.deal_damage(bare, HitInfo.new())
	bare.free()
	effect.deal_damage(null, HitInfo.new())
	assert_eq(ProcLog.recent().size(), 0, "a hit that never reached a sink is not a proc")
