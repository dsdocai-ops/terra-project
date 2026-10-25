shader_type canvas_item;
// White/gold/red hit flash overlay for sprites and polygons (combat-core, C1).
// flash_amount runs 1.0 -> 0.0 over the flash frames (HitFlash drives it);
// flash_color is white for a normal hit, gold for a crit, red for a player
// hurt. The sprite's own alpha is kept so transparent pixels stay clear.

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(base.rgb, flash_color.rgb, flash_amount), base.a);
}
