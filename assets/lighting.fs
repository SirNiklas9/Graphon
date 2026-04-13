#version 330

in vec3 fragPosition;
in vec2 fragTexCoord;
in vec3 fragNormal;
in vec4 fragColor;
in mat3 fragTBN;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec3 viewPos;
uniform vec3 ambientColor;

// Material properties (per-object)
uniform float materialSpecular;
uniform float materialRoughness;

// Per-object Grafel resolution — written to alpha, read by gpu_grid.glsl
// 1.0 = native detail, < 1.0 = reduced (solid color per cell)
uniform float grafelResolution;



// Normal mapping
uniform sampler2D normalMap;
uniform int hasNormalMap;

// Shadow mapping
uniform sampler2D shadowMap;
uniform mat4 lightVP;
uniform int shadowEnabled;
uniform int shadowLightIdx;
uniform int shadowMapResolution;

// Fog
uniform vec3 fogColor;
uniform float fogStart;
uniform float fogEnd;
uniform int fogEnabled;

// Volumes — 3D regions with custom fog/ambient
#define MAX_VOLUMES 4
struct Volume {
    vec3 minPos;
    vec3 maxPos;
    vec3 color;     // Fog/tint color
    float density;  // 0 = no effect, 1 = full tint
    int enabled;
};
uniform Volume volumes[MAX_VOLUMES];

#define MAX_LIGHTS 4

struct Light {
    int enabled;
    int type;       // 0 = directional, 1 = point
    vec3 position;
    vec3 target;
    vec3 color;
};

uniform Light lights[MAX_LIGHTS];

out vec4 finalColor;

