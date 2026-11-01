class_name FixtureClassSkill
extends ClassSkill
## Test fixture: a ClassSkill that counts how many times it performs, standing in
## for the real Shift skills (Battle Cry, Tumble Volley, Blink; W5-G10c) so the
## cooldown and the request path can be tested before they exist. Owned by
## classes-characters. Sync: none (test helper).

var performs: int = 0


func _perform() -> void:
	performs += 1
