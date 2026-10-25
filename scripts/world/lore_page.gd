class_name LorePage
extends Area2D
## The lore page: the walk-over pickup a LORE room holds one of. Owned by
## story-dialogue (W6-B2, goal G4).
##
## SPEC-story-dialogue: "40+ pages across biomes (at least 6 per biome plus
## Vulkar's journals). `LORE` room populator spawns a `LorePage` pickup for the
## lowest-order unread page of that biome. Codex view in `ui-hud` lists them by
## biome with read state. Collecting all is required for the true ending."
## SPEC-floor-generation's room table: "`LORE` | 1 per biome at a fixed floor
## from `BiomeData.lore_floor`, holds one unread page".
##
## Three sentences, three parts. A **pickup** is a walk-over: `body_entered`
## fires when a player's body reaches the page, and there is no prompt and no
## hold — the page is read the moment it is reached. The **unlock** is
## `StoryManager.unlock_lore(page_id)` — the same idempotent store every
## dialogue condition and the codex read from — and the **permanent record** is
## `PlayerProfile.lore_unlocked`, written with the same null-profile guard
## `StoryManager._persist_unlock_flag()` uses, so a page read without a profile
## (headless tests, the shell before a run) still counts for the session.
##
## Two judgement calls are recorded here. **Biome is the index**: a page's
## `biome` field is the 1..6 index `RunState.biome_index` and
## `BiomePlaceholder.id` carry, because Dev A's named `BiomeData` has not landed
## and a name table would be a second source of truth; the swap to names is one
## comparison in `_next_page_for_biome` when biome content arrives (W6-B3).
## **Read state is the profile's**: a page is unread when its id is absent from
## `PlayerProfile.lore_unlocked`, which is the field `merge_run_gains` unions at
## run end — the same single source the codex will read.
##
## Sync: host-authoritative. The host's physics reports the walk-over, so the
## host unlocks and frees; a client whose body reaches the page forwards up the
## request path and unlocks nothing locally, so a page cannot be read on the
## wrong peer. The forwarded walk-over stops at the signal rather than inventing
## an RPC name the wire does not have — the shape is `Chest._forward_use()`'s,
## and the request_* name is networking's to declare.
##
## blocked on Dev A (W3-A3): registering the LORE populator is a guarded no-op
## until `RoomPopulator.generator_script()` resolves, so no generated floor
## places a page yet. The swap-in is nothing — this call starts working the
## moment `scripts/generation/floor_generator.gd` exists with `RoomType.LORE`
## and the static `register_populator(type, populator)`.

## A client forwarded its walk-over to the host (the request_* path).
signal pickup_forwarded(peer_id: int, page_id: StringName)
## Host: the walk-over happened; `peer_id` is the reader, `page_id` the page.
signal picked_up(peer_id: int, page_id: StringName)

## Physics layer 6, "interactable" (project.godot layer_names).
const INTERACTABLE_LAYER: int = 32
## The scene the populator spawns. Loaded at runtime rather than preloaded,
## because that scene's root script is this file and a preload would be a cycle.
const SCENE_PATH: String = "res://scenes/dungeon/interactables/lore_page.tscn"
## Where the lore pages live (SPEC-story-dialogue, "Data model": lore is JSON
## under `data/lore/`, one file per page).
const LORE_DIR: String = "res://data/lore"

## The room type the populator is registered under. SPEC-floor-generation's room
## table: "`LORE` | 1 per biome at a fixed floor from `BiomeData.lore_floor`,
## holds one unread page".
const ROOM_TYPE: StringName = &"LORE"

## A page's fields, one per SPEC-story-dialogue's page shape. The bounds mirror
## the rest of the story data: six biomes, three acts.
const MIN_BIOME: int = 1
const MAX_BIOME: int = 6
const MIN_ACT: int = 1
const MAX_ACT: int = 3

## Registering the populator is once per process; a second call is a no-op.
static var _populator_registered: bool = false
## The blocked-on-Dev-A note is worth one line per process, not one per call.
static var _blocker_logged: bool = false

## The pages read off `data/lore/`, sorted by `order`, cached per process.
static var _catalog: Array[Dictionary] = []
## True once the catalog has been read, so an empty directory is remembered
## rather than rescanned.
static var _catalog_loaded: bool = false
## Test injection: a non-empty catalog wins over `data/lore/` and skips the
## directory scan. `reset_catalog()` clears it and the cache.
static var _catalog_override: Array[Dictionary] = []

## Which page this pickup holds; the populator sets it at spawn.
var page_id: StringName = &""
## The biome index the page belongs to, carried for the codex and for sync
## checks once Dev A's floor sync names a biome (see the header's judgement).
var biome: int = 0

## Host state: the walk-over happened, so the page is spent.
var _collected: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


## True once this page has been collected. Host state.
func is_collected() -> bool:
	return _collected


# --- the pickup contract -----------------------------------------------------


## The walk-over trigger (PLAN G4: "On `body_entered(player)`, call
## `StoryManager.unlock_lore(page_id)` and queue_free"). The host collects; a
## client forwards.
func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null:
		return
	if not NetworkManager.is_host:
		_forward_use(peer_id_of(player))
		return
	_collect(peer_id_of(player))


