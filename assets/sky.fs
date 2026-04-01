#version 330

in vec3 fragPosition;
in vec2 fragTexCoord;
in vec3 fragNormal;
in vec4 fragColor;

uniform sampler2D texture0;    // Skybox panorama (equirectangular)
uniform samplerCube skyboxCube; // Cubemap skybox (6-face)
uniform vec3 viewPos;
uniform vec3 sunDirection;     // Direction TO the sun (current light)
uniform int useTexture;        // 1 = sample panorama, 0 = procedural
uniform int useCubemap;        // 1 = sample cubemap, 0 = no cubemap
uniform float skyboxRotation;  // unused
uniform int nightMode;         // 1 = night (moon), 0 = day (sun)

out vec4 finalColor;

const float PI = 3.14159265;

void main() {
    // Discard outer surface — we're inside the sphere, only render inner face
    if (gl_FrontFacing) discard;

    vec3 dir = normalize(fragPosition - viewPos);

    // ─── Cubemap skybox (highest priority) ───
    if (useCubemap == 1) {
        vec3 sky = texture(skyboxCube, dir).rgb;

        // Overlay procedural sun/moon
        vec3 lightDir = normalize(sunDirection);
        float lightDot = max(dot(dir, lightDir), 0.0);
        if (nightMode == 0) {
            vec3 sunCol = vec3(1.0, 0.95, 0.85);
            sky += sunCol * (pow(lightDot, 800.0) * 5.0 + pow(lightDot, 64.0) * 0.3 + pow(lightDot, 8.0) * 0.05);
        } else {
            vec3 moonCol = vec3(0.9, 0.92, 1.0);
            sky += moonCol * (pow(lightDot, 1200.0) * 3.0 + pow(lightDot, 80.0) * 0.15);
        }
        finalColor = vec4(sky, 1.0);
        return;
    }

    // ─── Equirectangular panorama skybox ───
    if (useTexture == 1) {
        // Sample panorama as-is (no rotation — clouds stay fixed)
        float u = atan(dir.z, dir.x) / (2.0 * PI) + 0.5;
        float v = 0.5 - asin(clamp(dir.y, -1.0, 1.0)) / PI;
        vec3 sky = texture(texture0, vec2(u, v)).rgb;

        // Overlay procedural sun or moon at the directional light position
        vec3 lightDir = normalize(sunDirection);
        float lightDot = max(dot(dir, lightDir), 0.0);

        if (nightMode == 0) {
            // Sun — small bright disc with corona
            vec3 sunCol = vec3(1.0, 0.95, 0.85);
            float disc   = pow(lightDot, 800.0) * 5.0;   // small tight core
            float corona = pow(lightDot, 64.0) * 0.3;    // subtle glow
            float haze   = pow(lightDot, 8.0) * 0.05;    // faint warm haze
            sky += sunCol * (disc + corona + haze);
        } else {
            // Moon — cool white disc, no corona, subtle glow
            vec3 moonCol = vec3(0.9, 0.92, 1.0);
            float disc   = pow(lightDot, 1200.0) * 3.0;  // sharp moon disc
            float glow   = pow(lightDot, 80.0) * 0.15;   // soft halo
            sky += moonCol * (disc + glow);
        }

        finalColor = vec4(sky, 1.0);
        return;
    }

    // ─── Procedural fallback ───
    float y = max(dir.y, 0.0);

    vec3 zenith, skyMid, skyLow, horizon;
    if (nightMode == 0) {
        zenith  = vec3(0.04, 0.06, 0.18);
        skyMid  = vec3(0.12, 0.22, 0.50);
        skyLow  = vec3(0.30, 0.35, 0.50);
        horizon = vec3(0.50, 0.45, 0.40);
    } else {
        zenith  = vec3(0.005, 0.005, 0.02);
        skyMid  = vec3(0.01, 0.01, 0.04);
        skyLow  = vec3(0.02, 0.02, 0.05);
        horizon = vec3(0.03, 0.03, 0.06);
    }

    float alt = clamp(y, 0.0, 1.0);

    vec3 skyColor;
    float low  = smoothstep(0.0, 0.12, alt);
    float mid  = smoothstep(0.08, 0.35, alt);
    float high = smoothstep(0.30, 0.70, alt);
    skyColor = mix(horizon, skyLow, low);
    skyColor = mix(skyColor, skyMid, mid);
    skyColor = mix(skyColor, zenith, high);

    float lightDotP = max(dot(dir, normalize(sunDirection)), 0.0);
    if (nightMode == 0) {
        vec3 sunCol = vec3(1.0, 0.95, 0.85);
        float disc   = pow(lightDotP, 800.0) * 5.0;
        float corona = pow(lightDotP, 64.0) * 0.3;
        float haze   = pow(lightDotP, 8.0) * 0.05;
        skyColor += sunCol * (disc + corona + haze);
    } else {
        vec3 moonCol = vec3(0.9, 0.92, 1.0);
        float disc = pow(lightDotP, 1200.0) * 3.0;
        float glow = pow(lightDotP, 80.0) * 0.15;
        skyColor += moonCol * (disc + glow);
    }

    finalColor = vec4(skyColor, 1.0);
}
