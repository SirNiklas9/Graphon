#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec2 resolution;
uniform float aberrationAmount;

out vec4 finalColor;

void main() {
    vec2 texelSize = 1.0 / resolution;
    float offset = aberrationAmount;

    float r = texture(texture0, fragTexCoord + vec2(offset, 0.0) * texelSize).r;
    float g = texture(texture0, fragTexCoord).g;
    float b = texture(texture0, fragTexCoord - vec2(offset, 0.0) * texelSize).b;

    finalColor = vec4(r, g, b, 1.0);
}