// ACES filmic tone mapping — preserves saturation better than Reinhard
vec3 acesToneMap(vec3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

void main() {
    vec4 texColor = texture(texture0, fragTexCoord);

    // sRGB → linear (proper input conversion)
    vec3 baseColor = pow(texColor.rgb * colDiffuse.rgb * fragColor.rgb, vec3(2.2));

    vec3 viewDir = normalize(viewPos - fragPosition);

    // Normal — use normal map if available, otherwise vertex normal
    vec3 norm;
    if (hasNormalMap == 1) {
        vec3 mapNormal = texture(normalMap, fragTexCoord).rgb * 2.0 - 1.0;
        norm = normalize(fragTBN * mapNormal);
    } else {
        norm = normalize(fragNormal);
    }

    // Lighting accumulation (all math in linear space)
    vec3 lightDot = vec3(0.0);
    vec3 specTotal = vec3(0.0);

    for (int i = 0; i < MAX_LIGHTS; i++) {
        if (lights[i].enabled == 0) continue;

        vec3 lightDir;
        float attenuation = 1.0;

        if (lights[i].type == 0) {
            lightDir = -normalize(lights[i].target - lights[i].position);
        } else {
            vec3 toLight = lights[i].position - fragPosition;
            float dist = length(toLight);
            lightDir = normalize(toLight);
            attenuation = 1.0 / (1.0 + 0.09 * dist + 0.032 * dist * dist);
        }

        // Diffuse
        float NdotL = max(dot(norm, lightDir), 0.0);
        lightDot += lights[i].color * NdotL * attenuation;

        // Specular — per-object material, suppressed on upward-facing surfaces (ground)
        float upFacing = abs(dot(norm, vec3(0.0, 1.0, 0.0)));
        float specMask = 1.0 - smoothstep(0.7, 0.95, upFacing);
        if (NdotL > 0.0 && specMask > 0.0 && materialSpecular > 0.0) {
            float shininess = pow(2.0, 10.0 * (1.0 - materialRoughness));
            float specCo = pow(max(0.0, dot(viewDir, reflect(-lightDir, norm))), shininess);
            specTotal += lights[i].color * specCo * materialSpecular * specMask * attenuation;
        }
    }

    // Compute lit color (before shadow)
    vec3 result = baseColor * (lightDot + specTotal);

    // Shadow calculation
    if (shadowEnabled == 1) {
        vec4 fragPosLightSpace = lightVP * vec4(fragPosition, 1.0);
        fragPosLightSpace.xyz /= fragPosLightSpace.w;
        fragPosLightSpace.xyz = (fragPosLightSpace.xyz + 1.0) / 2.0;
        vec2 sampleCoords = fragPosLightSpace.xy;
        float curDepth = fragPosLightSpace.z;

        if (sampleCoords.x >= 0.0 && sampleCoords.x <= 1.0 &&
            sampleCoords.y >= 0.0 && sampleCoords.y <= 1.0 &&
            curDepth <= 1.0 && curDepth >= 0.0) {

            vec3 l = -normalize(lights[shadowLightIdx].target - lights[shadowLightIdx].position);
            float bias = max(0.0005 * (1.0 - dot(norm, l)), 0.00005) + 0.00002;

            // Rotated Poisson disk PCF — per-pixel rotation breaks ALL visible patterns
            const vec2 poissonDisk[16] = vec2[16](
                vec2(-0.94201624, -0.39906216), vec2( 0.94558609, -0.76890725),
                vec2(-0.09418410, -0.92938870), vec2( 0.34495938,  0.29387760),
                vec2(-0.91588581,  0.45771432), vec2(-0.81544232, -0.87912464),
                vec2(-0.38277543,  0.27676845), vec2( 0.97484398,  0.75648379),
                vec2( 0.44323325, -0.97511554), vec2( 0.53742981, -0.47373420),
                vec2(-0.26496911, -0.41893023), vec2( 0.79197514,  0.19090188),
                vec2(-0.24188840,  0.99706507), vec2(-0.81409955,  0.91437590),
                vec2( 0.19984126,  0.78641367), vec2( 0.14383161, -0.14100790)
            );

            // Per-pixel random rotation angle — makes each pixel sample differently
            float angle = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) * 6.2832;
            float ca = cos(angle);
            float sa = sin(angle);

            float shadow = 0.0;
            float spread = 5.0 / float(shadowMapResolution); // wider spread = softer transition
            for (int i = 0; i < 16; i++) {
                // Rotate each Poisson sample by the per-pixel angle
                vec2 rotated = vec2(
                    poissonDisk[i].x * ca - poissonDisk[i].y * sa,
                    poissonDisk[i].x * sa + poissonDisk[i].y * ca
                );
                float sampleDepth = texture(shadowMap, sampleCoords + rotated * spread).r;
                if (curDepth - bias > sampleDepth) shadow += 1.0;
            }
            shadow /= 16.0;

            result = mix(result, vec3(0.0), shadow);
        }
    }

    // World-space ambient occlusion — no camera dependency, fully stable
    // Ground proximity: surfaces near the ground get darker ambient
    float groundAO = smoothstep(0.0, 2.0, fragPosition.y) * 0.5 + 0.5;

    // Cavity: downward-facing surfaces are likely in crevices/undercuts
    float upDot = dot(norm, vec3(0.0, 1.0, 0.0));
    float cavityAO = smoothstep(-0.5, 0.5, upDot) * 0.4 + 0.6;

    float worldAO = groundAO * cavityAO;

    // Add ambient with world-space AO (always visible, even in shadow)
    result += baseColor * ambientColor * worldAO;

    // Distance fog
    if (fogEnabled == 1) {
        float dist = length(viewPos - fragPosition);
        float fogFactor = clamp((dist - fogStart) / (fogEnd - fogStart), 0.0, 1.0);
        result = mix(result, fogColor, fogFactor);
    }

    // Volume fog/tint — apply if fragment is inside a volume
    for (int v = 0; v < MAX_VOLUMES; v++) {
        if (volumes[v].enabled == 0) continue;
        if (fragPosition.x >= volumes[v].minPos.x && fragPosition.x <= volumes[v].maxPos.x &&
            fragPosition.y >= volumes[v].minPos.y && fragPosition.y <= volumes[v].maxPos.y &&
            fragPosition.z >= volumes[v].minPos.z && fragPosition.z <= volumes[v].maxPos.z) {
            result = mix(result, volumes[v].color, volumes[v].density);
        }
    }

    // ACES tone mapping (linear HDR → [0,1])
    result = acesToneMap(result);

    // Linear → sRGB (proper output conversion)
    result = pow(result, vec3(1.0 / 2.2));

    // Dither to break 8-bit color banding — ±0.5 LSB noise, imperceptible
    float noise = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);
    result += (noise - 0.5) / 255.0;

    // Per-object Grafel resolution — direct control, no distance compensation
    // grafelResolution >= 1.0 = native. Lower = chunkier. Written directly to alpha.
    float outAlpha = clamp(grafelResolution, 0.10, 1.0);
    finalColor = vec4(result, outAlpha);
}
