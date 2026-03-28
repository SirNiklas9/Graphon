#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float time;
uniform vec2 gridSize;
uniform vec2 screenRes;
uniform vec3 camPos;
uniform vec3 camTarget;

// Raymarching SDF 3D scene — entirely on GPU
float sdBox3D(vec3 p, vec3 b) {
    vec3 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0);
}

float sdSphere(vec3 p, float r) {
    return length(p) - r;
}

float sdPlane(vec3 p, float h) {
    return p.y - h;
}

float sdCylinder(vec3 p, float r, float h) {
    float d = length(p.xz) - r;
    return max(d, abs(p.y) - h);
}

// Rotate around Y
vec3 rotY(vec3 p, float a) {
    float c = cos(a), s = sin(a);
    return vec3(c*p.x + s*p.z, p.y, -s*p.x + c*p.z);
}

struct HitResult {
    float dist;
    int id; // 0=ground, 1=cube, 2-5=pillars
};

HitResult scene(vec3 p) {
    HitResult h;
    h.dist = 1e10;
    h.id = 0;

    // Ground plane
    float ground = sdPlane(p, 0.0);
    if (ground < h.dist) { h.dist = ground; h.id = 0; }

    // Spinning cube
    vec3 cp = rotY(p - vec3(0.0, 2.0, 0.0), time);
    float cube = sdBox3D(cp, vec3(1.5));
    if (cube < h.dist) { h.dist = cube; h.id = 1; }

    // 4 pillars
    vec3 pillarPos[4] = vec3[](
        vec3(-6.0, 3.0, -4.0),
        vec3(6.0, 3.0, -4.0),
        vec3(-6.0, 3.0, 4.0),
        vec3(6.0, 3.0, 4.0)
    );
    for (int i = 0; i < 4; i++) {
        float pil = sdCylinder(p - pillarPos[i], 0.6, 3.0);
        if (pil < h.dist) { h.dist = pil; h.id = 2 + i; }
    }

    return h;
}

vec3 calcNormal(vec3 p) {
    vec2 e = vec2(0.001, 0.0);
    return normalize(vec3(
        scene(p + e.xyy).dist - scene(p - e.xyy).dist,
        scene(p + e.yxy).dist - scene(p - e.yxy).dist,
        scene(p + e.yyx).dist - scene(p - e.yyx).dist
    ));
}

void main() {
    vec2 tc = vec2(fragTexCoord.x, 1.0 - fragTexCoord.y);
    vec2 cellCoord = floor(tc * gridSize);
    vec2 uv = (cellCoord / gridSize) * 2.0 - 1.0;
    uv.x *= screenRes.x / screenRes.y;

    // Camera — from CPU uniforms (WASD + mouse controlled)
    vec3 ro = camPos;
    vec3 target = camTarget;
    vec3 forward = normalize(target - ro);
    vec3 right = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
    vec3 up = cross(right, forward);

    // Match CPU camera FOV (60 degrees vertical)
    float fovScale = tan(radians(60.0) * 0.5);
    vec3 rd = normalize(forward + uv.x * right * fovScale + uv.y * up * fovScale);

    // Raymarch
    float t = 0.0;
    HitResult hit;
    for (int i = 0; i < 80; i++) {
        hit = scene(ro + rd * t);
        if (hit.dist < 0.01) break;
        t += hit.dist;
        if (t > 60.0) break;
    }

    vec3 color = vec3(0.08, 0.08, 0.1); // fog/sky color

    if (t < 60.0) {
        vec3 pos = ro + rd * t;
        vec3 nor = calcNormal(pos);

        // Material colors
        vec3 matColor;
        if (hit.id == 0) {
            // Checkerboard ground
            float checker = mod(floor(pos.x) + floor(pos.z), 2.0);
            matColor = mix(vec3(0.3), vec3(0.5), checker);
        } else if (hit.id == 1) {
            matColor = vec3(0.9, 0.15, 0.1); // red cube
        } else if (hit.id == 2) {
            matColor = vec3(0.1, 0.8, 0.2); // green
        } else if (hit.id == 3) {
            matColor = vec3(0.1, 0.3, 0.9); // blue
        } else if (hit.id == 4) {
            matColor = vec3(0.1, 0.8, 0.8); // cyan
        } else {
            matColor = vec3(0.9, 0.8, 0.1); // yellow
        }

        // Directional light
        vec3 lightDir = normalize(vec3(-0.5, 1.0, 0.3));
        float diff = max(dot(nor, lightDir), 0.0);
        float amb = 0.15;

        // Point light (orbiting)
        vec3 lightPos = vec3(cos(time * 0.7) * 6.0, 4.0, sin(time * 0.7) * 6.0);
        vec3 toLight = lightPos - pos;
        float lightDist = length(toLight);
        float pointDiff = max(dot(nor, toLight / lightDist), 0.0);
        float atten = 1.0 / (1.0 + lightDist * lightDist * 0.02);
        vec3 pointColor = vec3(1.0, 0.6, 0.3) * pointDiff * atten;

        color = matColor * (amb + diff * 0.7) + pointColor * 0.5;

        // Depth fog
        float fog = 1.0 - exp(-t * 0.03);
        color = mix(color, vec3(0.08, 0.08, 0.1), fog);
    }

    finalColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
