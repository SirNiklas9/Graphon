#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float time;
uniform vec2 gridSize;

float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdCircle(vec2 p, float r) {
    return length(p) - r;
}

float sdLine(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

void main() {
    vec2 tc = vec2(fragTexCoord.x, 1.0 - fragTexCoord.y);
    vec2 cellCoord = floor(tc * gridSize);
    vec2 uv = cellCoord / gridSize;
    vec2 p = uv;

    vec3 color = vec3(0.125); // dark bg

    // Title area (top)
    if (uv.y < 0.15) {
        // "GRAPHON" text placeholder — bright bar
        if (uv.x > 0.02 && uv.x < 0.35 && uv.y > 0.02 && uv.y < 0.12) {
            float stripe = step(0.5, fract(uv.x * 20.0));
            color = mix(vec3(0.8, 0.8, 0.8), vec3(1.0), stripe);
        }
    }

    // Blue filled rect
    vec2 rectCenter = vec2(0.15, 0.4);
    if (sdBox(p - rectCenter, vec2(0.08, 0.08)) < 0.0) {
        color = vec3(0.0, 0.0, 1.0) * 0.75;
    }
    // Cyan outline
    float rectDist = abs(sdBox(p - rectCenter, vec2(0.08, 0.08)));
    if (rectDist < 0.005) color = vec3(0.0, 1.0, 1.0);

    // Red filled circle
    vec2 circCenter = vec2(0.35, 0.4);
    if (sdCircle(p - circCenter, 0.06) < 0.0) {
        color = vec3(1.0, 0.0, 0.0) * 0.5 + color * 0.5;
    }
    // Yellow outline
    if (abs(sdCircle(p - circCenter, 0.06)) < 0.005) color = vec3(1.0, 1.0, 0.0);

    // Crossing lines
    if (sdLine(p, vec2(0.5, 0.25), vec2(0.7, 0.55)) < 0.004) color = vec3(0.0, 1.0, 0.0);
    if (sdLine(p, vec2(0.5, 0.55), vec2(0.7, 0.25)) < 0.004) color = vec3(1.0, 0.0, 1.0);

    // Hearts (diamond shapes)
    vec2 h1 = vec2(0.8, 0.35);
    vec2 h2 = vec2(0.9, 0.35);
    float heart1 = abs(p.x - h1.x) + abs(p.y - h1.y);
    float heart2 = abs(p.x - h2.x) + abs(p.y - h2.y);
    if (heart1 < 0.03) color = vec3(1.0, 0.0, 0.0);
    if (heart2 < 0.03) color = vec3(0.0, 0.0, 1.0);

    // Opacity gradient bar at bottom
    if (uv.y > 0.85 && uv.y < 0.9 && uv.x > 0.05 && uv.x < 0.55) {
        float grad = (uv.x - 0.05) / 0.5;
        color = mix(vec3(0.125), vec3(1.0), grad);
    }

    // Text rows (horizontal bars representing text)
    for (int i = 0; i < 4; i++) {
        float ty = 0.55 + float(i) * 0.07;
        if (uv.y > ty && uv.y < ty + 0.04 && uv.x > 0.02 && uv.x < 0.5) {
            float charPattern = step(0.3, fract(uv.x * 50.0 + float(i) * 3.0));
            vec3 textColors[4] = vec3[](
                vec3(1.0), vec3(1.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0)
            );
            color = mix(color, textColors[i], charPattern * 0.8);
        }
    }

    finalColor = vec4(color, 1.0);
}
