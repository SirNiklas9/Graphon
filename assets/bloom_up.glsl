#version 330

// Bloom upsample — tent filter for smooth blending between mip levels

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec2 resolution;  // resolution of the SMALLER source texture

void main() {
    vec2 texelSize = 1.0 / resolution;
    vec2 uv = fragTexCoord;

    // 9-tap tent filter for smooth upsampling
    vec3 color = vec3(0.0);
    color += texture(texture0, uv + vec2(-1.0, -1.0) * texelSize).rgb * 1.0;
    color += texture(texture0, uv + vec2( 0.0, -1.0) * texelSize).rgb * 2.0;
    color += texture(texture0, uv + vec2( 1.0, -1.0) * texelSize).rgb * 1.0;
    color += texture(texture0, uv + vec2(-1.0,  0.0) * texelSize).rgb * 2.0;
    color += texture(texture0, uv).rgb * 4.0;
    color += texture(texture0, uv + vec2( 1.0,  0.0) * texelSize).rgb * 2.0;
    color += texture(texture0, uv + vec2(-1.0,  1.0) * texelSize).rgb * 1.0;
    color += texture(texture0, uv + vec2( 0.0,  1.0) * texelSize).rgb * 2.0;
    color += texture(texture0, uv + vec2( 1.0,  1.0) * texelSize).rgb * 1.0;
    color /= 16.0;

    finalColor = vec4(color, 1.0);
}
