// ============================================================
//  MOON — v1.0
//  Created by RBambey
//  Flying mechanics from Ocean Sunset by RBambey
//  Procedural crater terrain — large / medium / small scales
// ============================================================

const int NUM_STEPS = 8;

// ---- Hash ----
float hash(vec2 p) {
    float h = dot(p, vec2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// ---- Value noise ----
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i),                    hash(i + vec2(1.0, 0.0)), u.x),
        mix(hash(i + vec2(0.0, 1.0)),   hash(i + vec2(1.0, 1.0)), u.x),
        u.y);
}

// ---- Crater profile (r = dist / radius) ----
// Floor depression at r<0.7, raised rim at r≈1, fades to 0 at r>2.2
float craterProfile(float r) {
    if (r > 2.0) return 0.0;
    float rim    = exp(-pow((r - 1.0) * 3.5, 2.0)) * 0.5;
    float floor_ = -exp(-r * r * 1.8) * 1.2;
    float fade   = 1.0 - smoothstep(1.8, 2.2, r);
    return (rim + floor_) * fade;
}

// ---- Moon surface height at world XZ ----
float moonHeight(vec2 xz) {
    float h = 0.0;

    // Large craters (radius 15–40 units, grid 120)
    vec2 lGrid = floor(xz / 120.0);
    for (int di = -1; di <= 1; di++) {
        for (int dj = -1; dj <= 1; dj++) {
            vec2 cell   = lGrid + vec2(float(di), float(dj));
            float r0    = hash(cell + vec2(17.3, 41.7));
            if (r0 > 0.45) continue;
            float r1    = hash(cell + vec2(2.1,  8.9));
            float r2    = hash(cell + vec2(5.7,  3.3));
            float radius = 15.0 + r1 * 25.0;
            vec2  center = (cell + 0.5) * 120.0 + (vec2(r1, r2) - 0.5) * 80.0;
            float dist   = length(xz - center) / radius;
            h += craterProfile(dist) * radius * 0.15;
        }
    }

    // Medium craters (radius 3–12 units, grid 30)
    vec2 mGrid = floor(xz / 30.0);
    for (int di = -1; di <= 1; di++) {
        for (int dj = -1; dj <= 1; dj++) {
            vec2 cell    = mGrid + vec2(float(di), float(dj));
            float r0     = hash(cell + vec2(53.1, 97.3));
            if (r0 > 0.55) continue;
            float r1     = hash(cell + vec2(11.3, 73.9));
            float r2     = hash(cell + vec2(29.7,  5.1));
            float radius  = 3.0 + r1 * 9.0;
            vec2  center  = (cell + 0.5) * 30.0 + (vec2(r1, r2) - 0.5) * 24.0;
            float dist    = length(xz - center) / radius;
            h += craterProfile(dist) * radius * 0.17;
        }
    }

    // Small craters (radius 0.3–2.5 units, grid 7) — LOD: skip beyond 50 units
    if (length(xz - vec2(cam_x, cam_z)) < 70.0) {
        vec2 sGrid = floor(xz / 7.0);
        for (int di = -1; di <= 1; di++) {
            for (int dj = -1; dj <= 1; dj++) {
                vec2 cell    = sGrid + vec2(float(di), float(dj));
                float r0     = hash(cell + vec2(73.1, 19.7));
                if (r0 > 0.55) continue;
                float r1     = hash(cell + vec2(37.1, 61.3));
                float r2     = hash(cell + vec2(83.7,  7.9));
                float radius  = 0.3 + r1 * 2.2;
                vec2  center  = (cell + 0.5) * 7.0 + (vec2(r1, r2) - 0.5) * 5.5;
                float dist    = length(xz - center) / radius;
                h += craterProfile(dist) * radius * 0.20;
            }
        }
    }

    // Base terrain undulation (scaled by terrain_roughness)
    h += (noise(xz * 0.018) * 1.0
        + noise(xz * 0.055) * 0.3) * terrain_roughness;

    return h;
}

// ---- Height-above-surface SDF ----
float map(vec3 p) {
    return p.y - moonHeight(p.xz);
}

// ---- Surface normal via finite differences ----
vec3 getNormal(vec3 p, float eps) {
    float h0 = moonHeight(p.xz);
    float hx = moonHeight(p.xz + vec2(eps, 0.0));
    float hz = moonHeight(p.xz + vec2(0.0, eps));
    return normalize(vec3(h0 - hx, eps, h0 - hz));
}

// ---- Ray-terrain intersection (regula-falsi / secant) ----
float heightMapTracing(vec3 ori, vec3 dir, out vec3 p) {
    float tm   = 0.0;
    float tx   = draw_distance;
    float hx   = map(ori + dir * tx);
    if (hx > 0.0) { p = ori + dir * tx; return tx; }
    float hm   = map(ori);
    float tmid = 0.0;
    for (int i = 0; i < NUM_STEPS; i++) {
        tmid = mix(tm, tx, hm / (hm - hx));
        p    = ori + dir * tmid;
        float hmid = map(p);
        if (hmid < 0.0) { tx = tmid; hx = hmid; }
        else             { tm = tmid; hm = hmid; }
    }
    return tmid;
}

