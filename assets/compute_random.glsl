#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float time;
uniform vec2 gridSize;

// Hash function for pseudo-random per cell
float hash(vec2 p) {
    p = fract(p * vec2(443.8975, 397.2973));
    p += dot(p.xy, p.yx + 19.19);
    return fract(p.x * p.y);
}

vec3 hashColor(vec2 p, float seed) {
    return vec3(
        hash(p + seed * 1.0),
        hash(p + seed * 2.7),
        hash(p + seed * 5.3)
    );
}

void main() {
    vec2 tc = vec2(fragTexCoord.x, 1.0 - fragTexCoord.y);
    vec2 cellCoord = floor(tc * gridSize);

    // Generate random color per cell, changes with time on SPACE press
    vec3 fg = hashColor(cellCoord, floor(time));

    finalColor = vec4(fg, 1.0);
}
