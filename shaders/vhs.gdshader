shader_type canvas_item;

uniform float noise_amount = 0.05;
uniform float scanline_intensity = 0.5;
uniform float color_bleed = 0.005;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 uv = SCREEN_UV;
	
	// Add horizontal color bleeding (chromatic aberration)
	vec4 color;
	color.r = texture(SCREEN_TEXTURE, uv + vec2(color_bleed, 0.0)).r;
	color.g = texture(SCREEN_TEXTURE, uv).g;
	color.b = texture(SCREEN_TEXTURE, uv - vec2(color_bleed, 0.0)).b;
	color.a = 1.0;
	
	// Scanlines
	float scanline = sin(uv.y * 800.0) * 0.04 * scanline_intensity;
	color.rgb -= scanline;
	
	// Noise/Film Grain
	float noise = fract(sin(dot(uv + vec2(TIME), vec2(12.9898, 78.233))) * 43758.5453);
	color.rgb += (noise - 0.5) * noise_amount;
	
	COLOR = color;
}
