class_name DebugCommands
extends RefCounted
## Registers the debug-tools core command set on a DebugConsole (the
## SPEC-debug-tools command table): help, spawn, give, gold, skip, seed, god,
## kill, heal, timestop, timeslow, fps, dump. Handlers return result text;
## targeting commands use the issuing peer id to find the right player.
## Owned by debug-tools (W2-B4).
## Sync: every handler runs on the host (a client's console routes the line
## there via NetworkManager.request_debug first), and the host-only seams the
## commands touch (spawn, kill, currency) are re-checked by the systems they
## call.

## The TimeManager source tag used by timestop / timeslow so clear_source can
## cancel them.
const SOURCE := &"debug_console"
const GIVE_TYPES: Array[String] = ["relic", "ability", "weapon", "mutation"]
const DUMP_PATH := "user://debug_dump.json"

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
	console.register(&"skip", _cmd_skip, "skip — stub: floor advance lands with floor-generation (week 3)")
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


func _cmd_skip(_args: PackedStringArray, _peer_id: int) -> String:
	return "skip: floor advance lands with floor-generation (week 3) — nothing to skip yet"


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
