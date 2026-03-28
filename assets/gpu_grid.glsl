#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;    // cellFG bound via DrawTexturePro (unit 0)
uniform sampler2D cellBG;      // bg colors (unit 1)
uniform sampler2D cellChar;    // char indices (unit 2)
uniform sampler2D fontAtlas;   // font glyph texture (unit 3)

uniform vec2 resolution;       // screen size in pixels
uniform vec2 gridSize;         // cols, rows
uniform vec2 cellSize;         // cell width, cell height in pixels
uniform vec4 glyphRects[32];   // x, y, w, h in atlas for each char
uniform vec2 atlasSize;        // font atlas texture size

void main() {
    // Screen pixel position
    vec2 pixelPos = fragTexCoord * resolution;

    // Which cell are we in?
    vec2 cellCoord = floor(pixelPos / cellSize);

    // Out of grid bounds
    if (cellCoord.x < 0.0 || cellCoord.x >= gridSize.x ||
        cellCoord.y < 0.0 || cellCoord.y >= gridSize.y) {
        finalColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // UV to sample cell data textures (center of texel)
    vec2 cellUV = (cellCoord + 0.5) / gridSize;

    // Sample cell colors
    vec4 fg = texture(texture0, cellUV);
    vec4 bg = texture(cellBG, cellUV);

    // Sample character index (stored in red channel, 0-255 mapped to 0.0-1.0)
    float charVal = texture(cellChar, cellUV).r;
    int idx = clamp(int(charVal * 255.0 + 0.5), 0, 31);

    // Position within the cell (0 to 1)
    vec2 localPos = fract(pixelPos / cellSize);

    // Look up glyph rectangle in font atlas
    vec4 rect = glyphRects[idx];

    // If glyph has zero size, just show fg color (full block)
    if (rect.z < 1.0 || rect.w < 1.0) {
        finalColor = fg;
        return;
    }

    // Sample font atlas — the atlas is GRAY_ALPHA format
    vec2 glyphUV = (rect.xy + localPos * rect.zw) / atlasSize;
    vec4 glyphSample = texture(fontAtlas, glyphUV);

    // Coverage from the glyph (alpha channel has the shape)
    float coverage = glyphSample.a;

    // Mix bg and fg based on glyph coverage
    finalColor = mix(bg, fg, coverage);
    finalColor.a = 1.0;
}