// ---- Star field (3 density layers) ----
float starLayer(vec3 rd, float scale, vec2 seed) {
    vec2 uv2 = vec2(atan(rd.x, rd.z), asin(clamp(rd.y, -1.0, 1.0))) * scale / PI;
    vec2 id  = floor(uv2);
    float h0 = hash(id + seed);
    float h1 = hash(id + seed + vec2(3.7, 1.3));
    float h2 = hash(id + seed + vec2(7.1, 4.9));
    vec2  off = (vec2(h0, h1) - 0.5) * 0.5;
    vec2  pos = fract(uv2) - 0.5 - off;
    return step(0.90, h2) * exp(-dot(pos, pos) * 60.0) * (0.6 + h0 * 0.4);
}

vec3 skyColor(vec3 rd, vec3 sunDir, vec3 sunCol) {
    vec3 col = vec3(0.0);

    // Stars — three overlapping layers for natural density variation
    col += starLayer(rd,       70.0, vec2( 0.0,  0.0)) * vec3(0.85, 0.90, 1.00);
    col += starLayer(rd.yzx,  120.0, vec2(11.3, 17.7)) * vec3(1.00, 0.95, 0.85) * 0.8;
    col += starLayer(rd.zxy,  200.0, vec2(37.9,  5.1)) * vec3(0.80, 0.88, 1.00) * 0.5;

    // Sun disc + corona glow
    float sunDot  = dot(rd, sunDir);
    float sunDisc = smoothstep(0.9997, 1.0, sunDot);
    float sunGlow = pow(max(sunDot, 0.0), 384.0) * 0.4;
    col += sunCol * sunDisc * 10.0 + sunCol * sunGlow;

    return col;
}

// ================================================================
vec4 renderMain() {

    // --- Camera (basis vectors from script.js) ---
    vec3 ro     = vec3(cam_x, cam_y, cam_z);
    vec3 cRight = vec3(cam_rx, cam_ry, cam_rz);
    vec3 cUp    = vec3(cam_ux, cam_uy, cam_uz);
    vec3 cFwd   = vec3(cam_fx, cam_fy, cam_fz);
    vec2 uv     = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd     = normalize(cFwd + cRight * uv.x + cUp * uv.y);

    // --- Sun direction ---
    float sunAz  = sun_angle * PI * 2.0;
    float sinEl  = 0.15 + sun_elevation * 0.65;   // always keeps sun off horizon
    float cosEl  = sqrt(max(1.0 - sinEl * sinEl, 0.0));
    vec3  sunDir = normalize(vec3(cos(sunAz) * cosEl, sinEl, sin(sunAz) * cosEl));
    vec3  sunCol = vec3(1.00, 0.98, 0.95);

    // --- Sky layer ---
    vec3 skyCol = skyColor(rd, sunDir, sunCol);

    // Early exit for upward-pointing rays
    if (rd.y >= -0.001) {
        return vec4(skyCol, 1.0);
    }

    // --- Terrain trace ---
    vec3  p;
    float t = heightMapTracing(ro, rd, p);

    // Ray missed terrain — show sky
    if (t >= draw_distance - 0.5) {
        return vec4(skyCol, 1.0);
    }

    // --- Surface normal ---
    float epsNrm = max(dot(p - ro, p - ro) * (0.08 / RENDERSIZE.x), 0.02);
    vec3  n      = getNormal(p, epsNrm);

    // --- Surface albedo (grey regolith with subtle patchwork) ---
    float albedo = 0.42
                 + noise(p.xz * 0.08) * 0.06
                 + noise(p.xz * 0.90) * 0.02;
    vec3 tint    = mix(vec3(1.00, 0.97, 0.93),   // 0 = warm dusty tan
                        vec3(0.93, 0.96, 1.02),   // 1 = cool earthshine blue
                        moon_tint);
    vec3 surface = vec3(albedo) * tint;

    // --- Lighting — no atmosphere, harsh directional sun ---
    float diff     = max(dot(n, sunDir), 0.0);
    float selfShad = smoothstep(-0.05, 0.25, dot(n, sunDir));

    // Earthshine ambient + bass pulse
    float bassAmb  = syn_BassLevel * bass_reactivity * 0.08;
    float ambient  = 0.04 + bassAmb;

    vec3 col = surface * (diff * selfShad + ambient);

    // Dust retroreflection (regolith opposition surge)
    float spec = pow(max(dot(reflect(-sunDir, n), -rd), 0.0), 10.0) * 0.06;
    col += sunCol * spec;

    // Bass hit briefly brightens rim-facing faces
    float rimFace = max(dot(n, sunDir) - 0.3, 0.0);
    col += surface * rimFace * syn_BassHits * bass_reactivity * 0.12;

    // --- Horizon fade to space ---
    float fog = exp(-t * (2.0 / draw_distance));
    col = mix(skyCol * 0.01, col, fog);

    // --- Gamma ---
    col = pow(max(col, vec3(0.0)), vec3(0.78));

    return vec4(col, 1.0);
}
