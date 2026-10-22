extends Node
## In-engine screenshot of the HUD and its screens with sample state (SPEC-art-audio
## review sheets). Needs a window (not --headless).
##   godot --path . --resolution 960x540 res://tools/art/capture_ui.tscn -- <out_dir>
## (a scene, not a -s script, so the autoloads exist when the HUD scripts compile)
## Writes hud.png, choice.png, vote.png, pause.png and menu.png into <out_dir>.

const HUD_SCENE := "res://scenes/ui/hud.tscn"

var _out_dir: String = "user://"
var _frames: int = 0
var _hud: Hud
var _background: ColorRect


class SampleModel:
	extends HudModel

	func refresh(_local_peer_id: int) -> void:
		local_hp_ratio = 0.68
		local_hp_current = 68
		local_hp_max = 100
		gold = 1240
		ore_total = 18
		echo_shards = 6
		floor_label = "FLOOR 3"
		biome_label = "Fungal Caverns"
		teammates.clear()
		for spec: Array in [["Mira", 0.9, false, 1], ["Okoye", 0.35, false, 2], ["Tam", 0.0, true, 3]]:
			var mate := HudTeammate.new()
			mate.display_name = spec[0]
			mate.hp_ratio = spec[1]
			mate.is_downed = spec[2]
			mate.slot = spec[3]
			teammates.append(mate)
		relics.clear()
		for spec: Array in [["ember_boots", 0, 1], ["spark_plug", 0, 3], ["mirror_step", 1, 1], ["soul_jar", 3, 1], ["domino", 2, 2], ["leech_fang", 4, 1]]:
			var relic := HudRelic.new()
			relic.id = spec[0]
			var data: RelicData = RelicFlow.data_for(relic.id)
			relic.display_name = data.display_name if data != null else String(relic.id)
			relic.icon = data.icon if data != null else null
			relic.rarity = spec[1]
			relic.stacks = spec[2]
			relics.append(relic)
		statuses.clear()
		for spec: Array in [[0, 2], [1, 1], [4, 3]]:
			var status := HudStatus.new()
			status.status = spec[0]
			status.stacks = spec[1]
			statuses.append(status)
		weapon_slots[0].display_name = "Pickaxe"
		weapon_slots[0].weapon_id = "pickaxe"
		weapon_slots[0].active = true
		weapon_slots[1].display_name = "Crossbow"
		weapon_slots[1].weapon_id = "crossbow"
		weapon_slots[1].cooldown_fraction = 0.4
		changed.emit()


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 1:
		var root: Window = get_tree().root
		root.size = Vector2i(960, 540)
		root.content_scale_size = Vector2i(960, 540)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		_background = ColorRect.new()
		_background.color = Color(0.32, 0.24, 0.16)
		_background.size = Vector2(960, 540)
		root.add_child(_background)
		_hud = (load(HUD_SCENE) as PackedScene).instantiate() as Hud
		_hud.hud_model = SampleModel.new()
		root.add_child(_hud)
		_hud.lantern_orb.mana_ratio = 0.6
		_hud.ability_row.ultimate_ratio = 0.72
		_hud.ability_row.potion_count = 2
		_hud.ability_row.has_active_relic = true
		var rooms: Array[Rect2i] = [Rect2i(5, 40, 14, 10), Rect2i(30, 40, 14, 10), Rect2i(52, 14, 14, 10), Rect2i(52, 66, 14, 10), Rect2i(76, 40, 14, 10)]
		_hud.lamp_map.rooms = rooms
	elif _frames == 6:
		_hud.currencies.queue_redraw()
	elif _frames == 8:
		_save("hud.png")
		var ids: Array[StringName] = [&"mirror_step", &"soul_jar", &"spark_plug"]
		_hud._open_choice(ids)
	elif _frames == 14:
		_save("choice.png")
		_hud.choice_popup.close()
		_hud.rope_vote_prompt.apply_votes({1: true, 2: true, 3: true, 4: false})
	elif _frames == 20:
		_save("vote.png")
		_hud.rope_vote_prompt.visible = false
		_hud.set_paused_view(true)
	elif _frames == 26:
		_save("pause.png")
		_hud.visible = false
		var menu: Control = (load("res://scenes/main/placeholder_menu.tscn") as PackedScene).instantiate() as Control
		get_tree().root.add_child(menu)
	elif _frames == 34:
		_save("menu.png")
		get_tree().quit()


func _save(file: String) -> void:
	var image: Image = get_tree().root.get_texture().get_image()
	image.save_png(_out_dir.path_join(file))
	print("captured %s" % file)
