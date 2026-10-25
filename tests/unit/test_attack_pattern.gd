extends GutTest
## Data checks for every enemy and boss AttackPattern (SPEC-combat-core "Enemy
## attack contract"): a telegraphed windup of at least 0.2 s, a real active
## window, and a recovery of at least 0.3 s so every attack leaves the enemy
## punishable. Owned by combat-core. Runs over the `.tres` files, so a new
## pattern is checked the moment it is added.

const PATTERN_DIRS: Array[String] = ["res://data/enemies/attacks", "res://data/bosses/attacks"]
const MIN_RECOVERY_SECONDS: float = 0.3


func _all_patterns() -> Array[AttackPattern]:
	var found: Array[AttackPattern] = []
	for dir_path: String in PATTERN_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file: String in dir.get_files():
			if file.ends_with(".tres"):
				var pattern: AttackPattern = load("%s/%s" % [dir_path, file]) as AttackPattern
				if pattern != null:
					found.append(pattern)
	return found


func test_there_are_patterns_to_check() -> void:
	assert_gt(_all_patterns().size(), 2, "the enemy attacks are found")


func test_every_pattern_has_a_telegraphed_windup() -> void:
	for pattern: AttackPattern in _all_patterns():
		assert_gte(pattern.windup_seconds, AttackPattern.MIN_WINDUP, "%s windup" % pattern.id)


func test_every_pattern_has_a_real_active_window() -> void:
	for pattern: AttackPattern in _all_patterns():
		assert_gt(pattern.active_seconds, 0.0, "%s active_seconds" % pattern.id)


func test_every_pattern_leaves_a_punishable_recovery() -> void:
	for pattern: AttackPattern in _all_patterns():
		assert_gte(pattern.recovery_seconds, MIN_RECOVERY_SECONDS, "%s recovery_seconds" % pattern.id)


func test_every_enemys_patterns_are_covered_too() -> void:
	var dir := DirAccess.open(EnemyData.DATA_DIR)
	for sub: String in dir.get_directories():
		var biome_dir := DirAccess.open("%s/%s" % [EnemyData.DATA_DIR, sub])
		for file: String in biome_dir.get_files():
			if not file.ends_with(".tres"):
				continue
			var data: EnemyData = load("%s/%s/%s" % [EnemyData.DATA_DIR, sub, file]) as EnemyData
			if data == null:
				continue
			for pattern: AttackPattern in data.attacks:
				assert_gte(pattern.windup_seconds, AttackPattern.MIN_WINDUP, "%s / %s windup" % [data.id, pattern.id])
				assert_gt(pattern.active_seconds, 0.0, "%s / %s active" % [data.id, pattern.id])
				assert_gte(pattern.recovery_seconds, MIN_RECOVERY_SECONDS, "%s / %s recovery" % [data.id, pattern.id])


func test_the_checker_rejects_a_bad_pattern() -> void:
	var bad := AttackPattern.new()
	bad.windup_seconds = 0.1
	bad.active_seconds = 0.0
	bad.recovery_seconds = 0.1
	assert_lt(bad.windup_seconds, AttackPattern.MIN_WINDUP)
	assert_false(bad.active_seconds > 0.0)
	assert_lt(bad.recovery_seconds, MIN_RECOVERY_SECONDS)


func test_new_pattern_fields_default_to_a_light_hit_with_no_poise() -> void:
	var pattern := AttackPattern.new()
	assert_false(pattern.is_heavy)
	assert_eq(pattern.poise_damage, 0.0)
	assert_eq(AttackPattern.TelegraphShape.RING, 3, "RING is appended, existing .tres values keep their meaning")
