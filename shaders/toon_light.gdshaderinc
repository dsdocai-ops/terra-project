// Shared cel-shading light() for the toon world (terrain, grass, rocks, trees).
// Diffuse light falls in hard bands (shadow / mid / lit) instead of a smooth falloff, and
// sun shadows land in the darkest band. No specular, so surfaces read as flat colour.

void light() {
	float intensity = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float band = 0.4 * smoothstep(0.02, 0.06, intensity) + 0.6 * smoothstep(0.42, 0.47, intensity);
	DIFFUSE_LIGHT += band * LIGHT_COLOR / PI;
}
