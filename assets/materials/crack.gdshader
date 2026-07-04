shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;

// Minecraft-style block-break overlay. A unit cube sits over the block being mined and
// draws a procedural crack network (Worley cell-edges) that spreads and darkens as the
// `progress` uniform climbs 0 -> 1. Triplanar world coords keep the cracks aligned on
// every face without needing per-face UVs.
uniform float progress = 0.0;
uniform vec3 crack_color = vec3(0.0);   // base crack tint: black normally, red when the pickaxe is too weak
uniform float alpha_mul = 1.0;          // break-pop fade multiplier driven by a tween (1.0 = normal mining)

varying vec3 v_world;
varying vec3 v_wnorm;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// F2 - F1 of a Worley pattern: ~0 along the borders between cells, which read as cracks.
float worley_edge(vec2 uv) {
	vec2 g = floor(uv);
	vec2 f = fract(uv);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 p = o + hash2(g + o) - f;
			float d = dot(p, p);
			if (d < f1) { f2 = f1; f1 = d; }
			else if (d < f2) { f2 = d; }
		}
	}
	return sqrt(f2) - sqrt(f1);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(v_wnorm);
	vec2 uv;
	if (n.x >= n.y && n.x >= n.z) uv = v_world.zy;
	else if (n.z >= n.y) uv = v_world.xy;
	else uv = v_world.xz;

	float edge = worley_edge(uv * 3.0);
	float w = mix(0.015, 0.14, clamp(progress, 0.0, 1.0));  // cracks widen as it nears breaking
	float crack = 1.0 - smoothstep(0.0, w, edge);
	crack *= smoothstep(0.02, 0.18, progress);              // fade in once mining actually starts

	// Colour ramp: normal cracks heat from dark toward a warm ember in the final ~40% (a clear
	// "one more hit" read); a red crack_color (too-weak pickaxe) is kept red throughout so
	// "you're wasting this block" stays legible instead of turning into a reward-ember.
	float hot = smoothstep(0.6, 1.0, progress);
	bool weak = crack_color.r > 0.2;
	ALBEDO = weak ? crack_color : mix(crack_color, vec3(0.5, 0.14, 0.03), hot);
	ALPHA = crack * (0.8 + hot * 0.15) * alpha_mul;   // slightly more opaque near break; alpha_mul drives the break pop
}
