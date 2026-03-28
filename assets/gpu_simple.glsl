#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

// Single texture: each pixel = one cell's fg color (RGBA)
// texture0 is bound automatically by Raylib's DrawTexturePro
uniform sampler2D texture0;
uniform vec2 resolution;
uniform vec2 gridSize;
uniform vec2 cellSize;

void main() {
    // Screen pixel position
    vec2 pixelPos = fragTexCoord * resolution;

    // Which cell?
    vec2 cellCoord = floor(pixelPos / cellSize);

    // Bounds check
    if (cellCoord.x < 0.0 || cellCoord.x >= gridSize.x ||
        cellCoord.y < 0.0 || cellCoord.y >= gridSize.y) {
        finalColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // Sample cell color (center of texel for POINT filtering)
    vec2 cellUV = (cellCoord + 0.5) / gridSize;
    finalColor = texture(texture0, cellUV);
    finalColor.a = 1.0;
}