## The peer behind a body; the local peer when the caller names none.
func peer_id_of(player: Player) -> int:
	if player == null:
		return NetworkManager.local_peer_id
	return player.peer_id


## Host only. Marks the page read in StoryManager, writes the profile record,
## announces the pickup and frees the page. Refuses a page the populator never
## named (an empty `page_id`) and a second walk-over, so a despawn race cannot
## read one page twice.
func _collect(peer_id: int) -> void:
	if _collected or page_id == &"":
		return
	_collected = true
	StoryManager.unlock_lore(page_id)
	_persist_read(page_id)
	picked_up.emit(peer_id, page_id)
	queue_free()


## Client path. The host owns the read, so it travels up as a request and
## nothing unlocks locally. With no session there is nobody to ask.
func _forward_use(peer_id: int) -> void:
	if not NetworkManager.is_active:
		push_warning("[story] lore page refused: no session to send the request on")
		return
	pickup_forwarded.emit(peer_id, page_id)


## Writes the page id into the profile and saves. The profile may be absent (a
## run scene used standalone, or a test) — then the page still counts for the
## session in StoryManager and the save is skipped, never delayed into a crash.
static func _persist_read(page_id: StringName) -> void:
	var profile := SaveManager.profile
	if profile == null:
		return
	if not profile.lore_unlocked.has(String(page_id)):
		profile.lore_unlocked.append(String(page_id))
		SaveManager.save()


# --- the LORE populator and its registration seam ----------------------------


## The Callable the LORE room populator is registered as:
## `FloorGenerator.register_populator(RoomType.LORE, LorePage.lore_populator())`.
static func lore_populator() -> Callable:
	return Callable(LorePage, &"_populate_lore_room")


## Registers the LORE populator with Dev A's registry, once per process.
## Returns true when it registered, false while the registry is absent.
## Guarded on purpose: a floor must never depend on the other lane landing first
## (BRIEF Assumption 4), so the absent-registry path is a recorded no-op that
## notes its blocker **once** — a floor change must not reprint it.
## blocked on Dev A (W3-A3): the swap-in is nothing — this call starts working
## the moment floor_generator.gd exists with RoomType.LORE and the static
## register_populator(type, populator).
static func register_populator() -> bool:
	if _populator_registered:
		return true
	var generator: Script = RoomPopulator.generator_script()
	if generator == null:
		_note_blocked("%s does not exist yet, so a page spawns with the registry" % RoomPopulator.GENERATOR_SCRIPT_PATH)
		return false
	if not generator.has_method(RoomPopulator.REGISTER_METHOD):
		_note_blocked("%s has no %s()" % [RoomPopulator.GENERATOR_SCRIPT_PATH, RoomPopulator.REGISTER_METHOD])
		return false
	var room_type: Variant = room_type_value(generator)
	if room_type == null:
		_note_blocked("%s declares no RoomType.LORE" % RoomPopulator.GENERATOR_SCRIPT_PATH)
		return false
	generator.call(RoomPopulator.REGISTER_METHOD, room_type, lore_populator())
	_populator_registered = true
	print("[story] LORE populator registered with FloorGenerator")
	return true


## How many blocked-on-Dev-A notes this process has written: 0, or 1. The guarded
## registration notes its blocker once and a second call is inert, and this read
## is how that is a checked claim rather than a comment.
static func blocker_warnings() -> int:
	return 1 if _blocker_logged else 0


## The `RoomType.LORE` value, read off a generator script's own constants so
## this file never references a type that does not exist yet. Public because the
## registration test drives it with a registry double.
static func room_type_value(generator: Script) -> Variant:
	return RoomPopulator.room_type_value(generator, ROOM_TYPE)


## Host only. Fills `room` with the biome's lowest-order unread page and returns
## it, or an empty array when it refused (not the host, no room, no live run to
## read a biome from, or no unread page left). `biome_index` overrides the run's
## own biome, so a caller with the room's truth at hand can name it — that is
## the biome context PLAN G4's hook carries. The generator calls this through
## `lore_populator()` after painting the room.
static func populate_room(room: Node, biome_index: int = -1) -> Array[LorePage]:
	var spawned: Array[LorePage] = []
	if not NetworkManager.is_host:
		return spawned
	if room == null:
		push_warning("[story] LORE populator called with no room")
		return spawned
	var resolved := biome_index
	if resolved < 0:
		var run: RunState = GameState.run
		if run == null:
			return spawned
		resolved = run.biome_index
	var page := _next_page_for_biome(resolved)
	if page.is_empty():
		return spawned
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		push_warning("[story] LORE populator could not load %s" % SCENE_PATH)
		return spawned
	var spawned_page: LorePage = packed.instantiate() as LorePage
	if spawned_page == null:
		push_warning("[story] %s does not instantiate as a LorePage" % SCENE_PATH)
		return spawned
	spawned_page.page_id = StringName(String(page["id"]))
	spawned_page.biome = int(page["biome"])
	# TODO(floor-generation, W3-A2): sit on RoomSpec's interactable anchor once
	# Room exposes it; the room's origin is the stand-in, as it is for the chest.
	spawned_page.position = Vector2.ZERO
	room.add_child(spawned_page)
	spawned.append(spawned_page)
	return spawned


