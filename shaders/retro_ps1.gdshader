shader_type canvas_item;

uniform float pixel_size : hint_range(1.0, 16.0) = 3.0;
uniform int color_depth : hint_range(1, 32) = 12;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

const float bayer_matrix[16] = float[16](
	0.0/16.0, 8.0/16.0, 2.0/16.0, 10.0/16.0,
	12.0/16.0, 4.0/16.0, 14.0/16.0, 6.0/16.0,
	3.0/16.0, 11.0/16.0, 1.0/16.0, 9.0/16.0,
	15.0/16.0, 7.0/16.0, 13.0/16.0, 5.0/16.0
);

// High frequency noise for film grain
float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

void fragment() {
	// Pixelation
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 grid = floor(UV * resolution / pixel_size) * pixel_size;
	vec2 pixelated_uv = grid / resolution;
	
	vec4 color = texture(screen_texture, pixelated_uv);
	
	// Bayer Dithering
	int x = int(mod(grid.x, 4.0));
	int y = int(mod(grid.y, 4.0));
	float bayer = bayer_matrix[y * 4 + x] - 0.5;
	float dither_strength = 0.15;
	color.rgb += bayer * dither_strength;
	
	// Film grain
	float noise = (random(pixelated_uv + vec2(TIME)) - 0.5) * 0.05;
	color.rgb += noise;
	
	// Color Quantization
	float depth = float(color_depth);
	color.rgb = floor(color.rgb * depth + 0.5) / depth;
	
	COLOR = color;
}
