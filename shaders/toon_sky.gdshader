shader_type sky;
// Cel-shaded sky for the toon world (main.tscn's WorldEnvironment): a flat-coloured gradient
// with a pale horizon band, a hard-edged sun disc with a flat halo ring (follows the Sun light),
// and drifting cartoon cumulus clouds. Each cloud is its own shape: a flat base with a row of
// round puffs on it (biggest in the middle) and a couple more on top, shaded white with a
// lavender shadow along the underside (and the side away from the sun) and a blue ink rim.
// Clouds sit in three rings around the sky (far / mid / high) that drift at different speeds;
// the far ring is hazed toward the horizon colour for depth. No textures. The ambient-light
// (radiance) pass skips the clouds and sun so lighting stays steady.

uniform vec3 zenith_color : source_color = vec3(0.2, 0.47, 0.92);
uniform vec3 sky_color : source_color = vec3(0.36, 0.64, 0.96);
uniform vec3 horizon_color : source_color = vec3(0.7, 0.86, 0.98);
uniform vec3 ground_color : source_color = vec3(0.25, 0.4, 0.22);
uniform vec3 sun_color : source_color = vec3(1.0, 0.97, 0.82);
uniform float sun_size = 0.035;          // disc radius, in radians-ish (distance on the unit sphere)
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow : source_color = vec3(0.78, 0.8, 0.95);
uniform vec3 cloud_ink : source_color = vec3(0.34, 0.44, 0.74);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.7;  // chance of a cloud in each slot
uniform float cloud_size = 1.0;          // scales every cloud
uniform float wind_speed = 0.004;        // drift around the sky, in radians per second
uniform float ink_pixels = 3.5;          // ink rim thickness on screen, like the outlines on props

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float smin(float a, float b, float k) {
	float h = max(k - abs(a - b), 0.0) / k;
	return min(a, b) - h * h * k * 0.25;
}

// One cartoon cumulus, > 0 inside. q is relative to the middle of its flat base, hw its
// half-width: five round puffs along the base (biggest in the middle), three on top, and the
// bottom cut flat with softly rounded corners (unless `puffs_only`, used for the shadow line).
float cumulus(vec2 q, float hw, float seed, bool puffs_only) {
	float d = -1.0;
	for (int i = 0; i < 5; i++) {
		float t = float(i) * 0.5 - 1.0;
		float r = hw * 0.4 * (1.0 - 0.45 * t * t) * (0.85 + 0.3 * hash(vec2(seed, float(i))));
		vec2 c = vec2(t * hw * 0.72, r * 0.5 + (1.0 - t * t) * hw * 0.1);
		d = max(d, r - length(q - c));
	}
	for (int i = 0; i < 3; i++) {
		float t = float(i) - 1.0;
		float r = hw * (0.2 + 0.1 * hash(vec2(seed, 7.0 + float(i))));
		vec2 c = hw * vec2(t * 0.36 + (hash(vec2(seed, 11.0 + float(i))) - 0.5) * 0.16,
				0.52 - 0.1 * abs(t) + 0.06 * hash(vec2(seed, 15.0 + float(i))));
		d = max(d, r - length(q - c));
	}
	return puffs_only ? d : smin(d, q.y, hw * 0.12);
}

