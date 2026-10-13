extends Node3D
## Cel-shaded explosion for a destroyed mech (vela_model.gd explode()): a fireball of
## ink-rimmed blobs whose colour steps white -> yellow -> orange -> red -> smoke, a few
## lingering smoke puffs and a flash of light. Add it to the scene at the blast centre; it frees
## itself when done. The emitters start one frame after it enters the tree, so the caller can
## still place it after add_child().

const ToonFx := preload("res://scripts/toon_fx.gd")
const FIRE_INK := Color(0.28, 0.08, 0.04)
const SMOKE := Color(0.42, 0.38, 0.45)


func _ready() -> void:
	var fireball := ToonFx.burst(12, 0.8, 1.7,
		ToonFx.sprite_material(ToonFx.Shape.BLOB, {"ink_color": FIRE_INK, "ink_width": 0.1, "energy": 1.3}),
		[[0.0, Color(1.0, 0.97, 0.85)], [0.12, Color(1.0, 0.85, 0.3)], [0.3, Color(1.0, 0.52, 0.12)],
			[0.5, Color(0.9, 0.24, 0.08)], [0.68, SMOKE]],
		[Vector2(0.0, 0.3), Vector2(0.15, 1.0), Vector2(0.6, 0.85), Vector2(1.0, 0.0)])
	fireball.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fireball.emission_sphere_radius = 0.5
	fireball.initial_velocity_min = 3.0
	fireball.initial_velocity_max = 7.0
	fireball.damping_min = 6.0
	fireball.damping_max = 9.0
	fireball.gravity = Vector3(0, 2.5, 0)  # the fireball billows upward

	var smoke := ToonFx.burst(6, 1.6, 1.5,
		ToonFx.sprite_material(ToonFx.Shape.BLOB, {
			"ink_color": ToonFx.SMOKE_INK, "ink_width": 0.08, "puff": true, "wobble": 0.12,
			"shadow_tint": Color(0.65, 0.6, 0.72)}),
		[[0.0, SMOKE]],
		[Vector2(0.0, 0.0), Vector2(0.35, 1.0), Vector2(1.0, 0.0)])  # grows in as the fire dies
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.6
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 3.0
	smoke.damping_min = 1.5
	smoke.damping_max = 2.5
	smoke.gravity = Vector3(0, 2.0, 0)

	for p in [smoke, fireball]:
		add_child(p)
	_ignite.call_deferred([smoke, fireball])


func _ignite(emitters: Array) -> void:
	for p: CPUParticles3D in emitters:
		p.emitting = true
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.omni_range = 18.0
	light.light_energy = 0.0
	add_child(light)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 8.0, 0.05)
	tween.tween_property(light, "light_energy", 0.0, 0.5)
	get_tree().create_timer(1.8).timeout.connect(queue_free)
