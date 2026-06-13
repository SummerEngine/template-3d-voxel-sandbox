shader_type canvas_item;

// Makes the flat green chroma background of the logo transparent. A pixel is keyed
// out when green strongly dominates red and blue; the orange/blue/dark-outline
// letters are kept.
uniform float threshold : hint_range(0.0, 1.0) = 0.28;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float greenness = c.g - max(c.r, c.b);
	if (greenness > threshold) {
		c.a = 0.0;
	}
	COLOR = c;
}