// A ring of clouds around the sky: `count` slots in azimuth, each holding a cloud (by chance)
// whose base sits between elevations e_range.x and .y. `az` is the view azimuth (shifted by the
// ring's drift) and dir the matching view direction. Each cloud is drawn flat on a card facing
// the viewer, so its base stays a straight horizontal line. Returns (density, lit density): lit
// where the cloud is still there a little way away from the light, so the underside and the
// side away from the sun fall in shadow.
vec2 cloud_layer(float az, vec3 dir, float count, vec2 e_range, float seed, vec2 light) {
	float cell = TAU / count;
	float i = floor(az / cell);
	vec2 best = vec2(-1.0);
	for (int n = -1; n <= 1; n++) {
		float ci = i + float(n);
		vec2 h = vec2(mod(ci, count), seed);
		if (hash(h) > cloud_coverage) {
			continue;
		}
		float base_e = mix(e_range.x, e_range.y, hash(h + 3.1));
		float hw = cell * cos(base_e) * cloud_size * mix(0.24, 0.52, hash(h + 5.7));
		float cx = (ci + 0.5 + (hash(h + 1.9) - 0.5) * 0.4) * cell;
		vec3 centre = vec3(sin(cx) * cos(base_e), sin(base_e), cos(cx) * cos(base_e));
		vec3 across = vec3(cos(cx), 0.0, -sin(cx));
		float facing = dot(dir, centre);
		if (facing < 0.3) {
			continue;
		}
		vec2 q = vec2(dot(dir, across), dot(dir, cross(centre, across))) / facing;
		float s = h.x * 13.0 + seed;
		best.x = max(best.x, cumulus(q, hw, s, false));
		// The puffs alone, nudged toward the light: their round undersides give a scalloped
		// shadow line along the bottom.
		best.y = max(best.y, cumulus(q - light * hw * 0.32, hw, s, true));
	}
	return best;
}

// Paints one ring's clouds over `col`: white, shadow where unlit, ink at the rim, hazed by `haze`.
vec3 paint_clouds(vec3 col, vec2 c, float haze) {
	float ink = min(fwidth(c.x) * ink_pixels, 0.01);
	vec3 cloud = c.y > 0.0 ? cloud_color : cloud_shadow;
	cloud = c.x < ink ? cloud_ink : cloud;
	cloud = mix(cloud, horizon_color, haze);
	return c.x > 0.0 ? cloud : col;
}

// cloud_layer() for the view direction turned by `drift` around the vertical, so the ring moves.
vec2 ring(vec3 dir, float az, float drift, float count, vec2 e_range, float seed, vec2 light) {
	float a = mod(az + drift, TAU);
	float flat_len = length(dir.xz);
	return cloud_layer(a, vec3(sin(a) * flat_len, dir.y, cos(a) * flat_len), count, e_range, seed, light);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	// Sky: soft gradient from horizon to zenith, with a flat pale band right at the horizon.
	vec3 col = mix(sky_color, zenith_color, smoothstep(0.15, 0.75, h));
	col = mix(horizon_color, col, smoothstep(0.02, 0.2, h));
	col = mix(col, horizon_color, step(h, 0.04) * 0.6);
	if (h < 0.0) {
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.08, -h));
	}

	if (!AT_CUBEMAP_PASS) {
		// Sun: hard disc plus a flat, faint halo ring.
		if (LIGHT0_ENABLED) {
			float d = distance(dir, LIGHT0_DIRECTION);
			col = mix(col, mix(col, sun_color, 0.35), step(d, sun_size * 2.4));
			col = mix(col, sun_color * 1.4, step(d, sun_size));
		}
		// Clouds, far ring first so nearer ones overlap it; each ring drifts at its own speed.
		// Light comes from above and from the sun's side, in each cloud's (across, up) frame.
		float az = atan(dir.x, dir.z);
		vec3 sun = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
		vec2 light = normalize(vec2(dot(sun.xz, vec2(cos(az), -sin(az))), max(sun.y, 0.0) + 0.6));
		float drift = TIME * wind_speed;
		col = paint_clouds(col, ring(dir, az, drift * 0.5, 20.0, vec2(0.015, 0.07), 1.0, light), 0.25);
		col = paint_clouds(col, ring(dir, az, drift, 15.0, vec2(0.1, 0.3), 2.0, light), 0.1);
		col = paint_clouds(col, ring(dir, az, drift * 1.5, 8.0, vec2(0.36, 0.62), 3.0, light), 0.0);
	}
	COLOR = col;
}
