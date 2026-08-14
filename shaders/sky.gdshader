shader_type sky;
void sky() {
    // 1. Make the entire background absolute pitch black
    COLOR = vec3(0.0); 
    
    // 2. Generate harsh, pixelated white stars using a noise threshold
    float noise = fract(sin(dot(EYEDIR, vec3(12.9898, 78.233, 45.164))) * 43758.5453);
    if (noise > 0.998) {
        COLOR = vec3(1.0); // Pure white star
    }
}
