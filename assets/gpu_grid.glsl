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

// Configurable Grafel 3D parameters
uniform float cfgEdgeThreshold;      // Min brightness diff for edge characters
uniform vec4 cfgDensityThresholds;   // x=solid, y=75%, z=50%, w=25%
uniform float cfgDensityBgFactor;    // bg = fg * this

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

    // DENSITY only (level 1): 4 density characters — spread evenly
    if (fidelityLevel == 1) {
        if (brightness > 0.75) return 0;   // █
        if (brightness > 0.50) return 1;   // ▓
        if (brightness > 0.25) return 2;   // ▒
        if (brightness > 0.05) return 3;   // ░
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
        if (abs(above - below) > 0.2) {
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
        if (abs(left - right) > 0.2) {
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
        float spread = max(max(quadTL, quadTR), max(quadBL, quadBR)) - min(min(quadTL, quadTR), min(quadBL, quadBR));
        bool qTL = quadTL > avg + 0.05;
        bool qTR = quadTR > avg + 0.05;
        bool qBL = quadBL > avg + 0.05;
        bool qBR = quadBR > avg + 0.05;

        int qCount = (qTL ? 1 : 0) + (qTR ? 1 : 0) + (qBL ? 1 : 0) + (qBR ? 1 : 0);

        // Strong quadrant pattern — only at real edges (high spread)
        if (qCount >= 1 && qCount <= 3 && spread > 0.15 && brightness > 0.1 && brightness < 0.9) {
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

        // Fractional bars only at strong edges (object boundaries, not lighting gradients)
        float vEdge = abs(above - below);
        float hEdge = abs(left - right);

        if (vEdge > 0.2) {
            float fill = brightness;
            if (fill > 0.85) return 0;
            if (fill > 0.72) return 13;
            if (fill > 0.60) return 12;
            if (fill > 0.47) return 11;
            if (fill > 0.35) return 10;
            if (fill > 0.22) return 9;
            if (fill > 0.1)  return 8;
        }

        if (hEdge > 0.2) {
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

    // Position within cell
    vec2 localPos = fract(pixelPos / cellSize);

    // Sample cell data — area average for compute mode, center sample for hybrid
    vec3 fg;
    vec3 bg;
    vec4 fgData;
    vec4 bgData;
    int idx;

    if (computeMode == 1) {
        // 3D scene mode: procedural Grafel rendering with full character set
        vec2 cellStart = cellCoord / gridSize;
        vec2 cellEnd = (cellCoord + 1.0) / gridSize;
        vec2 cellMid = (cellStart + cellEnd) * 0.5;

        // Sample 4 quadrants of the cell for edge detection
        vec2 qSize = (cellEnd - cellStart) * 0.25;
        vec3 qTL = texture(texture0, cellStart + qSize).rgb;
        vec3 qTR = texture(texture0, vec2(cellEnd.x - qSize.x, cellStart.y + qSize.y)).rgb;
        vec3 qBL = texture(texture0, vec2(cellStart.x + qSize.x, cellEnd.y - qSize.y)).rgb;
        vec3 qBR = texture(texture0, cellEnd - qSize).rgb;

        // Average and quadrant brightnesses
        fg = (qTL + qTR + qBL + qBR) * 0.25;
        float bTL = dot(qTL, vec3(0.299, 0.587, 0.114));
        float bTR = dot(qTR, vec3(0.299, 0.587, 0.114));
        float bBL = dot(qBL, vec3(0.299, 0.587, 0.114));
        float bBR = dot(qBR, vec3(0.299, 0.587, 0.114));
        float brightness = (bTL + bTR + bBL + bBR) * 0.25;

        float bTop = (bTL + bTR) * 0.5;
        float bBot = (bBL + bBR) * 0.5;
        float bLeft = (bTL + bBL) * 0.5;
        float bRight = (bTR + bBR) * 0.5;

        vec3 cTop = (qTL + qTR) * 0.5;
        vec3 cBot = (qBL + qBR) * 0.5;
        vec3 cLeft = (qTL + qBL) * 0.5;
        vec3 cRight = (qTR + qBR) * 0.5;

        float vEdge = abs(bTop - bBot);
        float hEdge = abs(bLeft - bRight);

        // Diagonal detection
        float dFwd = abs((bTL + bBR) * 0.5 - (bTR + bBL) * 0.5); // ▚ direction
        float dBck = abs((bTR + bBL) * 0.5 - (bTL + bBR) * 0.5); // ▞ direction

        vec2 sp = floor(pixelPos);
        float edgeThreshold = cfgEdgeThreshold;

        // --- Edge characters (fidelity >= HALF) ---
        if (fidelityLevel >= 2 && max(vEdge, hEdge) > edgeThreshold) {
            if (vEdge > hEdge) {
                // Horizontal edge — ▀ or ▄
                vec3 brightSide = bTop > bBot ? cTop : cBot;
                vec3 darkSide = bTop > bBot ? cBot : cTop;
                bool topBright = bTop > bBot;
                // Procedural: top half or bottom half of cell
                float inTop = localPos.y < 0.5 ? 1.0 : 0.0;
                float pattern = topBright ? inTop : (1.0 - inTop);
                finalColor = vec4(mix(darkSide, brightSide, pattern), 1.0);
                return;
            } else {
                // Vertical edge — ▌ or ▐
                vec3 brightSide = bLeft > bRight ? cLeft : cRight;
                vec3 darkSide = bLeft > bRight ? cRight : cLeft;
                bool leftBright = bLeft > bRight;
                float inLeft = localPos.x < 0.5 ? 1.0 : 0.0;
                float pattern = leftBright ? inLeft : (1.0 - inLeft);
                finalColor = vec4(mix(darkSide, brightSide, pattern), 1.0);
                return;
            }
        }

        // --- Quarter blocks (fidelity >= ALL) ---
        if (fidelityLevel >= 4) {
            float qSpread = max(max(bTL, bTR), max(bBL, bBR)) - min(min(bTL, bTR), min(bBL, bBR));
            if (qSpread > edgeThreshold) {
                float avg = brightness;
                bool qTLon = bTL > avg + 0.02;
                bool qTRon = bTR > avg + 0.02;
                bool qBLon = bBL > avg + 0.02;
                bool qBRon = bBR > avg + 0.02;
                int qCount = (qTLon ? 1 : 0) + (qTRon ? 1 : 0) + (qBLon ? 1 : 0) + (qBRon ? 1 : 0);

                if (qCount >= 1 && qCount <= 3) {
                    // Determine bright/dark colors from quadrants
                    vec3 brightC = vec3(0.0);
                    vec3 darkC = vec3(0.0);
                    float bCount = 0.0, dCount = 0.0;
                    if (qTLon) { brightC += qTL; bCount += 1.0; } else { darkC += qTL; dCount += 1.0; }
                    if (qTRon) { brightC += qTR; bCount += 1.0; } else { darkC += qTR; dCount += 1.0; }
                    if (qBLon) { brightC += qBL; bCount += 1.0; } else { darkC += qBL; dCount += 1.0; }
                    if (qBRon) { brightC += qBR; bCount += 1.0; } else { darkC += qBR; dCount += 1.0; }
                    if (bCount > 0.0) brightC /= bCount;
                    if (dCount > 0.0) darkC /= dCount;

                    // Which quadrant is this pixel in?
                    bool inTL = localPos.x < 0.5 && localPos.y < 0.5;
                    bool inTR = localPos.x >= 0.5 && localPos.y < 0.5;
                    bool inBL = localPos.x < 0.5 && localPos.y >= 0.5;
                    bool inBR = localPos.x >= 0.5 && localPos.y >= 0.5;

                    bool pixelOn = (inTL && qTLon) || (inTR && qTRon) || (inBL && qBLon) || (inBR && qBRon);
                    finalColor = vec4(pixelOn ? brightC : darkC, 1.0);
                    return;
                }
            }
        }

        // --- Density characters (fidelity >= DENSITY) ---
        bg = fg * cfgDensityBgFactor;

        int densityLevel;
        if (brightness > cfgDensityThresholds.x) densityLevel = 0;
        else if (brightness > cfgDensityThresholds.y) densityLevel = 1;
        else if (brightness > cfgDensityThresholds.z) densityLevel = 2;
        else if (brightness > cfgDensityThresholds.w) densityLevel = 3;
        else densityLevel = 0;

        if (fidelityLevel == 0) densityLevel = 0;

        float pattern;
        if (densityLevel == 0) {
            pattern = 1.0;
        } else if (densityLevel == 1) {
            vec2 p = mod(sp, 2.0);
            pattern = (p.x < 1.0 && p.y < 1.0) ? 0.0 : 1.0;
        } else if (densityLevel == 2) {
            pattern = mod(sp.x + sp.y, 2.0) < 1.0 ? 1.0 : 0.0;
        } else {
            vec2 p = mod(sp, 2.0);
            pattern = (p.x >= 1.0 && p.y >= 1.0) ? 1.0 : 0.0;
        }

        finalColor = vec4(mix(bg, fg, pattern), 1.0);
        return;
    } else {
        // Hybrid mode: read char index from texture alpha
        vec2 cellUV = (cellCoord + 0.5) / gridSize;
        fgData = texture(texture0, cellUV);
        bgData = texture(cellBG, cellUV);
        fg = fgData.rgb;
        bg = bgData.rgb;
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

    // Procedural character rendering — no font atlas, continuous patterns
    // idx 0-3: density (█▓▒░), 4-7: half (▀▄▌▐), 22-31: quarter blocks
    vec2 sp = floor(pixelPos);
    float pattern = 1.0;

    if (idx == 0) {
        // █ solid
        pattern = 1.0;
    } else if (idx == 1) {
        // ▓ 75%
        vec2 p = mod(sp, 2.0);
        pattern = (p.x < 1.0 && p.y < 1.0) ? 0.0 : 1.0;
    } else if (idx == 2) {
        // ▒ 50% checkerboard
        pattern = mod(sp.x + sp.y, 2.0) < 1.0 ? 1.0 : 0.0;
    } else if (idx == 3) {
        // ░ 25%
        vec2 p = mod(sp, 2.0);
        pattern = (p.x >= 1.0 && p.y >= 1.0) ? 1.0 : 0.0;
    } else if (idx == 4) {
        // ▀ top half
        pattern = localPos.y < 0.5 ? 1.0 : 0.0;
    } else if (idx == 5) {
        // ▄ bottom half
        pattern = localPos.y >= 0.5 ? 1.0 : 0.0;
    } else if (idx == 6) {
        // ▌ left half
        pattern = localPos.x < 0.5 ? 1.0 : 0.0;
    } else if (idx == 7) {
        // ▐ right half
        pattern = localPos.x >= 0.5 ? 1.0 : 0.0;
    } else if (idx >= 8 && idx <= 13) {
        // ▁▂▃▅▆▇ bottom bars (increasing height)
        float heights[6] = float[6](0.125, 0.25, 0.375, 0.625, 0.75, 0.875);
        float h = heights[idx - 8];
        pattern = localPos.y >= (1.0 - h) ? 1.0 : 0.0;
    } else if (idx >= 14 && idx <= 19) {
        // ▉▊▋▍▎▏ left bars (decreasing width)
        float widths[6] = float[6](0.875, 0.75, 0.625, 0.375, 0.25, 0.125);
        float w = widths[idx - 14];
        pattern = localPos.x < w ? 1.0 : 0.0;
    } else if (idx == 20) {
        // ▔ top bar (thin)
        pattern = localPos.y < 0.125 ? 1.0 : 0.0;
    } else if (idx == 21) {
        // ▕ right bar (thin)
        pattern = localPos.x >= 0.875 ? 1.0 : 0.0;
    } else if (idx == 22) {
        // ▖ bottom-left quarter
        pattern = (localPos.x < 0.5 && localPos.y >= 0.5) ? 1.0 : 0.0;
    } else if (idx == 23) {
        // ▗ bottom-right quarter
        pattern = (localPos.x >= 0.5 && localPos.y >= 0.5) ? 1.0 : 0.0;
    } else if (idx == 24) {
        // ▘ top-left quarter
        pattern = (localPos.x < 0.5 && localPos.y < 0.5) ? 1.0 : 0.0;
    } else if (idx == 25) {
        // ▝ top-right quarter
        pattern = (localPos.x >= 0.5 && localPos.y < 0.5) ? 1.0 : 0.0;
    } else if (idx == 26) {
        // ▙ all except top-right
        pattern = !(localPos.x >= 0.5 && localPos.y < 0.5) ? 1.0 : 0.0;
    } else if (idx == 27) {
        // ▚ diagonal (TL + BR)
        bool tl = localPos.x < 0.5 && localPos.y < 0.5;
        bool br = localPos.x >= 0.5 && localPos.y >= 0.5;
        pattern = (tl || br) ? 1.0 : 0.0;
    } else if (idx == 28) {
        // ▛ all except bottom-right
        pattern = !(localPos.x >= 0.5 && localPos.y >= 0.5) ? 1.0 : 0.0;
    } else if (idx == 29) {
        // ▜ all except bottom-left
        pattern = !(localPos.x < 0.5 && localPos.y >= 0.5) ? 1.0 : 0.0;
    } else if (idx == 30) {
        // ▞ diagonal (TR + BL)
        bool tr = localPos.x >= 0.5 && localPos.y < 0.5;
        bool bl = localPos.x < 0.5 && localPos.y >= 0.5;
        pattern = (tr || bl) ? 1.0 : 0.0;
    } else if (idx == 31) {
        // ▟ all except top-left
        pattern = !(localPos.x < 0.5 && localPos.y < 0.5) ? 1.0 : 0.0;
    }

    finalColor = vec4(mix(bg, fg, pattern), 1.0);
}
