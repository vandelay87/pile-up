// Draws a mask of solid shapes as one merged shape: a faint fill inside, and a single edge
// where the inside meets the outside, so overlapping shapes share one outline.
shader_type canvas_item;

uniform vec4 colour : source_color = vec4(1.0, 0.9, 0.4, 0.8);
uniform float fill_alpha = 0.1;
// The edge's width in mask pixels.
uniform float edge_width = 2.0;

void fragment() {
	float inside = texture(TEXTURE, UV).a;
	float outside_near = 0.0;
	for (int k = 0; k < 8; k++) {
		float angle = float(k) * 0.785398;
		vec2 offset = vec2(cos(angle), sin(angle)) * edge_width * TEXTURE_PIXEL_SIZE;
		outside_near = max(outside_near, 1.0 - texture(TEXTURE, UV + offset).a);
	}
	float edge = inside * outside_near;
	COLOR = vec4(colour.rgb, inside * mix(fill_alpha, colour.a, edge));
}
