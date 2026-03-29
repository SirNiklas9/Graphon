#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float time;
uniform vec2 gridSize;

float hash(vec2 p) {
    p = fract(p * vec2(443.8975, 397.2973));
    p += dot(p.xy, p.yx + 19.19);
    return fract(p.x * p.y);
}

float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdCircle(vec2 p, float r) {
    return length(p) - r;
}

// Smooth min for organic blending
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D-like sphere with lighting
float sphere3D(vec2 p, vec2 center, float r) {
    float d = length(p - center);
    if (d > r) return 0.0;
    // Fake 3D: brightness from pseudo-normal
    float nz = sqrt(1.0 - (d/r) * (d/r));
    vec2 n2d = (p - center) / r;
    // Light from upper-left
    float light = max(dot(vec3(n2d, nz), normalize(vec3(-0.5, -0.6, 0.8))), 0.0);
    return 0.15 + light * 0.85;
}

void main() {
    vec2 tc = vec2(fragTexCoord.x, 1.0 - fragTexCoord.y);
    vec2 cellCoord = floor(tc * gridSize);
    vec2 uv = cellCoord / gridSize;
    vec2 p = uv * 2.0 - 1.0;
    float aspect = gridSize.x / gridSize.y;
    p.x *= aspect;

    vec3 color = vec3(0.0);

    // === BACKGROUND: subtle gradient ===
    color = vec3(0.02 + uv.y * 0.06, 0.02 + uv.y * 0.04, 0.04 + uv.y * 0.08);

    // === SECTION 1 (left): Gradient bars showing density character transitions ===
    if (uv.x < 0.25) {
        // Vertical gradient bars in different colors
        float barWidth = 0.05;
        int barIdx = int(uv.x / barWidth);
        vec3 barColors[5] = vec3[](
            vec3(1.0, 0.2, 0.1),
            vec3(0.1, 0.8, 0.2),
            vec3(0.2, 0.4, 1.0),
            vec3(1.0, 0.8, 0.1),
            vec3(0.8, 0.2, 0.8)
        );
        float brightness = 1.0 - uv.y; // top bright, bottom dark
        color = barColors[barIdx % 5] * brightness;
    }

    // === SECTION 2 (center-left): 3D spheres with smooth lighting ===
    if (uv.x > 0.25 && uv.x < 0.5) {
        vec2 sp = (uv - vec2(0.375, 0.5)) * 4.0;

        // Main sphere
        float s1 = sphere3D(sp, vec2(0.0, -0.3), 0.8);
        if (s1 > 0.0) color = vec3(0.9, 0.15, 0.1) * s1;

        // Small orbiting sphere
        vec2 orbitPos = vec2(cos(time * 1.5) * 0.6, sin(time * 1.5) * 0.6 - 0.3);
        float s2 = sphere3D(sp, orbitPos, 0.3);
        if (s2 > 0.0) color = vec3(0.1, 0.7, 0.9) * s2;

        // Tiny highlight sphere
        float s3 = sphere3D(sp, vec2(0.3, 0.5), 0.15);
        if (s3 > 0.0) color = vec3(1.0, 0.9, 0.3) * s3;
    }

    // === SECTION 3 (center-right): Sharp geometric shapes — edges trigger fractional/quarter blocks ===
    if (uv.x > 0.5 && uv.x < 0.75) {
        vec2 gp = (uv - vec2(0.625, 0.5)) * 4.0;

        // Rotating rectangle
        float a = time * 0.7;
        mat2 rot = mat2(cos(a), -sin(a), sin(a), cos(a));
        float box = sdBox(rot * gp, vec2(0.5, 0.3));
        if (box < 0.0) color = vec3(0.0, 0.8, 0.4) * (0.5 + 0.5 * cos(box * 10.0));

        // Diamond (rotated square)
        float a2 = 0.785; // 45 degrees
        mat2 rot2 = mat2(cos(a2), -sin(a2), sin(a2), cos(a2));
        float diamond = sdBox(rot2 * (gp + vec2(0.0, 0.8)), vec2(0.25, 0.25));
        if (diamond < 0.0) color = vec3(1.0, 0.5, 0.0);

        // Triangle approximation (3 intersecting half-planes)
        vec2 tp = gp + vec2(0.0, -0.7);
        float tri = max(max(-tp.y - 0.3, tp.x * 0.866 + tp.y * 0.5 - 0.3), -tp.x * 0.866 + tp.y * 0.5 - 0.3);
        if (tri < 0.0) color = vec3(0.6, 0.1, 0.9);
    }

    // === SECTION 4 (right): Organic/procedural — noise, waves, particles ===
    if (uv.x > 0.75) {
        vec2 np = (uv - vec2(0.875, 0.5)) * 6.0;

        // Plasma-like pattern
        float plasma = 0.0;
        plasma += sin(np.x * 3.0 + time * 2.0) * 0.5 + 0.5;
        plasma += sin(np.y * 4.0 + time * 1.5) * 0.5 + 0.5;
        plasma += sin((np.x + np.y) * 2.5 + time) * 0.5 + 0.5;
        plasma += sin(length(np) * 5.0 - time * 3.0) * 0.5 + 0.5;
        plasma *= 0.25;

        color = vec3(
            0.5 + 0.5 * sin(plasma * 6.28 + 0.0),
            0.5 + 0.5 * sin(plasma * 6.28 + 2.09),
            0.5 + 0.5 * sin(plasma * 6.28 + 4.19)
        ) * 0.8;

        // Floating bright dots (simulate particles)
        for (int i = 0; i < 12; i++) {
            float seed = float(i) * 3.17;
            vec2 dotPos = vec2(
                sin(time * 0.8 + seed) * 1.5,
                cos(time * 0.6 + seed * 1.3) * 2.0
            );
            float d = length(np - dotPos);
            float glow = 0.02 / (d * d + 0.01);
            glow *= 0.5 + 0.5 * sin(time * 3.0 + seed);
            vec3 dotColor = vec3(
                0.5 + 0.5 * sin(seed),
                0.5 + 0.5 * sin(seed * 1.7),
                0.5 + 0.5 * sin(seed * 2.3)
            );
            color += dotColor * glow * 0.3;
        }
    }

    // === TOP BANNER: "GRAPHON" text-like pattern ===
    if (uv.y < 0.08) {
        // Bright banner
        float pulse = 0.8 + 0.2 * sin(time * 2.0);
        color = vec3(0.9, 0.85, 0.7) * pulse;
        // Vertical stripes to simulate text
        float stripe = step(0.4, fract(uv.x * 40.0 + sin(uv.x * 20.0) * 0.3));
        color *= 0.3 + 0.7 * stripe;
    }

    // === BOTTOM: Checkerboard with smooth falloff — shows quarter block edge detection ===
    if (uv.y > 0.92) {
        float checker = mod(floor(uv.x * 30.0) + floor(uv.y * 30.0), 2.0);
        float fade = (uv.y - 0.92) / 0.08;
        color = mix(color, vec3(checker * 0.6 + 0.2), fade);
    }

    // === CENTER GLOW: orbiting point light ===
    vec2 lightPos = vec2(0.5 + cos(time * 0.5) * 0.3, 0.5 + sin(time * 0.5) * 0.2);
    float lightDist = length(uv - lightPos);
    color += vec3(1.0, 0.8, 0.5) * 0.03 / (lightDist * lightDist + 0.02);

    // === Section divider lines ===
    for (int i = 1; i < 4; i++) {
        float lineX = float(i) * 0.25;
        if (abs(uv.x - lineX) < 0.002) {
            color = vec3(0.3, 0.3, 0.4);
        }
    }

    finalColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
