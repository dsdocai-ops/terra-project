shader_type canvas_item;
// Elite outline: a flat glow behind an elite's body (SPEC-enemies-ai "Elites").
// Minimal and functional; the real outline art is W4-A6's. Drawn by the enemy's
// EliteOutline polygon, which Enemy grows past the body (enemies-ai, W4-A1).

uniform vec4 outline_color : source_color = vec4(1.0, 0.82, 0.25, 0.9);

void fragment() {
	COLOR = outline_color;
}
