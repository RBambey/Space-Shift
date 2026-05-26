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

// ---- Giant crater profile — broad rim, shallow flat floor (impact basin style) ----
float giantCraterProfile(float r) {
    if (r > 2.0) return 0.0;
    float rim    = exp(-pow((r - 1.0) * 2.2, 2.0)) * 0.35;
    float floor_ = -exp(-r * r * 0.5) * 0.65;
    float fade   = 1.0 - smoothstep(1.8, 2.2, r);
    return (rim + floor_) * fade;
}

// ---- Moon surface height at world XZ ----
float moonHeight(vec2 xz) {
    float h = 0.0;

    // Giant craters (radius 60–130 units, grid 400) — rare landmark basins
    vec2 gGrid = floor(xz / 400.0);
    for (int di = -1; di <= 1; di++) {
        for (int dj = -1; dj <= 1; dj++) {
            vec2  cell   = gGrid + vec2(float(di), float(dj));
            float r0     = hash(cell + vec2(7.1, 83.3));
            if (r0 > 0.12) continue;              // ~12% — very rare
            float r1     = hash(cell + vec2(3.9, 21.7));
            float r2     = hash(cell + vec2(61.3, 44.1));
            float radius  = 60.0 + r1 * 70.0;
            vec2  center  = (cell + 0.5) * 400.0 + (vec2(r1, r2) - 0.5) * 280.0;
            float dist    = length(xz - center) / radius;
            h += giantCraterProfile(dist) * radius * 0.10;
        }
    }

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

    // Base terrain — macro hills down to surface texture (all scaled by terrain_roughness)
    h += (noise(xz * 0.003) * 5.0      // ~330-unit rolling hills
        + noise(xz * 0.008) * 2.5      // ~125-unit medium hills
        + noise(xz * 0.018) * 1.0      // coarse undulation
        + noise(xz * 0.055) * 0.30     // medium detail
        + noise(xz * 0.13)  * 0.12)    // fine surface texture
        * terrain_roughness;

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

// ---- Horizon mountain silhouette (angular space — never reachable) ----
float moonMtnH(float az) {
    float h = noise(vec2(az * 3.8,  0.55)) * 0.50
            + noise(vec2(az * 8.1,  2.33)) * 0.28
            + noise(vec2(az * 17.5, 5.71)) * 0.15
            + noise(vec2(az * 36.2, 9.14)) * 0.07;
    return max(h - 0.42, 0.0) * (1.0 / 0.58);
}

vec4 horizonMountains(vec3 rd, vec3 sunDir) {
    // Anchor mountains to the terrain horizon so the gap closes at any altitude
    float horizonEl = -cam_y / draw_distance;
    float mtnMax    = 0.10;

    float el = rd.y;
    if (el > horizonEl + mtnMax + 0.04) return vec4(0.0);
    if (el < horizonEl - 0.03)          return vec4(0.0);

    float az = atan(rd.x, rd.z);
    float mh = horizonEl + moonMtnH(az) * mtnMax;  // peak angle relative to terrain horizon
    if (el > mh) return vec4(0.0);

    float eps = 0.006;
    float dh  = (moonMtnH(az + eps) - moonMtnH(az - eps)) * mtnMax;
    vec3  n   = normalize(vec3(-dh * cos(az), eps * 4.0, -dh * sin(az)));

    float diff  = max(dot(n, sunDir), 0.0);
    float elT   = clamp((el - horizonEl) / max(mh - horizonEl, 0.001), 0.0, 1.0);
    float shade = 0.12 + diff * 0.55 + smoothstep(0.0, 0.7, elT) * 0.10;

    vec3 mtnCol = mix(vec3(0.08, 0.09, 0.11), vec3(shade * 0.82, shade * 0.84, shade * 0.88), shade);
    return vec4(mtnCol, 1.0);
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

    // --- Earth (replaces sun disc) ---
    float earthDot = dot(rd, sunDir);
    float earthAngR = 0.070;   // ~4° angular radius

    // Wide earthshine glow — pulses with bass
    float eGlow = pow(max(earthDot, 0.0), 48.0)
                * (1.0 + syn_BassLevel * bass_reactivity * 2.5) * 0.35;
    col += vec3(0.20, 0.48, 0.90) * eGlow;

    // Tangent frame for disc UV (guard against vertical sunDir)
    vec3 eRight = abs(sunDir.y) < 0.999
                  ? normalize(cross(sunDir, vec3(0.0, 1.0, 0.0)))
                  : vec3(1.0, 0.0, 0.0);
    vec3 eUp    = normalize(cross(eRight, sunDir));
    vec3 rdPerp = rd - sunDir * earthDot;
    vec2 euv    = vec2(dot(rdPerp, eRight), dot(rdPerp, eUp)) / earthAngR;
    float r2    = dot(euv, euv);

    if (r2 < 1.12) {
        if (r2 >= 1.0) {
            // Atmospheric rim
            col += vec3(0.25, 0.55, 1.00) * exp(-10.0 * (sqrt(r2) - 1.0)) * 0.9;
        } else {
            // Earth surface — ocean / land / cloud layers
            float land  = smoothstep(0.44, 0.56,
                            noise(euv * 3.1 + 1.7) * 0.55
                          + noise(euv * 7.3)        * 0.30
                          + noise(euv * 14.7)       * 0.15);
            float cloud = smoothstep(0.52, 0.62,
                            noise(euv * 4.8 + vec2(0.3, 0.8)) * 0.50
                          + noise(euv * 9.5)                   * 0.35
                          + noise(euv * 21.0)                  * 0.15);
            float limb  = 1.0 - sqrt(max(1.0 - r2, 0.0)) * 0.35;

            vec3 ocean  = vec3(0.04, 0.16, 0.42);
            vec3 terra  = mix(vec3(0.06, 0.24, 0.06),
                              vec3(0.30, 0.22, 0.11),
                              noise(euv * 5.7 + 0.9));
            vec3 earthS = mix(ocean, terra, land);
            earthS      = mix(earthS, vec3(0.88, 0.92, 1.00), cloud);
            earthS     *= (1.0 - limb * 0.35);

            float pulse = 1.0 + syn_BassLevel * bass_reactivity * 1.5;
            col = earthS * pulse;
        }
    }

    // Horizon mountains (angular space — fixed, never reachable)
    vec4 mtn = horizonMountains(rd, sunDir);
    if (mtn.a > 0.5) return mtn.rgb;

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

    // --- Surface albedo — dark mare (0.10) to bright highland (0.75) ---
    float alb_mare  = noise(p.xz * 0.012);              // large highland/mare patches
    float alb_hills = noise(p.xz * 0.004) * 0.5 + 0.5; // hill-scale variation — bright hilltops
    float alb_mid   = noise(p.xz * 0.08)  * 0.08;
    float alb_fine  = noise(p.xz * 0.90)  * 0.03;
    float alb_micro = noise(p.xz * 4.0)   * 0.02;
    // Height-correlated: crater floors darker, rolling hills brighter
    float heightAlb = smoothstep(-3.0, 5.0, p.y) * 0.14;
    float albedo    = clamp(0.18 + alb_mare * 0.38
                                 + alb_hills * 0.08
                                 + alb_mid + alb_fine + alb_micro
                                 + heightAlb,
                            0.10, 0.75);

    // Subtle warm/cool patch variation layered on top of moon_tint knob
    float warmPatch = noise(p.xz * 0.035);
    vec3 tint = mix(vec3(1.00, 0.97, 0.93),   // 0 = warm dusty tan
                     vec3(0.93, 0.96, 1.02),   // 1 = cool earthshine blue
                     moon_tint);
    tint = mix(tint, tint + vec3(0.05, 0.03, -0.01) * warmPatch, 0.35);

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

    // --- Blend horizon mountains over far terrain to close sky/terrain gap ---
    float mtnFade = smoothstep(draw_distance * 0.80, draw_distance * 0.97, t);
    if (mtnFade > 0.001) {
        vec4 mtn = horizonMountains(rd, sunDir);
        if (mtn.a > 0.5) col = mix(col, mtn.rgb, mtnFade);
    }

    // --- Gamma ---
    col = pow(max(col, vec3(0.0)), vec3(0.78));

    return vec4(col, 1.0);
}
