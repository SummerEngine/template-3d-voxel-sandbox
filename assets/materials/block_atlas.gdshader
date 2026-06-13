shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

// 4x4 block atlas (assets/textures/blocks/atlas.png). The mesh stores each face's
// tile ORIGIN (col*0.25, row*0.25) in COLOR.rg, and UVs tile 0..N across the face;
// fract() keeps the sample inside the tile so big greedy-merged quads repeat cleanly.
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;

const float TILE = 0.25;        // 1/4 of the atlas per tile
const float INSET = 0.002;      // pull off the tile seam to avoid bleed

varying vec2 v_uv;
varying vec2 v_tile;

void vertex() {
	v_uv   = UV;
	v_tile = COLOR.rg;
}

void fragment() {
	vec2 local = clamp(fract(v_uv), INSET, 1.0 - INSET);
	vec2 uv = v_tile + local * TILE;
	ALBEDO    = texture(atlas, uv).rgb;
	ROUGHNESS = 1.0;
	METALLIC  = 0.0;
}
