shader_type spatial;
render_mode cull_back, diffuse_lambert;

// 8x8 block atlas (assets/textures/blocks/atlas.png). The mesh stores each face's
// tile ORIGIN (col*0.125, row*0.125) in COLOR.rg, and UVs tile 0..N across the face;
// fract() keeps the sample inside the tile so big greedy-merged quads repeat cleanly.
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;

const float TILE = 0.125;       // 1/8 of the atlas per tile
const float INSET = 0.002;      // pull off the tile seam to avoid bleed

varying vec2 v_uv;
varying vec2 v_tile;
varying float v_bright;   // per-face ambient brightness (top bright, sides medium, bottom dark)

void vertex() {
	v_uv   = UV;
	v_tile = COLOR.rg;
	v_bright = COLOR.b;
}

void fragment() {
	vec2 local = clamp(fract(v_uv), INSET, 1.0 - INSET);
	vec2 uv = v_tile + local * TILE;
	vec3 tex  = texture(atlas, uv).rgb;
	ALBEDO    = tex * v_bright;
	ROUGHNESS = 1.0;
	METALLIC  = 0.0;
	// Per-tile EMISSION so hot/precious tiles bloom through the scene's HDR glow (hdr_threshold 1.1).
	// Tile index reconstructed from the per-face tile origin packed in COLOR.rg (col*0.125,row*0.125).
	int tile = int(round(v_tile.y * 8.0)) * 8 + int(round(v_tile.x * 8.0));
	if (tile == 26) {
		// Lava: animated heat pulse, bright enough to bloom (and light caves once lava is generated).
		EMISSION = tex * (2.2 + 0.6 * sin(TIME * 3.0 + (UV.x + UV.y) * 6.0));
	} else if (tile >= 16 && tile <= 19) {
		EMISSION = tex * 0.30;                         // ores: a faint self-glint in torchlight / dark caves
	} else if (tile == 5) {
		EMISSION = tex * (0.45 + 0.2 * sin(TIME * 2.0)); // furnace: a gently flickering forge mouth
	}
}
