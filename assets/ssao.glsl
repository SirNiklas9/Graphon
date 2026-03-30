#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;  // Scene color
uniform sampler2D depthTex;  // R=depth, G=normal.x, B=normal.y
uniform vec2 resolution;
uniform float ssaoRadius;
uniform float ssaoStrength;

void main() {
    vec3 color = texture(texture0, fragTexCoord).rgb;
    vec3 depthData = texture(depthTex, fragTexCoord).rgb;
    float centerDepth = depthData.r;

    // Skip sky
    if (centerDepth > 0.95 || centerDepth < 0.001) {
        finalColor = vec4(color, 1.0);
        return;
    }

    // Reconstruct normal from packed data
    vec3 norm = vec3(depthData.g * 2.0 - 1.0, depthData.b * 2.0 - 1.0, 0.0);
    norm.z = sqrt(max(0.0, 1.0 - norm.x * norm.x - norm.y * norm.y));

    vec2 texelSize = 1.0 / resolution;

    // Sample neighbors and compare depth — but normalize by expected depth change
    // The key: compare depth differences against what a FLAT surface would produce
    // Compute expected depth gradient from nearby samples
    float dRight = texture(depthTex, fragTexCoord + vec2(texelSize.x, 0.0)).r;
    float dLeft  = texture(depthTex, fragTexCoord - vec2(texelSize.x, 0.0)).r;
    float dUp    = texture(depthTex, fragTexCoord + vec2(0.0, texelSize.y)).r;
    float dDown  = texture(depthTex, fragTexCoord - vec2(0.0, texelSize.y)).r;

    // Depth gradient — how much depth changes per pixel on THIS surface
    vec2 depthGrad = vec2(dRight - dLeft, dUp - dDown) * 0.5;
    float gradMag = length(depthGrad);

    // For each sample: predict what depth SHOULD be (based on gradient)
    // vs what depth ACTUALLY is. Difference = occlusion.
    float ao = 0.0;
    float samples = 0.0;

    vec2 offsets[8] = vec2[8](
        vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
        vec2(1.0, 1.0), vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(-1.0, 1.0)
    );

    for (int i = 0; i < 8; i++) {
        vec2 offset = offsets[i] * ssaoRadius;
        vec2 sampleUV = fragTexCoord + offset * texelSize;
        float sampleDepth = texture(depthTex, sampleUV).r;

        // Predicted depth at this offset (linear extrapolation from gradient)
        float predictedDepth = centerDepth + dot(depthGrad, offset);

        // How much does actual depth deviate from predicted?
        float deviation = sampleDepth - predictedDepth;

        // Negative deviation = sample is closer than expected = geometry occluding
        if (deviation < -0.002 && deviation > -0.05) {
            ao += clamp(-deviation * 20.0, 0.0, 1.0);
            samples += 1.0;
        }
    }

    if (samples > 0.0) ao /= samples;
    ao = clamp(ao * ssaoStrength, 0.0, 0.5);

    finalColor = vec4(color * (1.0 - ao), 1.0);
}
