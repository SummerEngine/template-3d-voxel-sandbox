shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

// Translucent, gently rippling water. Same 4x4 atlas as solid blocks (water tile origin
// arrives in COLOR.rg), but rendered as a separate transparent surface so you can see the
// bottom and it sways.
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
const float TILE = 0.125;
const float INSET = 0.002;

varying vec2 v_uv;
varying vec2 v_tile;

void vertex() {
	v_uv   = UV;
	v_tile = COLOR.rg;
	// Soft surface ripple driven by world position + time.
	VERTEX.y += sin(VERTEX.x * 0.7 + TIME * 1.3) * 0.05 + cos(VERTEX.z * 0.6 + TIME * 1.1) * 0.05;
}

void fragment() {
	vec2 local = clamp(fract(v_uv), INSET, 1.0 - INSET);
	vec2 uv = v_tile + local * TILE;
	ALBEDO = texture(atlas, uv).rgb;
	// Fresnel: water is near-clear looking straight down and brightens to a reflective sheet at
	// grazing angles. Modulates alpha (see-the-bottom overhead, opaque toward the horizon) and a
	// cool rim glow — the single biggest missing water "feel" cue. Fragment-only; no cull change.
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), normalize(NORMAL)), 0.0, 1.0), 4.0);
	ALBEDO += fres * 0.25 * vec3(0.6, 0.75, 0.9);   // grazing-angle rim glow
	ALPHA     = mix(0.5, 0.92, fres);               // clear overhead, brighter/denser at the horizon
	ROUGHNESS = mix(0.1, 0.02, fres);               // a touch glossier at grazing
	METALLIC  = 0.0;
}
