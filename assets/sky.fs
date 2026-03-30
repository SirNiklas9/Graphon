#version 330

in vec3 fragPosition;
in vec2 fragTexCoord;
in vec3 fragNormal;
in vec4 fragColor;

uniform vec3 viewPos;
uniform vec3 sunDirection; // Direction TO the sun

out vec4 finalColor;

void main() {
    vec3 dir = normalize(fragPosition - viewPos);
    float y = dir.y;

    // Atmospheric scattering approximation
    // Rayleigh: blue scatters more at zenith, warm at horizon
    vec3 zenith    = vec3(0.05, 0.08, 0.20);   // Deep blue
    vec3 skyBlue   = vec3(0.15, 0.25, 0.55);   // Mid sky blue
    vec3 horizon   = vec3(0.45, 0.40, 0.35);   // Warm haze at horizon
    vec3 sunGlow   = vec3(0.8, 0.5, 0.2);      // Warm sun glow
    vec3 ground    = vec3(0.03, 0.03, 0.05);    // Dark below

    vec3 color;
    if (y > 0.0) {
        // Above horizon
        float t = clamp(y, 0.0, 1.0);

        // Base gradient: horizon → sky blue → zenith
        if (t < 0.15) {
            color = mix(horizon, skyBlue, t / 0.15);
        } else if (t < 0.6) {
            color = mix(skyBlue, zenith, (t - 0.15) / 0.45);
        } else {
            color = zenith;
        }

        // Sun glow — bright warm area near sun direction
        float sunDot = max(dot(dir, sunDirection), 0.0);
        float sunIntensity = pow(sunDot, 32.0) * 1.5;   // Tight sun disc
        float hazeIntensity = pow(sunDot, 4.0) * 0.3;    // Wide haze around sun
        color += sunGlow * (sunIntensity + hazeIntensity);

        // Horizon haze — gets hazier near horizon
        float hazeFactor = pow(1.0 - t, 4.0);
        color = mix(color, horizon, hazeFactor * 0.5);
    } else {
        // Below horizon
        color = mix(horizon * 0.5, ground, clamp(-y * 5.0, 0.0, 1.0));
    }

    finalColor = vec4(color, 1.0);
}
