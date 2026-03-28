#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec2 resolution;
uniform float scanlineIntensity;
uniform float time;

out vec4 finalColor;

void main() {
    vec4 color = texture(texture0, fragTexCoord);

    // Scanline effect
    float scanline = sin(fragTexCoord.y * resolution.y * 3.14159) * 0.5 + 0.5;
    scanline = mix(1.0, scanline, scanlineIntensity);
    color.rgb *= scanline;

    // Subtle vignette
    vec2 uv = fragTexCoord * 2.0 - 1.0;
    float vignette = 1.0 - dot(uv, uv) * 0.3;
    color.rgb *= vignette;

    finalColor = color;
    finalColor.a = 1.0;
}
