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
uniform float blood = 0.0;          // blood-moon strength (0..~0.85), driven by DayNight

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
		// Layered sun: a tight bloom-able core + a soft halo + a wide warm horizon aureole. Everything
		// is scaled by LIGHT0_ENERGY so the wide glow fades out at night/overcast (dir is still defined).
		float disc = smoothstep(0.9990, 0.9996, sd);
		float core = pow(clamp(sd, 0.0, 1.0), 600.0) * 3.0;     // only this is meant to cross 1.1 and bloom
		float halo = pow(clamp(sd, 0.0, 1.0), 40.0) * 0.5;
		float aureole = pow(clamp(sd, 0.0, 1.0), 6.0) * (1.0 - clamp(up, 0.0, 1.0)) * 0.35;
		vec3 sun_c = LIGHT0_COLOR * LIGHT0_ENERGY;
		col += (disc + core + halo) * sun_c;
		col += aureole * sun_c;
		col += pow(clamp(sd, 0.0, 1.0), 3.0) * 0.15 * sun_c;   // faint sky-wide warm air glow near the sun

		// Moon: pale by default, swelling into a crimson disc with a pulsing aureole on a blood moon.
		float md = dot(dir, LIGHT0_DIRECTION);
		float moon = smoothstep(mix(0.9965, 0.992, blood), 0.9990, md);
		vec3 moonCol = mix(vec3(0.92, 0.94, 1.0), vec3(1.0, 0.12, 0.06), blood);
		col += (moon + pow(clamp(md, 0.0, 1.0), 800.0) * 0.4) * star_amount * moonCol;
		col += pow(clamp(md, 0.0, 1.0), 5.0) * blood * (0.6 + 0.3 * sin(TIME * 0.8)) * vec3(0.9, 0.1, 0.05);
	}

	// Procedural twinkling stars in the upper hemisphere, fading in at night.
	if (up > 0.04 && star_amount > 0.001) {
		vec2 sc = dir.xz / (up + 0.25) * 34.0;
		vec2 cell = floor(sc);
		float h = hash21(cell);
		if (h > 0.985) {
			vec2 f = fract(sc) - 0.5;
			float r = mix(0.07, 0.16, hash21(cell + 3.7));        // varied star size
			float star = smoothstep(r, 0.0, length(f));
			float tw = 0.6 + 0.4 * sin(TIME * 2.5 + h * 120.0);
			vec3 scol = mix(vec3(1.0, 0.85, 0.7), vec3(0.7, 0.8, 1.0), hash21(cell + 11.3));  // colour temp
			float energy = h > 0.997 ? 1.4 : 0.8;                 // a few bright stars cross 1.1 and bloom
			col += star * star_amount * tw * energy * scol;
		}
		// Faint Milky Way band arcing across the dome (night-only, so free by day).
		vec3 bn = normalize(vec3(0.4, 0.7, 0.55));
		float band = smoothstep(0.35, 0.0, abs(dot(normalize(dir), bn)));
		col += band * fbm(dir.xz * 2.0) * star_amount * 0.12 * vec3(0.85, 0.88, 1.0);
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
