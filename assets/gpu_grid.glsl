#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

// Texture 0: RGBA = fg.r, fg.g, fg.b, char_index (packed)
uniform sampler2D texture0;
// Texture 1: RGBA = bg.r, bg.g, bg.b, 1.0
uniform sampler2D cellBG;
// Texture 2: font atlas (GRAY_ALPHA)
uniform sampler2D fontAtlas;

uniform vec2 resolution;
uniform vec2 gridSize;
uniform vec2 cellSize;
uniform vec4 glyphRects[32];
uniform vec2 atlasSize;
uniform int fidelityLevel; // 0=FULL_ONLY, 1=DENSITY, 2=HALF, 3=FRACTIONAL, 4=ALL

void main() {
    vec2 pixelPos = fragTexCoord * resolution;

    // Which cell?
    vec2 cellCoord = floor(pixelPos / cellSize);

    if (cellCoord.x < 0.0 || cellCoord.x >= gridSize.x ||
        cellCoord.y < 0.0 || cellCoord.y >= gridSize.y) {
        finalColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // Sample cell data
    vec2 cellUV = (cellCoord + 0.5) / gridSize;
    vec4 fgData = texture(texture0, cellUV);
    vec4 bgData = texture(cellBG, cellUV);

    vec3 fg = fgData.rgb;
    vec3 bg = bgData.rgb;

    // Char index packed in alpha
    int idx = clamp(int(fgData.a * 255.0 + 0.5), 0, 31);

    // FULL_ONLY or full block (idx 0) = solid fg color
    if (fidelityLevel == 0 || idx == 0) {
        finalColor = vec4(fg, 1.0);
        return;
    }

    // Position within cell
    vec2 localPos = fract(pixelPos / cellSize);

    // Glyph rectangle in font atlas
    vec4 rect = glyphRects[idx];
    if (rect.z < 1.0 || rect.w < 1.0) {
        finalColor = vec4(fg, 1.0);
        return;
    }

    // Sample glyph coverage from font atlas
    vec2 glyphUV = (rect.xy + localPos * rect.zw) / atlasSize;
    float coverage = texture(fontAtlas, glyphUV).a;

    // Mix bg and fg based on glyph shape
    finalColor = vec4(mix(bg, fg, coverage), 1.0);
}
