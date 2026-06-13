// ============================================================
//  AURORA CANADA — v1.0
//  Created by RBambey
//  Aurora system adapted from "Aurora Paint" by Noztol
//  Canada geese, maple leaf flags, northern lake flight world
// ============================================================

// ---- Hash / Noise ----

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i),             hash(i + vec2(1, 0)), u.x),
               mix(hash(i + vec2(0,1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// ---- Magic Box (painted star blotches — from Aurora Paint by Noztol) ----

float magicBox(vec3 p) {
    const int   MB_ITERS = 13;
    const float MB_MAGIC = 0.55;
    p = 1.0 - abs(1.0 - mod(p, 2.0));
    float lastLen = length(p);
    float tot = 0.0;
    for (int i = 0; i < MB_ITERS; i++) {
        p = abs(p) / (lastLen * lastLen) - MB_MAGIC;
        float newLen = length(p);
        tot += abs(newLen - lastLen);
        lastLen = newLen;
    }
    return tot;
}

float magicBox(vec2 uv) {
    const mat3 M = mat3( 0.28862355854826727,  0.6997227302779844,   0.6535170557707412,
                          0.06997493955670424,  0.6653237235314099,  -0.7432683571499161,
                         -0.9548821651308448,   0.26025457467376617,  0.14306504491456504);
    return magicBox(0.5 * M * vec3(uv, 0.0));
}

// ---- Stars ----

vec3 nmzHash33(vec3 q) {
    uvec3 p = uvec3(ivec3(q));
    p = p * uvec3(374761393U, 1103515245U, 668265263U) + p.zxy + p.yzx;
    p = p.yzx * (p.zxy ^ (p >> 3U));
    return vec3(p ^ (p >> 16U)) * (1.0 / vec3(0xffffffffU));
}

vec3 stars(vec3 rd) {
    vec3  c   = vec3(0.0);
    float res = RENDERSIZE.x * 0.7;
    for (float i = 0.0; i < 3.0; i++) {
        vec3  q  = fract(rd * (0.15 * res)) - 0.5;
        vec3  id = floor(rd * (0.15 * res));
        vec2  rn = nmzHash33(id).xy;
        float c2 = (1.0 - smoothstep(0.0, 0.6, length(q)))
                 * step(rn.x, 0.0003 + i * i * 0.0005);
        c  += c2 * (mix(vec3(0.7, 0.85, 1.0), vec3(0.95, 0.92, 0.82), rn.y) * 0.7 + 0.3);
        rd *= 1.4;
    }
    return c * c * 0.55;
}

// ---- Hue rotation (luma-preserving) ----

vec3 hueRotate(vec3 col, float hue) {
    float angle = hue * 2.0 * PI;
    float c = cos(angle), s = sin(angle);
    mat3 M = mat3(
        vec3(0.299+0.701*c+0.168*s, 0.299-0.299*c-0.328*s, 0.299-0.300*c+1.250*s),
        vec3(0.587-0.587*c+0.330*s, 0.587+0.413*c+0.035*s, 0.587-0.588*c-1.050*s),
        vec3(0.114-0.114*c-0.497*s, 0.114-0.114*c+0.292*s, 0.114+0.886*c-0.203*s)
    );
    return max(M * col, vec3(0.0));
}

// ---- Aurora (angular-space ribbon bands) ----

vec3 aurora(vec3 rd, float bassPulse) {
    float el = rd.y;
    if (el < 0.015 || el > 0.98) return vec3(0.0);

    float az = atan(rd.x, rd.z) / PI;  // [-1, 1]
    float t  = TIME * aurora_speed * 0.4;

    // Three warped UV spaces — adapted from Aurora Paint by Noztol
    vec2 aUV1 = vec2(az + sin(az * 2.0 + 1.0 + t) * 0.35 + sin(az * 4.0 - t * 1.5) * 0.10, el);
    vec2 aUV2 = vec2(az + cos(az * 2.5 - 0.5 - t * 0.8) * 0.40 + sin(az * 1.5 + t * 1.2) * 0.20, el);
    vec2 aUV3 = vec2(az + sin(az * 1.8 + 2.0 + t * 0.5) * 0.35, el);

    // Gaussian ribbons at specific sky elevations, textured with noise
    float b1 = exp(-pow((aUV1.y - 0.32) / 0.11, 2.0));
    float b2 = exp(-pow((aUV2.y - 0.47) / 0.14, 2.0));
    float b3 = exp(-pow((aUV3.y - 0.38) / 0.09, 2.0));

    b1 *= noise(aUV1 * vec2(4.0, 22.0)) + noise(aUV1 * vec2(13.0, 7.0)) * 0.38;
    b2 *= noise(aUV2 * vec2(6.0, 18.0)) + noise(aUV2 * vec2(20.0, 5.0)) * 0.28;
    b3 *= noise(aUV3 * vec2(5.0, 28.0)) + noise(aUV3 * vec2(9.0,  11.0)) * 0.42;

    vec3 col  = b3 * vec3(0.10, 0.80, 0.50) * 0.95;
    col      += b1 * vec3(0.30, 0.90, 0.70) * 1.05;
    col      += b2 * vec3(0.00, 0.65, 0.50) * 1.10;
    col      += b1 * vec3(0.55, 1.00, 0.80) * 0.55;  // bright accent

    col = hueRotate(col, aurora_hue);
    col *= smoothstep(0.97, 0.60, el);  // zenith fade
    col *= (1.0 + bassPulse * 0.65);

    return col * aurora_intensity;
}

// ---- Canada Goose SDF ----

float birdSDF(vec2 p, float flap) {
    // Body: slim horizontal oval
    float body = length(p * vec2(1.0, 4.5)) - 0.012;

    // Wings: parabolic arcs sweeping outward, animated by flap
    float flapY = flap * abs(p.x) * 0.38;
    float wing  = max(
        length(vec2(abs(p.x) - 0.003, p.y - flapY) * vec2(0.85, 6.0)) - 0.055,
        abs(p.x) - 0.065
    );

    // Head + neck: small elongated oval at leading edge
    vec2 hp = p - vec2(0.018, 0.0);
    float head = length(hp * vec2(1.0, 2.2)) - 0.009;

    return min(body, min(wing, head));
}

void drawGeese(float az, float el, inout vec3 col) {
    if (el < 0.08) return;

    float formAz = mod(TIME * 0.04, PI * 2.0) - PI;
    float formEl = 0.33;

    // Early cull — skip loop when far from formation elevation
    if (abs(el - formEl) > 0.18) return;

    // V-formation: lead + 3 pairs. V opens behind (−az) and widens in el.
    float OAZ[7];
    float OEL[7];
    OAZ[0] =  0.000; OEL[0] =  0.000;
    OAZ[1] = -0.038; OEL[1] =  0.022;
    OAZ[2] = -0.038; OEL[2] = -0.022;
    OAZ[3] = -0.076; OEL[3] =  0.044;
    OAZ[4] = -0.076; OEL[4] = -0.044;
    OAZ[5] = -0.114; OEL[5] =  0.066;
    OAZ[6] = -0.114; OEL[6] = -0.066;

    for (int i = 0; i < 7; i++) {
        float gAz = formAz + OAZ[i];
        float gEl = formEl + OEL[i];

        float daz = az - gAz;
        // Wrap azimuth discontinuity at ±PI
        daz -= floor(daz / (PI * 2.0) + 0.5) * PI * 2.0;

        // Quick distance cull per bird
        float del = el - gEl;
        if (abs(daz) > 0.10 || abs(del) > 0.10) continue;

        float flapPhase = sin(TIME * 3.5 + float(i) * 0.46);
        float d     = birdSDF(vec2(daz, del), flapPhase);
        float alpha = 1.0 - smoothstep(0.0, 0.003, d);
        col = mix(col, col * 0.04 + vec3(0.008, 0.010, 0.014), alpha);
    }
}

// ---- Canadian Island silhouettes (horizon angular space) ----

float islandH(float az) {
    float h = noise(vec2(az * 2.1, 0.50)) * 0.50
            + noise(vec2(az * 5.3, 1.30)) * 0.25
            + noise(vec2(az * 12.7, 3.10)) * 0.13
            + noise(vec2(az * 28.4, 6.70)) * 0.07;
    h = min(h, 0.80);  // flatten tops (Canadian Shield)
    return max(h - 0.35, 0.0) * (1.0 / 0.45);
}

vec4 horizonIslands(vec3 rd) {
    float el = rd.y;
    if (el > 0.12 || el < -0.04) return vec4(0.0);

    float az = atan(rd.x, rd.z);
    float ih = islandH(az) * 0.085;
    if (el > ih) return vec4(0.0);

    // Darker body with subtle aurora-lit top edge
    float topProx   = clamp(el / max(ih, 0.001), 0.0, 1.0);
    vec3 islandCol  = vec3(0.012, 0.020, 0.038);
    islandCol      += vec3(0.00, 0.09, 0.06) * pow(topProx, 2.5);

    return vec4(islandCol, 1.0);
}

// ---- Maple leaf SDF ----

float mapleleaf(vec2 p) {
    float r = length(p);
    float a = atan(p.y, p.x);
    float lobe = 0.40 + 0.13 * cos(a * 5.0) + 0.055 * cos(a * 10.0) + 0.025 * cos(a * 3.0);
    return r - lobe * 0.60;
}

// ---- Canadian flags (angular-space quads near horizon) ----

void drawFlags(float az, float el, float bassPulse, inout vec3 col) {
    float FAZ[5];
    FAZ[0] = -2.50; FAZ[1] = -1.20; FAZ[2] = 0.20; FAZ[3] = 1.50; FAZ[4] = 2.80;

    const float FLAG_W  = 0.019;
    const float FLAG_H  = 0.013;
    const float FLAG_EL = 0.025;

    for (int i = 0; i < 5; i++) {
        float daz = az - FAZ[i];
        daz -= floor(daz / (PI * 2.0) + 0.5) * PI * 2.0;
        float del = el - FLAG_EL;

        // Bass-reactive warm red glow halo
        float glowDist = length(vec2(daz * 1.4, del));
        col += vec3(1.0, 0.08, 0.04) * flag_glow * bassPulse * exp(-glowDist * 70.0) * 0.65;

        // Flag face (only draw if close enough)
        if (abs(daz) < FLAG_W && abs(del) < FLAG_H) {
            vec2 uv = vec2((daz / FLAG_W) * 0.5 + 0.5,
                           (del / FLAG_H) * 0.5 + 0.5);

            vec3 flagCol;
            if (uv.x < 0.25 || uv.x > 0.75) {
                flagCol = vec3(0.84, 0.04, 0.04);  // red stripes
            } else {
                // White center with maple leaf
                vec2 leafUV = (uv - vec2(0.5, 0.5)) * 2.0;
                flagCol = (mapleleaf(leafUV) < 0.0)
                    ? vec3(0.84, 0.04, 0.04)
                    : vec3(0.95, 0.95, 0.95);
            }

            float brightness = 1.0 + bassPulse * flag_glow * 0.65;
            // Soft edge blend
            float edgeBlend = smoothstep(FLAG_W, FLAG_W * 0.85, abs(daz))
                            * smoothstep(FLAG_H, FLAG_H * 0.85, abs(del));
            col = mix(col, flagCol * brightness, edgeBlend);
        }
    }
}

// ---- Sky background gradient ----

vec3 skyBg(float el) {
    return mix(vec3(0.012, 0.022, 0.055),
               vec3(0.030, 0.065, 0.130),
               smoothstep(-0.12, 0.55, el));
}

// ---- Water ripple normal ----

vec3 waterNormal(vec2 pos) {
    float e = 0.08;
    float h0 = noise(pos * 2.8 - TIME * 0.70) * 0.5 + noise(pos * 6.3 + TIME * 0.45) * 0.25;
    float hx = noise((pos + vec2(e, 0)) * 2.8 - TIME * 0.70) * 0.5
             + noise((pos + vec2(e, 0)) * 6.3 + TIME * 0.45) * 0.25;
    float hz = noise((pos + vec2(0, e)) * 2.8 - TIME * 0.70) * 0.5
             + noise((pos + vec2(0, e)) * 6.3 + TIME * 0.45) * 0.25;
    return normalize(vec3((h0 - hx) * wave_height * 6.0, e, (h0 - hz) * wave_height * 6.0));
}

// ================================================================
vec4 renderMain() {

    // --- Camera ---
    vec3 ro     = vec3(cam_x, cam_y, cam_z);
    vec3 cRight = vec3(cam_rx, cam_ry, cam_rz);
    vec3 cUp    = vec3(cam_ux, cam_uy, cam_uz);
    vec3 cFwd   = vec3(cam_fx, cam_fy, cam_fz);
    vec2 sc     = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd     = normalize(cFwd + cRight * sc.x + cUp * sc.y);

    // --- Audio ---
    float bassRaw   = clamp(syn_BassLevel, 0.0, 1.0);
    float bassPulse = pow(bassRaw, 1.5) * bass_reactivity;

    // --- Angular coords ---
    float el = rd.y;
    float az = atan(rd.x, rd.z);

    // --- Water intersection (flat plane at y = 0) ---
    bool  waterHit = (rd.y < -0.001) && (ro.y > 0.0);
    float waterT   = waterHit ? (-ro.y / rd.y) : (draw_distance + 1.0);
    waterHit = waterHit && (waterT < draw_distance);

    vec3 col;

    if (waterHit) {
        // ---- Water path ----
        vec3 wp = ro + rd * waterT;
        vec3 n  = waterNormal(wp.xz * 0.015);

        float fresnel = pow(clamp(1.0 - dot(n, -rd), 0.0, 1.0), 3.0) * 0.65;

        // Reflection ray into sky
        vec3 reflRd  = reflect(rd, n);
        vec3 rAur    = aurora(reflRd, bassPulse);
        vec3 rStars  = stars(reflRd) * max(reflRd.y, 0.0);
        vec3 rSky    = skyBg(reflRd.y);
        float rAurB  = dot(rAur, vec3(0.3, 0.6, 0.1));
        vec3 reflCol = rSky + rStars * (1.0 - clamp(rAurB * 2.0, 0.0, 1.0)) + rAur;

        // Island reflections
        vec4 rIsland = horizonIslands(reflRd);
        if (rIsland.a > 0.5) reflCol = rIsland.rgb;

        vec3 waterBase = vec3(0.012, 0.042, 0.068);
        col = mix(waterBase, reflCol, fresnel * water_clarity);

        // Dark-water depth tint toward horizon
        col = mix(col, vec3(0.004, 0.012, 0.022),
                  smoothstep(draw_distance * 0.4, draw_distance, waterT));

    } else {
        // ---- Sky path ----
        col = skyBg(el);

        // Stars — dim where aurora is bright
        vec3 aurCol  = aurora(rd, bassPulse);
        float aurBrt = dot(aurCol, vec3(0.3, 0.6, 0.1));
        col += stars(rd) * (1.0 - clamp(aurBrt * 2.2, 0.0, 1.0));

        // Aurora ribbons
        col += aurCol;

        // Magic-box painted star blotches (from Aurora Paint)
        float az01   = az / PI;
        float blotch = smoothstep(12.0, 25.0, magicBox((vec2(az01, el) + 3.5) * 5.5));
        blotch = pow(blotch, 1.6);
        col += vec3(0.45, 0.75, 0.90) * blotch * 0.35
             * (0.5 + 0.5 * sin(TIME * 1.3 + az01 * 3.5));

        // Island silhouettes at horizon
        vec4 islands = horizonIslands(rd);
        if (islands.a > 0.5) col = islands.rgb;

        // Canadian flags on islands
        drawFlags(az, el, bassPulse, col);

        // Canada geese in V-formation
        drawGeese(az, el, col);
    }

    // --- Tonemap + gamma ---
    col = pow(max(col, vec3(0.0)), vec3(0.93, 0.97, 1.01));
    col = mix(col, smoothstep(0.0, 1.0, col), 0.18);

    // --- Vignette ---
    vec2 q = _uv;
    col *= pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.10) * 0.9 + 0.1;

    // --- Motion blur ---
    vec4 past = texture(syn_FinalPass, _uv);
    col = mix(col, past.rgb, motion_blur);

    return vec4(col, 1.0);
}
