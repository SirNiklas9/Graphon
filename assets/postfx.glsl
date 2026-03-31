#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec2 resolution;
uniform float time;

// Effect toggles
uniform int enableBloom;
uniform int enableScanlines;
uniform int enableChromatic;

// Bloom
uniform float bloomIntensity;
uniform float bloomThreshold;

// Scanlines
uniform float scanlineIntensity;

// Chromatic aberration
uniform float aberrationAmount;

void main() {
    vec2 texelSize = 1.0 / resolution;
    vec2 uv = fragTexCoord;

    // --- Chromatic aberration (applied to UV before sampling) ---
    vec4 color;
    if (enableChromatic == 1) {
        float offset = aberrationAmount;
        float r = texture(texture0, uv + vec2(offset, 0.0) * texelSize).r;
        float g = texture(texture0, uv).g;
        float b = texture(texture0, uv - vec2(offset, 0.0) * texelSize).b;
        color = vec4(r, g, b, 1.0);
    } else {
        color = texture(texture0, uv);
    }

    // --- Bloom ---
    if (enableBloom == 1) {
        vec4 bloom = vec4(0.0);
        float count = 0.0;
        for (int x = -2; x <= 2; x++) {
            for (int y = -2; y <= 2; y++) {
                vec4 s = texture(texture0, uv + vec2(float(x), float(y)) * texelSize);
                float brightness = dot(s.rgb, vec3(0.2126, 0.7152, 0.0722));
                if (brightness > bloomThreshold) {
                    bloom += s;
                    count += 1.0;
                }
            }
        }
        if (count > 0.0) bloom /= count;
        color.rgb += bloom.rgb * bloomIntensity;
    }

    // --- Scanlines ---
    if (enableScanlines == 1) {
        float scanline = sin(uv.y * resolution.y * 3.14159) * 0.5 + 0.5;
        scanline = mix(1.0, scanline, scanlineIntensity);
        color.rgb *= scanline;

        // Vignette
        vec2 centered = uv * 2.0 - 1.0;
        float vignette = 1.0 - dot(centered, centered) * 0.3;
        color.rgb *= vignette;
    }

    finalColor = vec4(color.rgb, 1.0);
}
