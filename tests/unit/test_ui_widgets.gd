extends GutTest
## Unit tests for the redesigned UI's pure logic: the palette, the lantern's
## liquid polygon, currency formatting, the relic rope's charm rules, the choice
## popup's selection/arming, the carved menu and the rope vote tally.
## Owned by ui-hud (Dev B). Drawing itself is checked by launching the game.


func test_every_rarity_has_a_distinct_colour() -> void:
	var seen: Dictionary[Color, bool] = {}
	for rarity: int in RelicData.Rarity.values():
		seen[UiPalette.rarity_color(rarity)] = true
	assert_eq(seen.size(), RelicData.Rarity.values().size())


func test_every_status_has_a_colour_and_a_label() -> void:
	for status: int in StatusEffects.Status.values():
		assert_ne(UiPalette.status_label(status), "???", "status %d has a label" % status)
	assert_eq(UiPalette.STATUS_COLORS.size(), StatusEffects.Status.values().size())
	assert_eq(UiPalette.STATUS_LABELS.size(), StatusEffects.Status.values().size())


func test_liquid_is_empty_when_nothing_to_draw() -> void:
	assert_eq(UiPalette.liquid_polygon(40.0, 0.0, 0.0).size(), 0)
	assert_eq(UiPalette.liquid_polygon(0.0, 1.0, 0.0).size(), 0)


func test_liquid_stays_inside_the_circle_and_rises_with_the_ratio() -> void:
	var radius: float = 40.0
	var low := UiPalette.liquid_polygon(radius, 0.25, 0.0)
	var high := UiPalette.liquid_polygon(radius, 0.75, 0.0)
	assert_gte(low.size(), 3)
	for point: Vector2 in high:
		assert_lte(point.length(), radius + 0.01, "every liquid point is inside the glass")
	assert_lt(_top_of(high), _top_of(low), "a fuller orb has a higher surface (smaller y)")


func test_a_full_lantern_has_a_flat_surface() -> void:
	var full := UiPalette.liquid_polygon(40.0, 1.0, 1.7)
	assert_almost_eq(_top_of(full), -40.0, 0.5)


func _top_of(points: PackedVector2Array) -> float:
	var top: float = INF
	for point: Vector2 in points:
		top = minf(top, point.y)
	return top


func test_currency_amounts_get_thousands_separators() -> void:
	assert_eq(CurrencyReadout.format_amount(0), "0")
	assert_eq(CurrencyReadout.format_amount(999), "999")
	assert_eq(CurrencyReadout.format_amount(1240), "1,240")
	assert_eq(CurrencyReadout.format_amount(1000000), "1,000,000")
	assert_eq(CurrencyReadout.format_amount(-1500), "-1,500")


func test_run_clock_formats_minutes_and_seconds() -> void:
	assert_eq(RunSummary.format_clock(0), "0:00")
	assert_eq(RunSummary.format_clock(862), "14:22")
	assert_eq(RunSummary.format_clock(-5), "0:00")


func test_relic_rope_folds_extra_charms_into_a_count() -> void:
	var rope := RelicRope.new()
	add_child_autofree(rope)
	var held: Array[HudModel.HudRelic] = []
	for index: int in RelicRope.MAX_CHARMS + 3:
		var relic := HudModel.HudRelic.new()
		relic.display_name = "Relic %d" % index
		held.append(relic)
	rope.relics = held
	assert_eq(rope.visible_charm_count(), RelicRope.MAX_CHARMS)
	assert_eq(rope.overflow_text(), "+3")
	rope.relics = []
	assert_eq(rope.overflow_text(), "")


func test_every_rarity_gets_its_own_charm_shape() -> void:
	var sizes: Dictionary[int, int] = {}
	for rarity: int in RelicData.Rarity.values():
		var shape := RelicRope.charm_shape(rarity, 10.0)
		assert_gte(shape.size(), 3, "rarity %d has a polygon" % rarity)
		sizes[rarity] = shape.size()
	assert_ne(sizes[RelicData.Rarity.RARE], sizes[RelicData.Rarity.EPIC])


