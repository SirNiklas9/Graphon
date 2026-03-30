#version 330

in vec3 fragPosition;
in vec2 fragTexCoord;
in vec3 fragNormal;
in vec4 fragColor;

uniform vec3 viewPos;

out vec4 finalColor;

void main() {
    // View-space Z depth (distance along camera forward, not Euclidean)
    // This is linear in clip space — no perspective distortion on flat surfaces
    vec3 toFrag = fragPosition - viewPos;
    float depth = length(toFrag);
    float normalizedDepth = clamp(depth / 80.0, 0.0, 1.0);

    // Pack: R = depth, G = normal.x, B = normal.y (view-facing info)
    vec3 norm = normalize(fragNormal);
    finalColor = vec4(normalizedDepth, norm.x * 0.5 + 0.5, norm.y * 0.5 + 0.5, 1.0);
}
