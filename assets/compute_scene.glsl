#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float time;
uniform vec2 gridSize;
uniform vec2 resolution;
uniform vec2 cellSize;

// Hash for noise
float hash(vec2 p) {
    p = fract(p * vec2(443.8975, 397.2973));
    p += dot(p.xy, p.yx + 19.19);
    return fract(p.x * p.y);
}

// Signed distance functions for shapes
float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdCircle(vec2 p, float r) {
    return length(p) - r;
}

void main() {
    vec2 cellCoord = floor(fragTexCoord * gridSize);
    vec2 uv = cellCoord / gridSize;  // 0-1 normalized

    // Center UV
    vec2 p = uv * 2.0 - 1.0;
    p.x *= gridSize.x / gridSize.y; // aspect correct

    // Dark background
    vec3 color = vec3(0.08, 0.08, 0.1);

    // Animated ground plane (horizontal gradient at bottom)
    if (uv.y > 0.7) {
        float groundFade = (uv.y - 0.7) / 0.3;
        color = mix(color, vec3(0.15, 0.15, 0.2), groundFade);
    }

    // Spinning box
    float angle = time * 0.8;
    mat2 rot = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
    vec2 rp = rot * p;
    float box = sdBox(rp, vec2(0.3, 0.3));
    if (box < 0.0) {
        float shade = 0.6 + 0.4 * dot(normalize(rp + 0.001), vec2(0.7, 0.7));
        color = vec3(0.9, 0.2, 0.15) * shade;
    }

    // Orbiting circles
    for (int i = 0; i < 4; i++) {
        float a = time * 0.5 + float(i) * 1.5708;
        vec2 cp = vec2(cos(a), sin(a)) * 0.7;
        float circle = sdCircle(p - cp, 0.1);
        if (circle < 0.0) {
            vec3 cColors[4] = vec3[](
                vec3(0.2, 0.8, 0.3),
                vec3(0.2, 0.4, 0.9),
                vec3(0.1, 0.8, 0.8),
                vec3(0.9, 0.8, 0.1)
            );
            color = cColors[i];
        }
    }

    // Point light glow from orbiting light
    vec2 lightPos = vec2(cos(time * 0.7), sin(time * 0.7)) * 0.5;
    float lightDist = length(p - lightPos);
    vec3 lightColor = vec3(1.0, 0.6, 0.3);
    color += lightColor * 0.15 / (lightDist * lightDist + 0.1);

    // Particle-like sparkles
    for (int i = 0; i < 8; i++) {
        float seed = float(i) * 7.13;
        vec2 sparklePos = vec2(
            sin(time * 1.3 + seed) * 0.8,
            cos(time * 0.9 + seed * 1.7) * 0.6
        );
        float d = length(p - sparklePos);
        float sparkle = 0.003 / (d * d + 0.005);
        sparkle *= 0.5 + 0.5 * sin(time * 5.0 + seed);
        color += vec3(1.0, 0.9, 0.5) * sparkle;
    }

    // Subtle noise grain
    float noise = hash(cellCoord + floor(time * 60.0)) * 0.03;
    color += noise;

    finalColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
