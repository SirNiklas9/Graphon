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

void main() {
    vec2 tc = vec2(fragTexCoord.x, 1.0 - fragTexCoord.y);
    vec2 cellCoord = floor(tc * gridSize);
    vec2 uv = cellCoord / gridSize;

    vec3 color = vec3(0.08, 0.08, 0.1);

    // Simulate ~200 particles on GPU
    for (int i = 0; i < 200; i++) {
        float seed = float(i);
        float birthTime = hash(vec2(seed, 0.0)) * 2.0;
        float lifespan = 1.5 + hash(vec2(seed, 1.0)) * 1.5;

        // Particle cycles
        float cycle = floor((time - birthTime) / lifespan);
        float t = mod(time - birthTime, lifespan);
        float lifeFrac = t / lifespan;

        if (lifeFrac < 0.0 || lifeFrac > 1.0) continue;

        // Spawn position (orbiting emitter)
        float emitAngle = time * 0.5 + cycle * 1.7;
        vec2 emitPos = vec2(0.5 + cos(emitAngle) * 0.25, 0.5 + sin(emitAngle * 0.7) * 0.15);

        // Velocity
        float angle = hash(vec2(seed, 2.0 + cycle)) * 6.283;
        float speed = 0.1 + hash(vec2(seed, 3.0 + cycle)) * 0.15;

        vec2 pos = emitPos + vec2(cos(angle), sin(angle)) * speed * t;
        pos.y += 0.05 * t * t; // gravity

        // Distance to this cell
        vec2 cellUV = cellCoord / gridSize;
        float dist = length(cellUV - pos);

        if (dist < 0.015) {
            float fade = (1.0 - lifeFrac);
            fade *= fade; // quadratic

            // Color based on particle index
            vec3 pColor;
            int colorIdx = i % 5;
            if (colorIdx == 0) pColor = vec3(1.0, 0.8, 0.1);
            else if (colorIdx == 1) pColor = vec3(1.0, 0.3, 0.1);
            else if (colorIdx == 2) pColor = vec3(0.1, 0.8, 1.0);
            else if (colorIdx == 3) pColor = vec3(0.1, 1.0, 0.3);
            else pColor = vec3(1.0, 0.1, 0.5);

            float brightness = fade * (1.0 - dist / 0.015);
            color += pColor * brightness;
        }
    }

    finalColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
