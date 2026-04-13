#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform vec4 colDiffuse;

out vec4 finalColor;

void main() {
    // Output pure tint color — ignore all textures
    finalColor = colDiffuse;
}
