#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float time;
uniform vec2 gridSize;

void main() {
    vec2 tc = vec2(fragTexCoord.x, 1.0 - fragTexCoord.y);
    vec2 cellCoord = floor(tc * gridSize);
    vec2 uv = cellCoord / gridSize;

    // Layer 0: Background gradient
    float brightness = 0.08 + uv.y * 0.1;
    vec3 color = vec3(brightness, brightness, brightness + 0.04);

    // Layer 1: World — static shapes
    if (uv.x > 0.05 && uv.x < 0.45 && uv.y > 0.35 && uv.y < 0.65) {
        color = mix(color, vec3(0.0, 0.0, 0.8), 0.75);
    }
    if (uv.x > 0.3 && uv.x < 0.6 && uv.y > 0.25 && uv.y < 0.55) {
        color = mix(color, vec3(0.0, 0.8, 0.0), 0.5);
    }

    // Layer 2: Entity — moving circle
    vec2 entityPos = vec2(0.5 + cos(time) * 0.2, 0.5 + sin(time * 0.7) * 0.15);
    float entityDist = length(uv - entityPos);
    if (entityDist < 0.06) {
        color = vec3(1.0, 0.0, 0.0);
    }

    // Layer 3: Effects — glow around entity
    float glowR = 0.1 + sin(time * 3.0) * 0.03;
    if (entityDist < glowR && entityDist > 0.06) {
        float glow = 1.0 - (entityDist - 0.06) / (glowR - 0.06);
        color += vec3(1.0, 0.9, 0.0) * glow * 0.6;
    }

    // Layer 4: UI text bars at top
    if (uv.y < 0.05 && uv.x < 0.4) {
        float bar = step(0.3, fract(uv.x * 30.0));
        color = mix(color, vec3(1.0), bar * 0.9);
    }
    if (uv.y > 0.08 && uv.y < 0.12 && uv.x < 0.6) {
        float bar = step(0.3, fract(uv.x * 40.0));
        color = mix(color, vec3(0.0, 1.0, 1.0), bar * 0.7);
    }

    vec3 c = clamp(color, 0.0, 1.0);
    float b = dot(c, vec3(0.299, 0.587, 0.114));
    int charIdx = 0;
    if (b > 0.875) charIdx = 0;
    else if (b > 0.625) charIdx = 1;
    else if (b > 0.375) charIdx = 2;
    else if (b > 0.125) charIdx = 3;
    finalColor = vec4(c, 1.0);
}
