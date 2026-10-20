class_name ProcChainProbe
extends Effect
## Test double for a proc-chaining relic: it listens to every hit-carrying
## signal on the `Events` bus and, when a hit concerns it, produces one more
## result through `deal_damage` (or `spawn`) — which is exactly the shape the
## proc-depth rules exist for. Used by `tests/unit/test_proc_limits.gd`; never
## used in a game scene.
##
## It goes through `Effect.listen()`, so the dispatch wrapper under test is the
## real one, and it reads `trigger_depth` inside its handler, so the depth the
## wrapper set is observed where an effect script would observe it.
##
## Fields, all set by the test after `EffectHost.add()` (the handler reads them,
## so `_on_attach()` does not need them):
## - `react_tag`: only hits carrying this tag concern this probe. Empty means
##   every hit does. Two probes with different tags are two links of one chain.
## - `emit_tag`: the tag the produced hit carries, so the next link recognises
##   it. Empty means the produced hit carries no tag of its own (the chain is
##   then self-feeding, which is the "self-triggering" case).
## - `link_limit`: how many results this probe will ever produce. The five-link
##   chain sets 5; the observe-only cases set 0, so the probe records reactions
##   without advancing the chain. The cap is the *test's* bound, deliberately
##   longer than the spec's depth limit, so a chain that stops has stopped
##   because of the gate and not because it ran out of links.
## - `target` / `spawn_scene`: what it produces — a hit on `target`, or one
##   spawn at `spawn_at` when a scene is set.
## - `log`: the shared `ProcChainLog` the case reads back.
##
## Sync: none — a test double. The real effects it stands in for are host-only.

## Every signal on the bus that carries a `HitData`, so the gate can be asserted
## through any of them rather than through `hit_landed` alone.
const HIT_SIGNAL_NAMES: Array[StringName] = [
	&"hit_landed",
	&"crit_landed",
	&"player_damaged",
	&"enemy_killed",
	&"elite_killed",
]

## Only hits carrying this tag concern this probe; empty means all of them.
var react_tag: StringName = &""
## The tag the produced hit carries; empty means none of its own.
var emit_tag: StringName = &""
## How many results this probe may produce in one case.
var link_limit: int = 0
## The node a produced hit is dealt to.
var target: Node = null
## When set, the probe spawns this scene instead of dealing a hit.
var spawn_scene: PackedScene = null
## Where a spawned scene is placed.
var spawn_at: Vector2 = Vector2.ZERO
## The shared record of every reaction in the case.
var log: ProcChainLog = null
## How many results this probe has produced so far.
var links: int = 0


func _on_attach() -> void:
	listen(Events.hit_landed, _on_hit_landed)
	listen(Events.crit_landed, _on_crit_landed)
	listen(Events.player_damaged, _on_player_damaged)
	listen(Events.enemy_killed, _on_enemy_killed)
	listen(Events.elite_killed, _on_elite_killed)


func _on_hit_landed(hit: HitData) -> void:
	_react(&"hit_landed", hit)


func _on_crit_landed(hit: HitData) -> void:
	_react(&"crit_landed", hit)


func _on_player_damaged(_victim: Player, hit: HitData) -> void:
	_react(&"player_damaged", hit)


func _on_enemy_killed(_enemy: Node, hit: HitData) -> void:
	_react(&"enemy_killed", hit)


func _on_elite_killed(_enemy: Node, hit: HitData) -> void:
	_react(&"elite_killed", hit)


## One reaction: filter, record, then advance the chain if there is one left to
## advance. The record happens before the chain check, so a probe that has run
## out of links is still counted as having reacted — the gate is asserted on
## what ran, not on what it produced.
func _react(signal_name: StringName, hit: HitData) -> void:
	if hit == null:
		return
	if react_tag != &"" and not hit.tags.has(react_tag):
		return
	if log != null:
		log.record(source_id(), signal_name, trigger_depth)
	if target == null and spawn_scene == null:
		return
	if links >= link_limit:
		return
	links += 1
	if spawn_scene != null:
		spawn(spawn_scene, spawn_at)
		return
	var next: HitData = HitData.new()
	next.base_damage = hit.base_damage
	if emit_tag != &"":
		next.tags.append(emit_tag)
	deal_damage(target, next)
