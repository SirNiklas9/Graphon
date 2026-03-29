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

// Character index map:
// 0-3:   Density  — █ ▓ ▒ ░
// 4-7:   Half     — ▀ ▄ ▌ ▐
// 8-13:  Bottom bars — ▁ ▂ ▃ ▅ ▆ ▇ (1/8 to 7/8 height from bottom)
// 14-19: Left bars  — ▉ ▊ ▋ ▍ ▎ ▏ (7/8 to 1/8 width from left)
// 20-21: Thin edges — ▔ ▕ (top bar, right bar)
// 22-31: Quarters   — ▖ ▗ ▘ ▝ ▙ ▚ ▛ ▜ ▞ ▟

// Sample neighboring cell brightness for edge detection
float sampleBrightness(vec2 cellCoord, vec2 offset) {
    vec2 nc = cellCoord + offset;
    if (nc.x < 0.0 || nc.x >= gridSize.x || nc.y < 0.0 || nc.y >= gridSize.y)
        return 0.0;
    vec2 uv = (nc + 0.5) / gridSize;
    vec4 s = texture(texture0, uv);
    return dot(s.rgb, vec3(0.299, 0.587, 0.114));
}

int charFromBrightness(float brightness, vec2 localPos, vec2 cellCoord) {
    if (fidelityLevel == 0) return 0; // FULL_ONLY — solid rectangles

    // DENSITY only (level 1): 4 density characters
    if (fidelityLevel == 1) {
        if (brightness > 0.875) return 0;  // █
        if (brightness > 0.625) return 1;  // ▓
        if (brightness > 0.375) return 2;  // ▒
        if (brightness > 0.125) return 3;  // ░
        return 0;
    }

    // HALF (level 2): density + half blocks using edge detection
    if (fidelityLevel == 2) {
        float above = sampleBrightness(cellCoord, vec2(0.0, -1.0));
        float below = sampleBrightness(cellCoord, vec2(0.0, 1.0));
        float left  = sampleBrightness(cellCoord, vec2(-1.0, 0.0));
        float right = sampleBrightness(cellCoord, vec2(1.0, 0.0));

        float vEdge = abs(above - below);
        float hEdge = abs(left - right);

        if (brightness > 0.9) return 0;
        if (vEdge > 0.2 && brightness > 0.4) {
            return (above > below) ? 4 : 5; // ▀ or ▄
        }
        if (hEdge > 0.2 && brightness > 0.4) {
            return (left > right) ? 6 : 7;  // ▌ or ▐
        }
        if (brightness > 0.625) return 1;
        if (brightness > 0.375) return 2;
        if (brightness > 0.125) return 3;
        return 0;
    }

    // FRACTIONAL (level 3): density + half + fractional bars
    if (fidelityLevel == 3) {
        float above = sampleBrightness(cellCoord, vec2(0.0, -1.0));
        float below = sampleBrightness(cellCoord, vec2(0.0, 1.0));
        float left  = sampleBrightness(cellCoord, vec2(-1.0, 0.0));
        float right = sampleBrightness(cellCoord, vec2(1.0, 0.0));

        if (brightness > 0.95) return 0; // █

        // Vertical edge — use bottom bars (▁▂▃▅▆▇) based on fill amount
        if (abs(above - below) > 0.15) {
            float fill = (above > below) ? brightness : (1.0 - brightness);
            fill = clamp(fill, 0.0, 1.0);
            if (fill > 0.85) return 0;     // █
            if (fill > 0.72) return 13;    // ▇
            if (fill > 0.60) return 12;    // ▆
            if (fill > 0.47) return 11;    // ▅
            if (fill > 0.35) return 10;    // ▃
            if (fill > 0.22) return 9;     // ▂
            if (fill > 0.1)  return 8;     // ▁
            return 0;
        }

        // Horizontal edge — use left bars (▉▊▋▍▎▏)
        if (abs(left - right) > 0.15) {
            float fill = (left > right) ? brightness : (1.0 - brightness);
            fill = clamp(fill, 0.0, 1.0);
            if (fill > 0.85) return 0;     // █
            if (fill > 0.72) return 14;    // ▉
            if (fill > 0.60) return 15;    // ▊
            if (fill > 0.47) return 16;    // ▋
            if (fill > 0.35) return 17;    // ▍
            if (fill > 0.22) return 18;    // ▎
            if (fill > 0.1)  return 19;    // ▏
            return 0;
        }

        // No strong edge — use density
        if (brightness > 0.75) return 1;
        if (brightness > 0.5)  return 2;
        if (brightness > 0.25) return 3;
        return 0;
    }

    // ALL (level 4): full 32-character set with quarter blocks
    {
        float above = sampleBrightness(cellCoord, vec2(0.0, -1.0));
        float below = sampleBrightness(cellCoord, vec2(0.0, 1.0));
        float left  = sampleBrightness(cellCoord, vec2(-1.0, 0.0));
        float right = sampleBrightness(cellCoord, vec2(1.0, 0.0));
        float tl = sampleBrightness(cellCoord, vec2(-1.0, -1.0));
        float tr = sampleBrightness(cellCoord, vec2(1.0, -1.0));
        float bl = sampleBrightness(cellCoord, vec2(-1.0, 1.0));
        float br = sampleBrightness(cellCoord, vec2(1.0, 1.0));

        if (brightness > 0.95) return 0; // █

        // Quarter block detection — compare quadrant brightnesses
        float quadTL = (tl + above + left + brightness) * 0.25;
        float quadTR = (tr + above + right + brightness) * 0.25;
        float quadBL = (bl + below + left + brightness) * 0.25;
        float quadBR = (br + below + right + brightness) * 0.25;

        float avg = (quadTL + quadTR + quadBL + quadBR) * 0.25;
        bool qTL = quadTL > avg;
        bool qTR = quadTR > avg;
        bool qBL = quadBL > avg;
        bool qBR = quadBR > avg;

        int qCount = (qTL ? 1 : 0) + (qTR ? 1 : 0) + (qBL ? 1 : 0) + (qBR ? 1 : 0);

        // Strong quadrant pattern — use quarter blocks
        if (qCount >= 1 && qCount <= 3 && brightness > 0.15 && brightness < 0.85) {
            // ▖▗▘▝ — single quadrant
            if (qCount == 1) {
                if (qBL) return 22; // ▖
                if (qBR) return 23; // ▗
                if (qTL) return 24; // ▘
                if (qTR) return 25; // ▝
            }
            // ▙▚▛▜▞▟ — two/three quadrants
            if (qCount == 2) {
                if (qBL && qTL) return 6;  // ▌
                if (qBR && qTR) return 7;  // ▐
                if (qTL && qTR) return 4;  // ▀
                if (qBL && qBR) return 5;  // ▄
                if (qTL && qBR) return 27; // ▚ diagonal
                if (qTR && qBL) return 30; // ▞ diagonal
            }
            if (qCount == 3) {
                if (!qTR) return 28; // ▛
                if (!qTL) return 29; // ▜
                if (!qBR) return 26; // ▙
                if (!qBL) return 31; // ▟
            }
        }

        // Fallback to fractional bars for edges
        float vEdge = abs(above - below);
        float hEdge = abs(left - right);

        if (vEdge > 0.1) {
            float fill = brightness;
            if (fill > 0.85) return 0;
            if (fill > 0.72) return 13;
            if (fill > 0.60) return 12;
            if (fill > 0.47) return 11;
            if (fill > 0.35) return 10;
            if (fill > 0.22) return 9;
            if (fill > 0.1)  return 8;
        }

        if (hEdge > 0.1) {
            float fill = brightness;
            if (fill > 0.85) return 0;
            if (fill > 0.72) return 14;
            if (fill > 0.60) return 15;
            if (fill > 0.47) return 16;
            if (fill > 0.35) return 17;
            if (fill > 0.22) return 18;
            if (fill > 0.1)  return 19;
        }

        // No edges — density
        if (brightness > 0.75) return 1;
        if (brightness > 0.5)  return 2;
        if (brightness > 0.25) return 3;
        return 0;
    }
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
        idx = charFromBrightness(brightness, localPos, cellCoord);
        // bg is a darker shade of fg — preserves color while showing character detail
        bg = fg * 0.3;
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

    // Final color
    if (computeMode == 1) {
        // Compute mode: modulate brightness by coverage — keeps color, adds subtle character texture
        float intensity = 0.75 + 0.25 * coverage;
        finalColor = vec4(fg * intensity, 1.0);
    } else {
        // Hybrid mode: mix bg and fg based on glyph shape
        finalColor = vec4(mix(bg, fg, coverage), 1.0);
    }
}