## The registered populator, in the `Callable(room: Room) -> void` shape
## SPEC-floor-generation declares. Thin on purpose: `populate_room` carries the
## body, and the room does not choose the page because the spec does.
static func _populate_lore_room(room: Node) -> void:
	populate_room(room)


## Notes the blocked path once per process.
static func _note_blocked(detail: String) -> void:
	if _blocker_logged:
		return
	_blocker_logged = true
	push_warning("[story] LORE populator not registered — %s" % RoomPopulator.blocker_line(detail))


# --- the catalog -------------------------------------------------------------


## Every page under `data/lore/`, sorted by `order`, read once per process. A
## test's override wins while it is set; the real folder is scanned only when
## the override is empty.
static func catalog() -> Array[Dictionary]:
	if not _catalog_override.is_empty():
		return _catalog_override
	if _catalog_loaded:
		return _catalog
	_catalog = catalog_at(LORE_DIR)
	_catalog_loaded = true
	return _catalog


## Reads and validates every `*.json` under `dir_path`. Each page must carry the
## full shape SPEC-story-dialogue names — `{id, title, body, biome, act,
## order}` — and a page that does not (or a duplicate `order` within one biome)
## is warned about and skipped, never half-loaded, so bad content cannot enter
## the game. An empty or missing directory is simply no pages.
static func catalog_at(dir_path: String) -> Array[Dictionary]:
	var pages: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return pages
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return pages
	var seen: Dictionary = {}
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var page := _page_at(dir_path.path_join(file_name))
		if page.is_empty():
			continue
		var placement := "%d/%d" % [int(page["biome"]), int(page["order"])]
		if seen.has(placement):
			push_warning("[story] %s repeats biome/order %s; skipped" % [file_name, placement])
			continue
		seen[placement] = true
		pages.append(page)
	pages.sort_custom(_order_before)
	return pages


## One page off `path`, or an empty dictionary when the file does not hold a
## valid one. Split from the scan so a case can pin one file's verdict. The
## parse goes through `JSON.new().parse()` rather than `JSON.parse_string` so a
## malformed file is a warning here, not an engine error a test would eat.
static func _page_at(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[story] %s does not exist" % path)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK \
			or not (json.data is Dictionary):
		push_warning("[story] %s is not a JSON object" % path)
		return {}
	var raw := json.data as Dictionary
	for field: String in ["id", "title", "body"]:
		var value: Variant = raw.get(field)
		if not (value is String) or (value as String).is_empty():
			push_warning("[story] %s has no usable \"%s\"" % [path, field])
			return {}
	for field: String in ["biome", "act", "order"]:
		# JSON numbers arrive as float, so a whole one is an index and a
		# fractional one (or anything else) is a mistyped field.
		var number: Variant = raw.get(field)
		if not ((number is int) or (number is float)) \
				or float(number) != roundf(float(number)):
			push_warning("[story] %s has no integer \"%s\"" % [path, field])
			return {}
	var biome := int(raw["biome"])
	var act := int(raw["act"])
	var order := int(raw["order"])
	if biome < MIN_BIOME or biome > MAX_BIOME:
		push_warning("[story] %s has biome %d outside %d..%d" % [path, biome, MIN_BIOME, MAX_BIOME])
		return {}
	if act < MIN_ACT or act > MAX_ACT:
		push_warning("[story] %s has act %d outside %d..%d" % [path, act, MIN_ACT, MAX_ACT])
		return {}
	if order < 0:
		push_warning("[story] %s has a negative order" % path)
		return {}
	return {
		"id": StringName(raw["id"]),
		"title": raw["title"],
		"body": raw["body"],
		"biome": biome,
		"act": act,
		"order": order,
	}


## The lowest-order unread page for `biome_index`, or an empty dictionary when
## every page of that biome has been read (or the catalog holds none of it).
## Scans for the minimum rather than trusting sort order, so an unsorted catalog
## (a test's pinned set) still answers with the lowest order.
static func _next_page_for_biome(biome_index: int) -> Dictionary:
	var read_ids: Array[String] = []
	var profile := SaveManager.profile
	if profile != null:
		read_ids = profile.lore_unlocked
	var best: Dictionary = {}
	for page: Dictionary in catalog():
		if int(page["biome"]) != biome_index:
			continue
		if read_ids.has(String(page["id"])):
			continue
		if best.is_empty() or int(page["order"]) < int(best["order"]):
			best = page
	return best


## Test hook: pins `pages` as the whole catalog until `reset_catalog()`.
static func set_catalog_override(pages: Array[Dictionary]) -> void:
	_catalog_override = pages


## Drops the test override and the cached scan, so one case's catalog is never
## another case's starting state.
static func reset_catalog() -> void:
	_catalog_override = []
	_catalog = []
	_catalog_loaded = false


## True when the catalog sorts `a` before `b`.
static func _order_before(a: Dictionary, b: Dictionary) -> bool:
	return int(a["order"]) < int(b["order"])
