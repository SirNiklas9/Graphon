#version 330

// Bloom downsample + bright pass / blur
// Used at each mip level to downsample and blur the bright pixels

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec2 resolution;     // resolution of THIS level (not source)
uniform float bloomThreshold; // only used on first pass
uniform int firstPass;        // 1 = extract bright, 0 = just downsample+blur

void main() {
    vec2 texelSize = 1.0 / resolution;
    vec2 uv = fragTexCoord;

    // 13-tap downsample filter (from Call of Duty: Advanced Warfare presentation)
    // Reduces firefly artifacts compared to simple bilinear
    vec3 a = texture(texture0, uv + vec2(-2.0, -2.0) * texelSize).rgb;
    vec3 b = texture(texture0, uv + vec2( 0.0, -2.0) * texelSize).rgb;
    vec3 c = texture(texture0, uv + vec2( 2.0, -2.0) * texelSize).rgb;
    vec3 d = texture(texture0, uv + vec2(-2.0,  0.0) * texelSize).rgb;
    vec3 e = texture(texture0, uv).rgb;
    vec3 f = texture(texture0, uv + vec2( 2.0,  0.0) * texelSize).rgb;
    vec3 g = texture(texture0, uv + vec2(-2.0,  2.0) * texelSize).rgb;
    vec3 h = texture(texture0, uv + vec2( 0.0,  2.0) * texelSize).rgb;
    vec3 i = texture(texture0, uv + vec2( 2.0,  2.0) * texelSize).rgb;
    vec3 j = texture(texture0, uv + vec2(-1.0, -1.0) * texelSize).rgb;
    vec3 k = texture(texture0, uv + vec2( 1.0, -1.0) * texelSize).rgb;
    vec3 l = texture(texture0, uv + vec2(-1.0,  1.0) * texelSize).rgb;
    vec3 m = texture(texture0, uv + vec2( 1.0,  1.0) * texelSize).rgb;

    vec3 color = (j + k + l + m) * 0.125;
    color += (a + c + g + i) * 0.03125;
    color += (b + d + f + h) * 0.0625;
    color += e * 0.125;

    if (firstPass == 1) {
        // Use alpha to exclude sky (alpha=0) from bloom
        float alpha = texture(texture0, uv).a;

        // Bright pass — soft knee extraction, masked by alpha
        float brightness = dot(color, vec3(0.2126, 0.7152, 0.0722));
        float knee = bloomThreshold * 0.3;
        float soft = clamp((brightness - bloomThreshold + knee) / (2.0 * knee + 0.0001), 0.0, 1.0);
        color *= soft * alpha;
    }

    finalColor = vec4(color, 1.0);
}
