#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float time;
uniform vec2 gridSize;

// === 3D Raymarching ===
float sdBox3D(vec3 p, vec3 b) {
    vec3 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0);
}

float sdSphere(vec3 p, float r) { return length(p) - r; }
float sdPlane(vec3 p, float h) { return p.y - h; }

float sdCylinder(vec3 p, float r, float h) {
    float d = length(p.xz) - r;
    return max(d, abs(p.y) - h);
}

float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

vec3 rotY(vec3 p, float a) {
    float c = cos(a), s = sin(a);
    return vec3(c*p.x + s*p.z, p.y, -s*p.x + c*p.z);
}

struct Hit { float dist; int id; };

Hit scene(vec3 p) {
    Hit h; h.dist = 1e10; h.id = 0;

    // Ground
    float ground = sdPlane(p, 0.0);
    if (ground < h.dist) { h.dist = ground; h.id = 0; }

    // Spinning cube
    vec3 cp = rotY(p - vec3(0.0, 2.0, 0.0), time * 0.8);
    float cube = sdBox3D(cp, vec3(1.2));
    if (cube < h.dist) { h.dist = cube; h.id = 1; }

    // Floating sphere
    vec3 sp = p - vec3(4.0, 1.5 + sin(time) * 0.5, -2.0);
    float sphere = sdSphere(sp, 1.0);
    if (sphere < h.dist) { h.dist = sphere; h.id = 2; }

    // Torus
    vec3 tp = rotY(p - vec3(-4.0, 1.5, -1.0), time * 0.5);
    float torus = sdTorus(tp, vec2(1.2, 0.4));
    if (torus < h.dist) { h.dist = torus; h.id = 3; }

    // 4 pillars
    vec3 pillarPos[4] = vec3[](
        vec3(-7.0, 2.5, -5.0), vec3(7.0, 2.5, -5.0),
        vec3(-7.0, 2.5, 5.0),  vec3(7.0, 2.5, 5.0)
    );
    for (int i = 0; i < 4; i++) {
        float pil = sdCylinder(p - pillarPos[i], 0.5, 2.5);
        if (pil < h.dist) { h.dist = pil; h.id = 4 + i; }
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

vec3 render3D(vec2 uv) {
    float aspect = gridSize.x / gridSize.y;
    uv.x *= aspect;

    // Orbiting camera
    vec3 ro = vec3(sin(time * 0.2) * 14.0, 7.0, cos(time * 0.2) * 14.0);
    vec3 target = vec3(0.0, 1.5, 0.0);
    vec3 forward = normalize(target - ro);
    vec3 right = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
    vec3 up = cross(right, forward);
    float fov = tan(radians(55.0) * 0.5);
    vec3 rd = normalize(forward + uv.x * right * fov + uv.y * up * fov);

    // Raymarch
    float t = 0.0;
    Hit hit;
    for (int i = 0; i < 64; i++) {
        hit = scene(ro + rd * t);
        if (hit.dist < 0.005) break;
        t += hit.dist;
        if (t > 50.0) break;
    }

    vec3 sky = vec3(0.05, 0.05, 0.08);
    if (t >= 50.0) return sky;

    vec3 pos = ro + rd * t;
    vec3 nor = calcNormal(pos);

    // Materials
    vec3 matColor;
    if (hit.id == 0) {
        float checker = mod(floor(pos.x) + floor(pos.z), 2.0);
        matColor = mix(vec3(0.25), vec3(0.45), checker);
    } else if (hit.id == 1) { matColor = vec3(0.9, 0.15, 0.1); }
    else if (hit.id == 2) { matColor = vec3(0.1, 0.6, 0.9); }
    else if (hit.id == 3) { matColor = vec3(0.9, 0.7, 0.1); }
    else if (hit.id == 4) { matColor = vec3(0.1, 0.8, 0.2); }
    else if (hit.id == 5) { matColor = vec3(0.2, 0.3, 0.9); }
    else if (hit.id == 6) { matColor = vec3(0.8, 0.2, 0.7); }
    else { matColor = vec3(0.1, 0.8, 0.8); }

    // Lighting
    vec3 lightDir = normalize(vec3(-0.4, 0.8, 0.3));
    float diff = max(dot(nor, lightDir), 0.0);
    float spec = pow(max(dot(reflect(-lightDir, nor), -rd), 0.0), 16.0);
    float amb = 0.12;

    // Point light
    vec3 lightPos = vec3(cos(time * 0.6) * 5.0, 3.5, sin(time * 0.6) * 5.0);
    vec3 toLight = lightPos - pos;
    float ld = length(toLight);
    float pDiff = max(dot(nor, toLight / ld), 0.0);
    float atten = 1.0 / (1.0 + ld * ld * 0.03);
    vec3 pointCol = vec3(1.0, 0.6, 0.3) * pDiff * atten;

    vec3 color = matColor * (amb + diff * 0.65) + vec3(1.0) * spec * 0.3 + pointCol * 0.4;

    // Fog
    float fog = 1.0 - exp(-t * 0.025);
    color = mix(color, sky, fog);

    return color;
}

// === 2D HUD Elements ===
float sdBox2D(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

vec4 renderHUD(vec2 uv, vec3 sceneColor) {
    vec3 color = sceneColor;
    float alpha = 0.0;

    // Health bar (bottom-left)
    vec2 hpPos = uv - vec2(0.05, 0.92);
    float hpBar = sdBox2D(hpPos - vec2(0.1, 0.0), vec2(0.1, 0.012));
    if (hpBar < 0.0) {
        float fill = 0.7 + 0.1 * sin(time * 2.0); // pulsing health
        float barFill = step(hpPos.x, fill * 0.2);
        color = mix(vec3(0.8, 0.1, 0.1), vec3(0.1, 0.9, 0.2), fill) * barFill;
        color += vec3(0.15) * (1.0 - barFill);
        alpha = 0.9;
    }
    // Health bar outline
    float hpOutline = abs(sdBox2D(hpPos - vec2(0.1, 0.0), vec2(0.102, 0.014)));
    if (hpOutline < 0.003) { color = vec3(0.8); alpha = 0.9; }

    // Energy bar (below health)
    vec2 enPos = uv - vec2(0.05, 0.95);
    float enBar = sdBox2D(enPos - vec2(0.075, 0.0), vec2(0.075, 0.008));
    if (enBar < 0.0) {
        float fill = 0.5 + 0.5 * sin(time * 1.5);
        float barFill = step(enPos.x, fill * 0.15);
        color = vec3(0.2, 0.5, 1.0) * barFill + vec3(0.1) * (1.0 - barFill);
        alpha = 0.85;
    }

    // Minimap (top-right corner)
    vec2 mmPos = uv - vec2(0.85, 0.05);
    float mmBg = sdBox2D(mmPos - vec2(0.065, 0.065), vec2(0.065, 0.065));
    if (mmBg < 0.0) {
        color = vec3(0.05, 0.1, 0.05);
        alpha = 0.8;

        // Minimap dots (objects)
        vec2 mmUV = (mmPos) / 0.13;
        float dot1 = length(mmUV - vec2(0.5 + sin(time * 0.2) * 0.3, 0.5 + cos(time * 0.2) * 0.3));
        if (dot1 < 0.08) { color = vec3(0.0, 1.0, 0.0); }

        // Player dot (center, pulsing)
        float player = length(mmUV - vec2(0.5, 0.5));
        if (player < 0.06 + 0.02 * sin(time * 4.0)) { color = vec3(1.0, 1.0, 1.0); }

        // Enemy dots
        for (int i = 0; i < 3; i++) {
            float seed = float(i) * 2.1;
            vec2 ePos = vec2(0.3 + sin(time * 0.5 + seed) * 0.3, 0.3 + cos(time * 0.7 + seed) * 0.3);
            if (length(mmUV - ePos) < 0.05) { color = vec3(1.0, 0.2, 0.2); }
        }
    }
    // Minimap border
    float mmBorder = abs(sdBox2D(mmPos - vec2(0.065, 0.065), vec2(0.067, 0.067)));
    if (mmBorder < 0.003) { color = vec3(0.4, 0.6, 0.4); alpha = 0.9; }

    // Crosshair (center)
    vec2 chPos = uv - vec2(0.5, 0.5);
    if ((abs(chPos.x) < 0.015 && abs(chPos.y) < 0.002) ||
        (abs(chPos.y) < 0.015 && abs(chPos.x) < 0.002)) {
        if (abs(chPos.x) > 0.004 || abs(chPos.y) > 0.004) {
            color = vec3(0.9, 0.9, 0.9);
            alpha = 0.7;
        }
    }

    // FPS-style ammo counter (bottom-right)
    vec2 ammoPos = uv - vec2(0.88, 0.92);
    float ammoBg = sdBox2D(ammoPos - vec2(0.05, 0.015), vec2(0.05, 0.015));
    if (ammoBg < 0.0) {
        // Ammo blocks
        int ammoCount = 7; // out of 10
        float blockW = 0.008;
        for (int i = 0; i < 10; i++) {
            float bx = float(i) * 0.01 - 0.045;
            if (abs(ammoPos.x - bx) < blockW * 0.4 && abs(ammoPos.y) < 0.01) {
                color = i < ammoCount ? vec3(1.0, 0.8, 0.2) : vec3(0.2);
            }
        }
        alpha = 0.85;
    }

    // Score text area (top-center)
    if (uv.y < 0.04 && abs(uv.x - 0.5) < 0.08) {
        float pulse = 0.85 + 0.15 * sin(time * 3.0);
        float stripe = step(0.4, fract(uv.x * 60.0));
        color = vec3(1.0, 0.9, 0.7) * pulse * stripe;
        alpha = 0.75;
    }

    return vec4(color, alpha);
}

void main() {
    vec2 tc = vec2(fragTexCoord.x, 1.0 - fragTexCoord.y);
    vec2 cellCoord = floor(tc * gridSize);
    vec2 uv = cellCoord / gridSize;
    vec2 centered = uv * 2.0 - 1.0;

    // Render 3D scene
    vec3 scene3d = render3D(centered);

    // Overlay 2D HUD
    vec4 hud = renderHUD(uv, scene3d);

    // Composite: HUD over 3D scene
    vec3 final_col = mix(scene3d, hud.rgb, hud.a);

    finalColor = vec4(clamp(final_col, 0.0, 1.0), 1.0);
}
