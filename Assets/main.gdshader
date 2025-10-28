shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.9, 0.6, 1.0); // glow tint
uniform float intensity = 0.25;   // overall brightness
uniform float radius = 0.004;     // blur spread
uniform int samples = 6;          // glow softness (try 4–8)

void fragment() {
    vec4 base = texture(TEXTURE, UV);
    if (base.a < 0.01) {
        COLOR = vec4(0.0);
    } else {
        // build soft radial blur around text
        vec4 glow = vec4(0.0);
        for (int x = -samples; x <= samples; x++) {
            for (int y = -samples; y <= samples; y++) {
                float dist = length(vec2(float(x), float(y)));
                float weight = 1.0 - smoothstep(0.0, float(samples), dist);
                vec2 offset = vec2(float(x), float(y)) * radius;
                glow += texture(TEXTURE, UV + offset) * weight;
            }
        }

        glow *= glow_color * intensity / float((samples * 2 + 1) * (samples * 2 + 1));

        // blend glow behind text instead of over it
        COLOR = glow + base;
    }
}
