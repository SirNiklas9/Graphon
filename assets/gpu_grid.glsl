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
uniform int computeMode;   // 0=hybrid (read char from texture), 1=compute (derive char from brightness)

// Derive character index from brightness — maps coverage to block characters
// Density: 0=█(1.0), 1=▓(0.75), 2=▒(0.5), 3=░(0.25)
// Half: 4=▀, 5=▄, 6=▌, 7=▐
// Quarter: 22-31
int charFromBrightness(float brightness, vec2 localPos) {
    if (fidelityLevel == 0) return 0; // FULL_ONLY

    // At ALL fidelity, use position-aware characters
    if (fidelityLevel >= 4) {
        // Quarter blocks based on position within cell
        bool top = localPos.y < 0.5;
        bool left = localPos.x < 0.5;

        if (brightness > 0.9) return 0;  // full block
        if (brightness > 0.7) return 1;  // ▓
        if (brightness > 0.5) {
            // Use half blocks based on dominant position
            if (top) return 4;   // ▀
            else return 5;       // ▄
        }
        if (brightness > 0.3) return 2;  // ▒
        if (brightness > 0.1) return 3;  // ░
        return 0;
    }

    // FRACTIONAL/HALF: density + half blocks
    if (fidelityLevel >= 2) {
        if (brightness > 0.875) return 0;
        if (brightness > 0.625) return 1;
        if (brightness > 0.375) return 2;
        if (brightness > 0.125) return 3;
        return 0;
    }

    // DENSITY only
    if (brightness > 0.875) return 0;
    if (brightness > 0.625) return 1;
    if (brightness > 0.375) return 2;
    if (brightness > 0.125) return 3;
    return 0;
}

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

    // Position within cell
    vec2 localPos = fract(pixelPos / cellSize);

    // Get character index
    int idx;
    if (computeMode == 1) {
        // Compute mode: derive character from fg brightness
        float brightness = dot(fg, vec3(0.299, 0.587, 0.114));
        idx = charFromBrightness(brightness, localPos);
        // In compute mode, bg is dark
        bg = vec3(0.08, 0.08, 0.1);
    } else {
        // Hybrid mode: read char index from texture alpha
        idx = clamp(int(fgData.a * 255.0 + 0.5), 0, 31);
    }

    // FULL_ONLY fidelity = solid fg
    if (fidelityLevel == 0) {
        finalColor = vec4(fg, 1.0);
        return;
    }

    // Full block (idx 0) = solid fg
    if (idx == 0) {
        finalColor = vec4(fg, 1.0);
        return;
    }

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