func test_tablet_polygon_is_an_arch() -> void:
	var tablet := ChoicePopup.tablet_polygon(100.0, 140.0)
	assert_gt(tablet.size(), 8)
	var top: float = INF
	for point: Vector2 in tablet:
		top = minf(top, point.y)
	assert_almost_eq(top, -70.0, 0.5, "the arch peaks at the top of the tablet")


func test_choice_popup_ignores_input_until_armed() -> void:
	var popup := ChoicePopup.new()
	add_child_autofree(popup)
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cards: Array[ChoiceOption] = []
	for index: int in 3:
		var option := ChoiceOption.new()
		option.title = "Card %d" % index
		cards.append(option)
	popup.open(cards)
	assert_true(popup.visible)
	assert_eq(popup.selected, 1, "the middle card starts highlighted")
	assert_false(popup.choose(1), "the press that opened the screen cannot pick")
	popup._armed_at_msec = Time.get_ticks_msec() - 1000
	_picks.clear()
	popup.picked.connect(_on_picked)
	assert_true(popup.choose(2))
	assert_eq(_picks, [2])


var _picks: Array[int] = []


func _on_picked(index: int) -> void:
	_picks.append(index)


func test_choice_popup_selection_wraps() -> void:
	var popup := ChoicePopup.new()
	add_child_autofree(popup)
	var cards: Array[ChoiceOption] = [ChoiceOption.new(), ChoiceOption.new(), ChoiceOption.new()]
	popup.open(cards)
	popup.selected = 2
	popup.move_selection(1)
	assert_eq(popup.selected, 0)
	popup.move_selection(-1)
	assert_eq(popup.selected, 2)


func test_choice_popup_refuses_a_card_with_a_reason() -> void:
	var popup := ChoicePopup.new()
	add_child_autofree(popup)
	var blocked := ChoiceOption.new()
	blocked.disabled_reason = "Max stacks"
	var cards: Array[ChoiceOption] = [blocked]
	popup.open(cards)
	popup._armed_at_msec = Time.get_ticks_msec() - 1000
	assert_false(popup.choose(0))


var _dismissals: int = 0


func _on_dismissed() -> void:
	_dismissals += 1


func _armed_popup(cards: Array[ChoiceOption]) -> ChoicePopup:
	var popup := ChoicePopup.new()
	add_child_autofree(popup)
	popup.size = Vector2(640, 360)
	popup.open(cards)
	popup._armed_at_msec = Time.get_ticks_msec() - 1000
	_dismissals = 0
	popup.dismissed.connect(_on_dismissed)
	return popup


func _click(at: Vector2, button: MouseButton) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = button
	click.pressed = true
	click.position = at
	return click


func test_a_blocked_only_card_can_still_be_left_with_esc() -> void:
	var blocked := ChoiceOption.new()
	blocked.disabled_reason = "Max stacks"
	var popup := _armed_popup([blocked])
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	popup._gui_input(cancel)
	assert_eq(_dismissals, 1, "Esc leaves even when no card can be taken")


func test_a_click_off_the_cards_or_a_right_click_leaves_the_choice() -> void:
	var popup := _armed_popup([ChoiceOption.new()])
	popup._gui_input(_click(Vector2(2, 2), MOUSE_BUTTON_LEFT))
	assert_eq(_dismissals, 1, "a left click off every card leaves")
	popup._gui_input(_click(popup.tablet_rect(0).get_center(), MOUSE_BUTTON_RIGHT))
	assert_eq(_dismissals, 2, "a right click leaves")


func test_a_click_on_a_card_takes_it_rather_than_leaving() -> void:
	var popup := _armed_popup([ChoiceOption.new()])
	_picks.clear()
	popup.picked.connect(_on_picked)
	popup._gui_input(_click(popup.tablet_rect(0).get_center(), MOUSE_BUTTON_LEFT))
	assert_eq(_picks, [0])
	assert_eq(_dismissals, 0)


func test_the_press_that_opened_the_choice_cannot_leave_it() -> void:
	var popup := _armed_popup([ChoiceOption.new()])
	popup._armed_at_msec = Time.get_ticks_msec()
	assert_false(popup.dismiss())
	assert_eq(_dismissals, 0)


