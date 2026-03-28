#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec2 resolution;
uniform float bloomIntensity;
uniform float bloomThreshold;

out vec4 finalColor;

void main() {
    vec4 color = texture(texture0, fragTexCoord);

    // Sample neighbors for bloom
    vec2 texelSize = 1.0 / resolution;
    vec4 bloom = vec4(0.0);
    float count = 0.0;

    for (int x = -2; x <= 2; x++) {
        for (int y = -2; y <= 2; y++) {
            vec4 sample_color = texture(texture0, fragTexCoord + vec2(float(x), float(y)) * texelSize);
            float brightness = dot(sample_color.rgb, vec3(0.2126, 0.7152, 0.0722));
            if (brightness > bloomThreshold) {
                bloom += sample_color;
                count += 1.0;
            }
        }
    }

    if (count > 0.0) {
        bloom /= count;
    }

    finalColor = color + bloom * bloomIntensity;
    finalColor.a = 1.0;
}
