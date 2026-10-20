class_name DebugCommands
extends RefCounted
## Registers the debug-tools core command set on a DebugConsole (the
## SPEC-debug-tools command table): help, spawn, give, gold, skip, floor, seed,
## god, kill, heal, timestop, timeslow, fps, dump. Handlers return result text;
## targeting commands use the issuing peer id to find the right player.
## Owned by debug-tools (W2-B4, floor advance W3-B5a).
## Sync: every handler runs on the host (a client's console routes the line
## there via NetworkManager.request_debug first), and the host-only seams the
## commands touch (spawn, kill, currency) are re-checked by the systems they
## call.

## The TimeManager source tag used by timestop / timeslow so clear_source can
## cancel them.
const SOURCE := &"debug_console"
const GIVE_TYPES: Array[String] = ["relic", "ability", "weapon", "mutation"]
const DUMP_PATH := "user://debug_dump.json"
## The most floor advances one `floor <n>` call may make. The target is range
## checked against RunState's own bounds first and next_floor() refuses past the
## last floor, so this is a guard on the loop rather than a second rule.
const MAX_FLOOR_JUMPS: int = 64

var console: DebugConsole


## Installs every core command onto self.console. Called by the console after
## wiring the back-reference; the console holds this instance so the bound
## handler callables stay valid.
func register_all() -> void:
	_register()


func _register() -> void:
	console.register(&"help", _cmd_help, "help [cmd] — list commands or describe one")
	console.register(&"spawn", _cmd_spawn, "spawn <enemy_id> [count] [elite] [affix] — spawn enemies at the issuing player (affix ignored until enemies-ai lands)")
	console.register(&"give", _cmd_give, "give <relic|ability|weapon|mutation> <id> [stacks] — grant to the issuing player (deferred to the owning module)")
	console.register(&"gold", _cmd_gold, "gold <n> — give n gold to the issuing player (currency_gained event; totals tracked from week 4)")
	console.register(&"skip", _cmd_skip, "skip — advance one floor (host only; reports why a shut exit blocked it)")
	console.register(&"floor", _cmd_floor, "floor <n> — jump to floor %d-%d, advancing one floor at a time (host only)" % [RunState.MIN_FLOOR, RunState.MAX_FLOOR])
	console.register(&"seed", _cmd_seed, "seed <n> — force the next run seed on GameState (0 clears)")
	console.register(&"god", _cmd_god, "god — toggle god mode for the issuing player (consumed once combat-core Health lands)")
	console.register(&"kill", _cmd_kill, "kill — kill every enemy under World/Entities (host-only)")
	console.register(&"heal", _cmd_heal, "heal — full-heal the issuing player (deferred until combat-core Health lands)")
	console.register(&"timestop", _cmd_timestop, "timestop <s> — stop enemies for s seconds (TimeManager; players unaffected)")
	console.register(&"timeslow", _cmd_timeslow, "timeslow <factor> <s> — slow enemies by factor for s seconds")
	console.register(&"fps", _cmd_fps, "fps — toggle the FPS overlay")
	console.register(&"dump", _cmd_dump, "dump — write run/profile debug state to user://debug_dump.json")


func _cmd_help(args: PackedStringArray, _peer_id: int) -> String:
	if args.is_empty():
		var lines: Array[String] = []
		for entry: DebugConsole.CommandEntry in console.list_commands():
			lines.append("%s — %s" % [entry.name, entry.help])
		return "\n".join(lines)
	var name := StringName(args[0])
	var entry := console.entry(name)
	if entry == null:
		return "unknown command: %s" % name
	return "%s — %s" % [entry.name, entry.help]


func _cmd_spawn(args: PackedStringArray, peer_id: int) -> String:
	if args.is_empty():
		return "spawn needs an enemy id: spawn <enemy_id> [count] [elite] [affix]"
	var kind := StringName(args[0])
	var count := 1
	if args.size() >= 2 and String(args[1]).is_valid_int():
		count = clampi(int(args[1]), 1, 32)
	var elite := _is_truthy(args, 2)
	# args[3] is the affix; accepted and ignored until EnemyData (W2-A9) lands.
	var world := GameState.world
	if world == null:
		return "no world loaded; cannot spawn"
	var position := _spawn_position(peer_id)
	for i in count:
		world.enemy_spawner.spawn_enemy(EnemySpawnInfo.new(kind, position, elite))
	return "spawned %d %s at %s%s" % [count, kind, position, " (elite)" if elite else ""]