func test_declining_an_offer_drops_it_so_nothing_reopens_it() -> void:
	RelicFlow.reset()
	var ids: Array[StringName] = [&"some_relic"]
	var holder := Node.new()
	add_child_autofree(holder)
	RelicFlow.record_offer(1, ids, holder, null)
	assert_true(RelicFlow.has_offer(1))
	assert_true(RelicFlow.decline(1))
	assert_false(RelicFlow.has_offer(1))
	assert_false(RelicFlow.decline(1), "nothing left to decline")
	RelicFlow.reset()


func test_choice_options_are_built_from_relic_data() -> void:
	var ids: Array[StringName] = [&"ember_boots", &"no_such_relic"]
	var options := ChoiceOption.from_relic_ids(ids)
	assert_eq(options.size(), 1, "an id without data is skipped")
	assert_eq(options[0].id, &"ember_boots")
	assert_ne(options[0].title, "")


func test_carved_menu_wraps_and_bows() -> void:
	var menu := CarvedMenu.new()
	add_child_autofree(menu)
	menu.items = ["Resume", "Quit Game"]
	menu.move_selection(-1)
	assert_eq(menu.selected, 1)
	menu.move_selection(1)
	assert_eq(menu.selected, 0)
	menu.items = ["a", "b", "c", "d"]
	assert_eq(menu.row_indent(0), 0.0)
	assert_gt(menu.row_indent(1), 0.0, "the middle rows bow out")


func test_rope_vote_counts_yes_answers_and_ignores_junk() -> void:
	var prompt := RopeVotePrompt.new()
	add_child_autofree(prompt)
	prompt.apply_votes({1: true, 2: true, 3: false, 4: "maybe"})
	assert_eq(prompt.agreed, 2)
	assert_eq(prompt.total, 4)
	assert_true(prompt.visible)
	prompt.apply_votes({})
	assert_false(prompt.visible, "an empty tally hides the prompt")


func test_lamp_map_places_rooms_around_the_centre() -> void:
	var map := LampMap.new()
	add_child_autofree(map)
	map.grid_tiles = 100
	map.rooms = [Rect2i(0, 0, 20, 20), Rect2i(40, 40, 20, 20), Rect2i(80, 80, 20, 20)]
	assert_lt(map.room_offset(0).x, 0.0)
	assert_almost_eq(map.room_offset(1).x, 0.0, 0.001)
	assert_gt(map.room_offset(2).x, 0.0)
	assert_eq(map.room_offset(9), Vector2.ZERO, "an unknown room reads as the centre")


# Pixel art: the font, the size grid and the icons

func test_font_sizes_snap_to_whole_steps_of_eight() -> void:
	assert_eq(UiPalette.snap_size(7), 8)
	assert_eq(UiPalette.snap_size(11), 8)
	assert_eq(UiPalette.snap_size(12), 16)
	assert_eq(UiPalette.snap_size(19), 16)
	assert_eq(UiPalette.snap_size(24), 24)


func test_the_ui_font_covers_every_character_the_ui_prints() -> void:
	var font := load("res://assets/fonts/sinkhole_pixel.fnt") as Font
	assert_not_null(font)
	var wanted: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,:;!?-+/%()'\"_<>=*#[]"
	for index: int in wanted.length():
		assert_true(font.has_char(wanted.unicode_at(index)), "glyph '%s'" % wanted[index])


func test_text_that_does_not_fit_drops_to_the_small_size() -> void:
	var font := load("res://assets/fonts/sinkhole_pixel.fnt") as Font
	assert_eq(UiPalette.fit_size(font, "Hi", 200.0), 16)
	assert_eq(UiPalette.fit_size(font, "A very long relic name indeed", 60.0), 8)


func test_every_status_has_a_pixel_icon() -> void:
	for status: int in StatusEffects.Status.values():
		var icon := UiPalette.status_icon(status)
		assert_not_null(icon, "status %d" % status)
		assert_eq(icon.get_size(), Vector2(16, 16))


func test_the_starting_weapons_potion_and_pointer_have_icons() -> void:
	for stem: String in ["weapon_pickaxe", "weapon_crossbow", "potion_flask", "pointer"]:
		assert_not_null(UiPalette.icon(stem), stem)
	assert_null(UiPalette.icon("no_such_icon"))

