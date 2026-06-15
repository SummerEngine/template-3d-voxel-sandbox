shader_type sky;

// Day/night sky: vertical gradient + sun disc/glow (from the scene's DirectionalLight) +
// procedural twinkling stars and a moon that fade in at night. DayNight drives the colors
// and `star_amount` (0 = day, 1 = night).
uniform vec3 top_color : source_color = vec3(0.30, 0.52, 0.86);
uniform vec3 horizon_color : source_color = vec3(0.78, 0.86, 0.95);
uniform vec3 ground_color : source_color = vec3(0.52, 0.46, 0.38);
uniform float star_amount = 0.0;
// Weather drives these: cloud_cover 0 = clear blue sky, 1 = fully overcast; cloud_time is a
// wind-driven drift offset so the cloud field slides across the sky.
uniform float cloud_cover = 0.0;
uniform float cloud_time = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.0 + vec2(7.3, 3.1);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;

	// Vertical gradient (sky above the horizon, ground tint below).
	vec3 col;
	if (up >= 0.0) {
		col = mix(horizon_color, top_color, pow(clamp(up, 0.0, 1.0), 0.5));
	} else {
		col = mix(horizon_color, ground_color, clamp(-up * 4.0, 0.0, 1.0));
	}

	// Sun disc + soft glow (LIGHT0_DIRECTION is the travel direction; the sun is opposite).
	if (LIGHT0_ENABLED) {
		float sd = dot(dir, -LIGHT0_DIRECTION);
		float disc = smoothstep(0.9990, 0.9996, sd);
		float glow = pow(clamp(sd, 0.0, 1.0), 220.0) * 0.6;
		col += (disc + glow) * LIGHT0_COLOR * LIGHT0_ENERGY;

		// Moon: a soft pale disc on the anti-sun side, visible at night.
		float md = dot(dir, LIGHT0_DIRECTION);
		float moon = smoothstep(0.9965, 0.9990, md);
		float moon_glow = pow(clamp(md, 0.0, 1.0), 800.0) * 0.4;
		col += (moon + moon_glow) * star_amount * vec3(0.92, 0.94, 1.0);
	}

	// Procedural twinkling stars in the upper hemisphere, fading in at night.
	if (up > 0.04 && star_amount > 0.001) {
		vec2 sc = dir.xz / (up + 0.25) * 34.0;
		vec2 cell = floor(sc);
		float h = hash21(cell);
		if (h > 0.985) {
			vec2 f = fract(sc) - 0.5;
			float star = smoothstep(0.13, 0.0, length(f));
			float tw = 0.6 + 0.4 * sin(TIME * 2.5 + h * 120.0);
			col += star * star_amount * tw;
		}
	}

	// Drifting clouds: fbm on the sky dome, coverage rises with cloud_cover (scattered white
	// puffs when low, dense grey overcast when high), darkening at night with the sun energy.
	if (up > 0.04 && cloud_cover > 0.001) {
		vec2 cp = dir.xz / (up + 0.22) * 1.15 + vec2(cloud_time, cloud_time * 0.35);
		float n = fbm(cp);
		float thr = mix(0.90, 0.24, cloud_cover);
		float d = smoothstep(thr, thr + 0.20, n);
		d *= smoothstep(0.03, 0.17, up);                 // fade into the horizon haze (kept low so clouds read in normal view)
		float lit = clamp(LIGHT0_ENERGY, 0.05, 1.5);
		vec3 ccol = mix(vec3(1.0), vec3(0.50, 0.52, 0.58), cloud_cover) * (0.35 + 0.65 * lit);
		col = mix(col, ccol, d);
	}

	COLOR = col;
}
