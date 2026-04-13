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

        vec2 cellCenter = (cellCoord + 0.5) / gridSize;

        // Per-object Grafel resolution — distance-compensated block merging
        // Alpha encodes screen-space block size (already adjusted for depth by lighting shader)
        float objAlpha = texture(texture0, cellCenter).a;
        if (objAlpha > 0.05 && objAlpha < 0.95) {
            // Direct: lower alpha = bigger blocks. 0.1 → 50 cells, 0.5 → 10 cells, 0.9 → 1 cell
            float bs = max(1.0, floor(5.0 / objAlpha));

            // Snap cell to coarser grid — bigger Grafels
            vec2 coarseCell = floor(cellCoord / bs) * bs + bs * 0.5;
            vec2 coarseUV = coarseCell / gridSize;
            vec3 color = texture(texture0, coarseUV).rgb;

            finalColor = vec4(color, 1.0);
            return;
        }

        // FULL_ONLY: solid color blocks
        if (fidelityLevel == 0) {
            finalColor = vec4(texture(texture0, cellCenter).rgb, 1.0);
            return;
        }

        // Cell UV boundaries
        vec2 cellStart = cellCoord / gridSize;
        vec2 cellEnd = (cellCoord + 1.0) / gridSize;
        vec2 qOff = (cellEnd - cellStart) * 0.25;

        // Sample 4 quadrants
        vec3 qTL = texture(texture0, cellStart + qOff).rgb;
        vec3 qTR = texture(texture0, vec2(cellEnd.x - qOff.x, cellStart.y + qOff.y)).rgb;
        vec3 qBL = texture(texture0, vec2(cellStart.x + qOff.x, cellEnd.y - qOff.y)).rgb;
        vec3 qBR = texture(texture0, cellEnd - qOff).rgb;

        // Cell average
        fg = (qTL + qTR + qBL + qBR) * 0.25;
        float brightness = dot(fg, vec3(0.299, 0.587, 0.114));

        // Smooth vs detail — adapt threshold to cell size
        // Small cells (< 6px) need higher threshold to avoid dithering artifacts
        float variance = (length(qTL - fg) + length(qTR - fg) +
                          length(qBL - fg) + length(qBR - fg)) * 0.25;

        float minCell = min(cellSize.x, cellSize.y);
        float adaptiveThreshold = cfgEdgeThreshold;
        if (minCell < 4.0) adaptiveThreshold = 1.0;       // tiny cells: always solid
        else if (minCell < 8.0) adaptiveThreshold = 0.5;   // small cells: mostly solid
        else if (minCell < 12.0) adaptiveThreshold = 0.35;  // medium: slightly more solid

        if (variance < adaptiveThreshold) {
            finalColor = vec4(fg, 1.0);
            return;
        }

        // Detail area — density patterns (only reached at larger cell sizes)
        bg = fg * cfgDensityBgFactor;
        vec2 sp = floor(pixelPos);
        float exactCov = clamp(brightness, 0.0, 1.0);
        float pattern;
        if (exactCov >= cfgDensityThresholds.x) {
            pattern = 1.0;
        } else if (exactCov >= cfgDensityThresholds.y) {
            vec2 p = mod(sp, 2.0);
            pattern = (p.x < 1.0 && p.y < 1.0) ? 0.0 : 1.0;
        } else if (exactCov >= cfgDensityThresholds.z) {
            pattern = mod(sp.x + sp.y, 2.0) < 1.0 ? 1.0 : 0.0;
        } else if (exactCov >= cfgDensityThresholds.w) {
            vec2 p = mod(sp, 2.0);
            pattern = (p.x >= 1.0 && p.y >= 1.0) ? 1.0 : 0.0;
        } else {
            pattern = 0.0;
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
