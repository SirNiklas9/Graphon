#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float time;
uniform vec2 gridSize;
uniform int blendMode; // 0=normal, 1=alpha, 2=additive, 3=multiply

void main() {
    vec2 tc = vec2(fragTexCoord.x, 1.0 - fragTexCoord.y);
    vec2 cellCoord = floor(tc * gridSize);
    vec2 uv = cellCoord / gridSize;

    // 7 palette colors cycling per row
    vec3 colors[7] = vec3[](
        vec3(1.0, 0.0, 0.0),
        vec3(0.0, 1.0, 0.0),
        vec3(0.0, 0.0, 1.0),
        vec3(0.0, 1.0, 1.0),
        vec3(1.0, 0.0, 1.0),
        vec3(1.0, 1.0, 0.0),
        vec3(1.0, 0.65, 0.0)
    );

    int row = int(cellCoord.y);
    vec3 fg = colors[row % 7];
    vec3 bg = vec3(0.125);
    float opacity = uv.x; // horizontal gradient

    vec3 result;
    if (blendMode == 0) {
        result = fg;
    } else if (blendMode == 1) {
        result = mix(bg, fg, opacity);
    } else if (blendMode == 2) {
        result = bg + fg * opacity;
    } else {
        result = bg * fg;
    }

    finalColor = vec4(clamp(result, 0.0, 1.0), 1.0);
}