func _cmd_give(args: PackedStringArray, _peer_id: int) -> String:
	if args.size() < 2:
		return "give needs: give <relic|ability|weapon|mutation> <id> [stacks]"
	var type := String(args[0]).to_lower()
	if not GIVE_TYPES.has(type):
		return "unknown type '%s' — expected one of %s" % [type, ", ".join(GIVE_TYPES)]
	var id := String(args[1])
	var stacks := 1
	if args.size() >= 3 and String(args[2]).is_valid_int():
		stacks = maxi(int(args[2]), 1)
	# The owning module (weapons / abilities / relics / run-economy) applies the
	# grant to the issuing player's inventory; none have landed (week 4-5), so
	# this validates the request and reports the deferral.
	return "give %s '%s' x%d: %s lands in week 4-5 — nothing granted yet" % [type, id, stacks, _owning_module(type)]


func _cmd_gold(args: PackedStringArray, peer_id: int) -> String:
	if args.is_empty() or not String(args[0]).is_valid_int():
		return "gold needs a whole number: gold <n>"
	var amount := maxi(int(args[0]), 0)
	var player := NetworkManager.get_player(peer_id)
	if player == null:
		return "no player for peer %d to receive gold" % peer_id
	Events.currency_gained.emit(player, &"gold", amount)
	return "granted %d gold to peer %d (currency_gained emitted; run-economy tracks totals from week 4)" % [amount, peer_id]


## `skip` is GameState.next_floor() with the authority's reason reported: the
## host owns the advance, refuses it while the floor's exit is shut or when the
## run is over, and records why in `last_advance_refusal`, so the console can
## say it instead of leaving the reason in the log line alone (W3-B5a).
func _cmd_skip(_args: PackedStringArray, _peer_id: int) -> String:
	GameState.next_floor()
	var reason: StringName = GameState.last_advance_refusal
	if reason != GameState.ADVANCE_REFUSAL_NONE:
		return "skip refused: %s" % _advance_refusal_text(reason)
	var state: RunState = GameState.run
	if state == null:
		return "skip refused: no run is live"
	return "skipped to floor %d (biome %d)" % [state.floor_index, state.biome_index]


## `floor <n>` jumps the live run to floor n by calling next_floor() once per
## floor, so every floor it passes through is announced and the same exit rule
## applies as a normal advance — there is no teleport that skips a shut exit.
## Refused: a non-integer, a value outside RunState's 1..30, a target behind the
## current floor (the advance only goes forward), no live run, and a shut exit.
func _cmd_floor(args: PackedStringArray, _peer_id: int) -> String:
	if args.is_empty() or not String(args[0]).is_valid_int():
		return "floor needs a whole number: floor <n> (%d-%d)" % [RunState.MIN_FLOOR, RunState.MAX_FLOOR]
	var target: int = int(args[0])
	if target < RunState.MIN_FLOOR or target > RunState.MAX_FLOOR:
		return "floor %d is out of range: floors are %d-%d" % [target, RunState.MIN_FLOOR, RunState.MAX_FLOOR]
	var state: RunState = GameState.run
	if state == null:
		return "floor refused: %s" % _advance_refusal_text(GameState.ADVANCE_REFUSAL_NO_RUN)
	var from_floor: int = state.floor_index
	if target == from_floor:
		return "already on floor %d" % target
	if target < from_floor:
		return "floor %d is behind the current floor %d: floor only advances (skip steps forward one floor)" % [target, from_floor]
	var steps := 0
	while GameState.run != null and GameState.run.floor_index < target and steps < MAX_FLOOR_JUMPS:
		GameState.next_floor()
		var reason: StringName = GameState.last_advance_refusal
		if reason != GameState.ADVANCE_REFUSAL_NONE:
			return "floor %d refused at floor %d after %d step(s): %s" % [
				target, GameState.run.floor_index, steps, _advance_refusal_text(reason)]
		steps += 1
	var arrived: RunState = GameState.run
	if arrived == null:
		return "floor refused: no run is live"
	return "floor %d: advanced %d floor(s) from %d (biome %d)" % [target, steps, from_floor, arrived.biome_index]


## The readable text for a refused floor advance, one phrase per GameState
## ADVANCE_REFUSAL_* code. Kept here so the wording the player reads lives with
## the console that prints it while GameState stays free of presentation
## strings, and so a new refusal code fails loudly rather than silently reading
## as a cleared refusal.
func _advance_refusal_text(reason: StringName) -> String:
	if reason == GameState.ADVANCE_REFUSAL_NOT_HOST:
		return "the host owns floor state"
	if reason == GameState.ADVANCE_REFUSAL_NO_RUN:
		return "no run is live"
	if reason == GameState.ADVANCE_REFUSAL_EXIT_SHUT:
		return "the current floor's exit is still shut"
	if reason == GameState.ADVANCE_REFUSAL_LAST_FLOOR:
		return "this is the run's last floor"
	return "unknown refusal (%s)" % reason


