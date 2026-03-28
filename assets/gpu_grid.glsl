#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;    // cellFG (unit 0, bound via DrawTexturePro)
uniform sampler2D cellBG;      // bg colors (unit 1)
uniform sampler2D cellChar;    // char indices (unit 2)
uniform sampler2D fontAtlas;   // font glyph texture (unit 3)

uniform vec2 resolution;
uniform vec2 gridSize;
uniform vec2 cellSize;
uniform vec4 glyphRects[32];
uniform vec2 atlasSize;

void main() {
    // fragTexCoord is 0-1 across the drawn quad (fullscreen)
    vec2 pixelPos = fragTexCoord * resolution;

    // Which cell?
    vec2 cellCoord = floor(pixelPos / cellSize);

    if (cellCoord.x < 0.0 || cellCoord.x >= gridSize.x ||
        cellCoord.y < 0.0 || cellCoord.y >= gridSize.y) {
        finalColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // Sample cell data at texel center
    vec2 cellUV = (cellCoord + 0.5) / gridSize;

    vec4 fg = texture(texture0, cellUV);
    vec4 bg = texture(cellBG, cellUV);

    // Character index from grayscale texture
    float charVal = texture(cellChar, cellUV).r;
    int idx = clamp(int(charVal * 255.0 + 0.5), 0, 31);

    // Position within cell (0-1)
    vec2 localPos = fract(pixelPos / cellSize);

    // Look up glyph in font atlas
    vec4 rect = glyphRects[idx];

    // Full block (idx 0) or zero-size glyph = solid fg
    if (idx == 0 || rect.z < 1.0 || rect.w < 1.0) {
        finalColor = fg;
        return;
    }

    // Sample font atlas glyph
    vec2 glyphUV = (rect.xy + localPos * rect.zw) / atlasSize;
    float coverage = texture(fontAtlas, glyphUV).a;

    finalColor = mix(bg, fg, coverage);
    finalColor.a = 1.0;
}
