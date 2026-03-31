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

// Configurable Graphon 3D parameters
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

// 4x4 Bayer ordered dithering — smooth transitions between character levels
float bayer4x4(vec2 coord) {
    ivec2 p = ivec2(mod(coord, 4.0));
    int idx = p.x + p.y * 4;
    if (idx == 0)  return  0.0/16.0;
    if (idx == 1)  return  8.0/16.0;
    if (idx == 2)  return  2.0/16.0;
    if (idx == 3)  return 10.0/16.0;
    if (idx == 4)  return 12.0/16.0;
    if (idx == 5)  return  4.0/16.0;
    if (idx == 6)  return 14.0/16.0;
    if (idx == 7)  return  6.0/16.0;
    if (idx == 8)  return  3.0/16.0;
    if (idx == 9)  return 11.0/16.0;
    if (idx == 10) return  1.0/16.0;
    if (idx == 11) return  9.0/16.0;
    if (idx == 12) return 15.0/16.0;
    if (idx == 13) return  7.0/16.0;
    if (idx == 14) return 13.0/16.0;
    return 5.0/16.0;
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
        // 3D scene mode: real lighting colors + procedural Graphon characters
        // Scene texture has correct per-pixel lighting — colors are always real
        // Characters provide sub-cell detail and the Graphon visual identity

        // FULL_ONLY: raw pixel pass-through, no Graphon processing
        if (fidelityLevel == 0) {
            finalColor = vec4(texture(texture0, fragTexCoord).rgb, 1.0);
            return;
        }

        // Cell UV boundaries
        vec2 cellStart = cellCoord / gridSize;
        vec2 cellEnd = (cellCoord + 1.0) / gridSize;
        vec2 qOff = (cellEnd - cellStart) * 0.25;

        // Sample 4 quadrants — real scene colors
        vec3 qTL = texture(texture0, cellStart + qOff).rgb;
        vec3 qTR = texture(texture0, vec2(cellEnd.x - qOff.x, cellStart.y + qOff.y)).rgb;
        vec3 qBL = texture(texture0, vec2(cellStart.x + qOff.x, cellEnd.y - qOff.y)).rgb;
        vec3 qBR = texture(texture0, cellEnd - qOff).rgb;

        // Cell average — the real lit color of this cell
        fg = (qTL + qTR + qBL + qBR) * 0.25;
        float brightness = dot(fg, vec3(0.299, 0.587, 0.114));

        // Background: same real color, slightly darkened — gives density chars visibility
        bg = fg * cfgDensityBgFactor;

        // Quadrant brightnesses for edge detection
        float bTL = dot(qTL, vec3(0.299, 0.587, 0.114));
        float bTR = dot(qTR, vec3(0.299, 0.587, 0.114));
        float bBL = dot(qBL, vec3(0.299, 0.587, 0.114));
        float bBR = dot(qBR, vec3(0.299, 0.587, 0.114));

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
        float maxEdge = max(vEdge, hEdge);
        float et = cfgEdgeThreshold;
        vec2 sp = floor(pixelPos);

        // ─── Quarter blocks (fidelity >= ALL, diagonal/complex edges) ───
        if (fidelityLevel >= 4 && maxEdge > et) {
            float qSpread = max(max(bTL, bTR), max(bBL, bBR))
                           - min(min(bTL, bTR), min(bBL, bBR));
            if (qSpread > et) {
                float avg = brightness;
                bool onTL = bTL > avg;
                bool onTR = bTR > avg;
                bool onBL = bBL > avg;
                bool onBR = bBR > avg;
                int cnt = (onTL?1:0) + (onTR?1:0) + (onBL?1:0) + (onBR?1:0);

                // Only use quarters for non-axis-aligned patterns (diagonals, corners)
                bool isAxisAligned = (onTL == onTR && onBL == onBR) ||
                                     (onTL == onBL && onTR == onBR);

                if (cnt >= 1 && cnt <= 3 && !isAxisAligned) {
                    // FG = bright quadrants' real color, BG = dark quadrants' real color
                    vec3 brightC = vec3(0.0), darkC = vec3(0.0);
                    float bCnt = 0.0, dCnt = 0.0;
                    if (onTL) { brightC += qTL; bCnt += 1.0; } else { darkC += qTL; dCnt += 1.0; }
                    if (onTR) { brightC += qTR; bCnt += 1.0; } else { darkC += qTR; dCnt += 1.0; }
                    if (onBL) { brightC += qBL; bCnt += 1.0; } else { darkC += qBL; dCnt += 1.0; }
                    if (onBR) { brightC += qBR; bCnt += 1.0; } else { darkC += qBR; dCnt += 1.0; }
                    if (bCnt > 0.0) brightC /= bCnt;
                    if (dCnt > 0.0) darkC /= dCnt;

                    bool inTL = localPos.x < 0.5 && localPos.y < 0.5;
                    bool inTR = localPos.x >= 0.5 && localPos.y < 0.5;
                    bool inBL = localPos.x < 0.5 && localPos.y >= 0.5;
                    bool inBR = localPos.x >= 0.5 && localPos.y >= 0.5;
                    bool pixelOn = (inTL && onTL) || (inTR && onTR) || (inBL && onBL) || (inBR && onBR);
                    finalColor = vec4(pixelOn ? brightC : darkC, 1.0);
                    return;
                }
            }
        }

        // ─── Fractional bars (fidelity >= FRACTIONAL, precise edge position) ───
        if (fidelityLevel >= 3 && maxEdge > et) {
            if (vEdge >= hEdge) {
                // Sample 8 points along vertical to find edge position
                float cellMidX = (cellStart.x + cellEnd.x) * 0.5;
                int topLikeCount = 0;
                for (int i = 0; i < 8; i++) {
                    float t = (float(i) + 0.5) / 8.0;
                    float yUV = mix(cellStart.y, cellEnd.y, t);
                    float b = dot(texture(texture0, vec2(cellMidX, yUV)).rgb, vec3(0.299, 0.587, 0.114));
                    if (abs(b - bTop) < abs(b - bBot)) topLikeCount++;
                }
                float splitY = clamp(float(topLikeCount) / 8.0, 0.125, 0.875);
                finalColor = vec4(localPos.y < splitY ? cTop : cBot, 1.0);
                return;
            } else {
                float cellMidY = (cellStart.y + cellEnd.y) * 0.5;
                int leftLikeCount = 0;
                for (int i = 0; i < 8; i++) {
                    float t = (float(i) + 0.5) / 8.0;
                    float xUV = mix(cellStart.x, cellEnd.x, t);
                    float b = dot(texture(texture0, vec2(xUV, cellMidY)).rgb, vec3(0.299, 0.587, 0.114));
                    if (abs(b - bLeft) < abs(b - bRight)) leftLikeCount++;
                }
                float splitX = clamp(float(leftLikeCount) / 8.0, 0.125, 0.875);
                finalColor = vec4(localPos.x < splitX ? cLeft : cRight, 1.0);
                return;
            }
        }

        // ─── Half blocks (fidelity >= HALF, strong axis-aligned edges) ───
        if (fidelityLevel >= 2 && maxEdge > et) {
            if (vEdge > hEdge) {
                vec3 brightSide = bTop > bBot ? cTop : cBot;
                vec3 darkSide = bTop > bBot ? cBot : cTop;
                bool topBright = bTop > bBot;
                float inTop = localPos.y < 0.5 ? 1.0 : 0.0;
                float pattern = topBright ? inTop : (1.0 - inTop);
                finalColor = vec4(mix(darkSide, brightSide, pattern), 1.0);
                return;
            } else {
                vec3 brightSide = bLeft > bRight ? cLeft : cRight;
                vec3 darkSide = bLeft > bRight ? cRight : cLeft;
                bool leftBright = bLeft > bRight;
                float inLeft = localPos.x < 0.5 ? 1.0 : 0.0;
                float pattern = leftBright ? inLeft : (1.0 - inLeft);
                finalColor = vec4(mix(darkSide, brightSide, pattern), 1.0);
                return;
            }
        }

        // ─── Smooth gradient rendering — all 32 characters, real colors ───
        // Uses directional bars aligned to the lighting gradient for 8 fill levels
        // Bayer dithering between adjacent levels gives ~128 effective brightness steps
        // fg = real cell color, bg = slightly darkened — character provides texture

        float vGrad = bTop - bBot;   // positive = top brighter
        float hGrad = bLeft - bRight; // positive = left brighter
        float absV = abs(vGrad);
        float absH = abs(hGrad);

        // Bayer dither value for this cell (smooth transitions between levels)
        float dither = bayer4x4(cellCoord);

        // Coverage from brightness — 8 levels (1/8 steps) with dithered transitions
        float exactCov = clamp(brightness, 0.0, 1.0);
        float baseCov = floor(exactCov * 8.0) / 8.0;
        float nextCov = min(baseCov + 0.125, 1.0);
        float fracCov = (exactCov - baseCov) * 8.0;
        float fill = fracCov > dither ? nextCov : baseCov;
        fill = clamp(fill, 0.0, 1.0);

        float pattern;
        bool hasGradient = max(absV, absH) > et * 0.75;

        if (fidelityLevel >= 3 && hasGradient) {
            // Diagonal gradient — quarter blocks
            bool isDiagonal = absV > 0.01 && absH > 0.01 && absV / absH < 2.5 && absH / absV < 2.5;

            if (fidelityLevel >= 4 && isDiagonal) {
                // Quarter blocks for diagonal gradients
                bool onTL = bTL > brightness;
                bool onTR = bTR > brightness;
                bool onBL = bBL > brightness;
                bool onBR = bBR > brightness;

                bool inTL = localPos.x < 0.5 && localPos.y < 0.5;
                bool inTR = localPos.x >= 0.5 && localPos.y < 0.5;
                bool inBL = localPos.x < 0.5 && localPos.y >= 0.5;
                bool inBR = localPos.x >= 0.5 && localPos.y >= 0.5;

                bool pixelOn = (inTL && onTL) || (inTR && onTR) || (inBL && onBL) || (inBR && onBR);
                pattern = pixelOn ? 1.0 : 0.0;
            } else if (absV >= absH) {
                // Vertical gradient — fill from bright side
                if (vGrad > 0.0) {
                    pattern = localPos.y < fill ? 1.0 : 0.0;
                } else {
                    pattern = localPos.y >= (1.0 - fill) ? 1.0 : 0.0;
                }
            } else {
                // Horizontal gradient — fill from bright side
                if (hGrad > 0.0) {
                    pattern = localPos.x < fill ? 1.0 : 0.0;
                } else {
                    pattern = localPos.x >= (1.0 - fill) ? 1.0 : 0.0;
                }
            }
        } else if (fidelityLevel >= 2 && hasGradient) {
            // Half blocks only — vertical or horizontal fill
            if (absV >= absH) {
                if (vGrad > 0.0) {
                    pattern = localPos.y < fill ? 1.0 : 0.0;
                } else {
                    pattern = localPos.y >= (1.0 - fill) ? 1.0 : 0.0;
                }
            } else {
                if (hGrad > 0.0) {
                    pattern = localPos.x < fill ? 1.0 : 0.0;
                } else {
                    pattern = localPos.x >= (1.0 - fill) ? 1.0 : 0.0;
                }
            }
        } else {
            // Density only (fidelity 1) or no gradient — 4 density patterns with dithered transitions
            float densityF = clamp((1.0 - exactCov) * 4.0, 0.0, 3.99);
            int baseD = int(floor(densityF));
            float fracD = fract(densityF);
            int dLevel = fracD > dither ? min(baseD + 1, 3) : baseD;

            if (dLevel == 0) {
                pattern = 1.0; // █
            } else if (dLevel == 1) {
                vec2 p = mod(sp, 2.0); // ▓
                pattern = (p.x < 1.0 && p.y < 1.0) ? 0.0 : 1.0;
            } else if (dLevel == 2) {
                pattern = mod(sp.x + sp.y, 2.0) < 1.0 ? 1.0 : 0.0; // ▒
            } else {
                vec2 p = mod(sp, 2.0); // ░
                pattern = (p.x >= 1.0 && p.y >= 1.0) ? 1.0 : 0.0;
            }
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