func _cmd_seed(args: PackedStringArray, _peer_id: int) -> String:
	if args.is_empty() or not String(args[0]).is_valid_int():
		return "seed needs a whole number: seed <n> (0 clears)"
	var value := int(args[0])
	GameState.forced_seed = value
	return "next run seed forced to %d (takes effect on the next run start)" % value


func _cmd_god(_args: PackedStringArray, peer_id: int) -> String:
	console.toggle_god(peer_id)
	return "god mode %s for peer %d (consumed once combat-core Health lands)" % ["ON" if console.is_god(peer_id) else "OFF", peer_id]


func _cmd_kill(_args: PackedStringArray, _peer_id: int) -> String:
	var world := GameState.world
	if world == null:
		return "no world loaded; nothing to kill"
	var killed := 0
	for child in world.entities.get_children():
		if not child.has_method("apply_hit"):
			continue
		if int(child.get("current_hp")) <= 0:
			continue
		child.apply_hit(int(child.get("current_hp")))
		Events.enemy_killed.emit(child, null)
		killed += 1
	return "killed %d enem%s" % [killed, "y" if killed == 1 else "ies"]


func _cmd_heal(_args: PackedStringArray, peer_id: int) -> String:
	var player := NetworkManager.get_player(peer_id)
	if player == null:
		return "no player for peer %d to heal" % peer_id
	return "heal: Health lands with combat-core (Dev A, W2-A1) — nothing to heal yet; player %d exists" % peer_id


func _cmd_timestop(args: PackedStringArray, _peer_id: int) -> String:
	if args.is_empty() or not String(args[0]).is_valid_float():
		return "timestop needs seconds: timestop <s>"
	var seconds := maxf(float(args[0]), 0.01)
	TimeManager.stop_enemies(seconds, SOURCE)
	return "time stop: enemies frozen for %.1f s (players unaffected)" % seconds


func _cmd_timeslow(args: PackedStringArray, _peer_id: int) -> String:
	if args.size() < 2 or not String(args[0]).is_valid_float() or not String(args[1]).is_valid_float():
		return "timeslow needs: timeslow <factor> <s>"
	var factor := clampf(float(args[0]), 0.0, 1.0)
	var seconds := maxf(float(args[1]), 0.01)
	TimeManager.slow_enemies(factor, seconds, SOURCE)
	return "time slow: enemies at %.2fx for %.1f s" % [factor, seconds]


func _cmd_fps(_args: PackedStringArray, _peer_id: int) -> String:
	var on := console.toggle_fps()
	return "FPS overlay %s" % ["ON" if on else "OFF"]


func _cmd_dump(_args: PackedStringArray, peer_id: int) -> String:
	var world := GameState.world
	var enemies := 0
	if world != null:
		for child in world.entities.get_children():
			if child.has_method("apply_hit"):
				enemies += 1
	var payload := {
		"generated_by": "debug console dump",
		"peer_id": peer_id,
		"is_host": NetworkManager.is_host,
		"peer_ids": NetworkManager.peer_ids,
		"forced_seed": GameState.forced_seed,
		"player_count": NetworkManager.player_count(),
		"enemies_alive": enemies,
		"world_loaded": world != null,
		"note": "GameState.run and profile are null until run-economy/save-system land (week 3/5)",
	}
	var file := FileAccess.open(DUMP_PATH, FileAccess.WRITE)
	if file == null:
		return "dump failed: cannot open %s" % DUMP_PATH
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return "wrote debug state to %s" % DUMP_PATH


func _spawn_position(peer_id: int) -> Vector2:
	var player := NetworkManager.get_player(peer_id)
	if player == null:
		return Vector2.ZERO
	# "At the cursor": the owning peer's replicated aim position when one is
	# set, else the player's own position.
	if player.aim_position != Vector2.ZERO:
		return player.aim_position
	return player.global_position


func _is_truthy(args: PackedStringArray, index: int) -> bool:
	if index >= args.size():
		return false
	var value := String(args[index]).to_lower()
	return value in ["1", "true", "yes", "elite", "on"]


func _owning_module(type: String) -> String:
	match type:
		"relic":
			return "relics/run-economy"
		"ability":
			return "abilities"
		"weapon":
			return "weapons"
		"mutation":
			return "weapons"
		_:
			return "run-economy"
