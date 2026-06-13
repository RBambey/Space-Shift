// ============================================================
//  AURORA CANADA — v2.0
//  Created by RBambey
//  Aurora system adapted from "Aurora Paint" by Noztol
//  Terrain inspired by "Sirenian Dawn" by nimitz
//  Snowy Canadian mountains, geese, 3D maple leaf flags
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

// Gradient noise with analytic derivatives (for terrain FBM)
vec3 noised(vec2 x) {
    vec2 i  = floor(x), f = fract(x);
    vec2 u  = f * f * (3.0 - 2.0 * f);
    vec2 du = 6.0 * f * (1.0 - f);
    float a = hash(i),             b = hash(i + vec2(1, 0));
    float c = hash(i + vec2(0,1)), d = hash(i + vec2(1, 1));
    float v = a + (b-a)*u.x + (c-a)*u.y + (a-b-c+d)*u.x*u.y;
    return vec3(v, du * vec2((b-a) + (a-b-c+d)*u.y, (c-a) + (a-b-c+d)*u.x));
}

// ---- Terrain — derivative-warped FBM ----

const mat2 m2 = mat2(0.80, 0.60, -0.60, 0.80);

float terrain(vec2 p) {
    float rz = 0., z = 1.;
    vec2  d  = vec2(0.0);
    float scl = 2.95, zscl = -0.4, zz = 5.;
    for (int i = 0; i < 4; i++) {
        vec3 n = noised(p);
        d  += pow(abs(n.yz), vec2(zz));
        d  -= smoothstep(-0.5, 1.5, n.yz);
        zz -= 1.0;
        rz += z * n.x / (dot(d, d) + 0.85);
        z   *= zscl;
        zscl *= 0.8;
        p    = m2 * p * scl;
    }
    rz /= smoothstep(1.5, -0.5, rz) + 0.75;
    return rz;
}

float map(vec3 p) {
    return p.y - terrain(p.xz * 0.05 / terrain_scale) * 5.5 - 1.0;
}

// ---- Ray-terrain intersection (forward scan + bisect) ----

float heightMapTracing(vec3 ro, vec3 rd, out vec3 p) {
    float t = 0.2, stepSize = 0.2;
    for (int i = 0; i < 60; i++) {
        p = ro + rd * t;
        float h = map(p);
        if (h < 0.0) {
            float tLo = t - stepSize, tHi = t;
            for (int j = 0; j < 8; j++) {
                float tMid = (tLo + tHi) * 0.5;
                if (map(ro + rd * tMid) < 0.0) tHi = tMid;
                else                            tLo = tMid;
            }
            t = (tLo + tHi) * 0.5;
            p = ro + rd * t;
            return t;
        }
        stepSize = max(1.0, h * 0.6);
        t += stepSize;
        if (t > draw_distance) break;
    }
    return draw_distance + 1.0;
}

// ---- Surface normal via finite differences ----

vec3 getNormal(vec3 p, float eps) {
    vec2 e = vec2(eps, 0.0);
    return normalize(vec3(map(p - e.xyy) - map(p + e.xyy),
                          2.0 * eps,
                          map(p - e.yyx) - map(p + e.yyx)));
}

// ---- Bump map (surface micro-detail) ----

float bnoise(vec2 p) {
    float z = 0.5, rz = 0.;
    for (int i = 0; i < 3; i++) {
        rz += (sin(noise(p) * 5.0) * 0.5 + 0.5) * z;
        z  *= 0.5;
        p  *= 2.0;
    }
    return rz;
}

vec3 bump(vec3 p, vec3 n, float ds) {
    vec2  e  = vec2(0.005 * ds, 0.0);
    float n0 = bnoise(p.zx);
    vec3  d  = vec3(bnoise(p.zx + e.xy) - n0, 1.0, bnoise(p.zx + e.yx) - n0) / e.x * 0.022;
    d -= n * dot(n, d);
    return normalize(n - d);
}

// ---- Surface curvature (drives color contrast) ----

float curv(vec3 p, float w) {
    vec2 e = vec2(-1.0, 1.0) * w;
    return 0.15 / e.y * (map(p + e.yxx) + map(p + e.xxy)
                       + map(p + e.xyx) + map(p + e.yyy) - 4.0 * map(p));
}

// ---- Magic Box (painted star blotches) ----

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

    float az = atan(rd.x, rd.z) / PI;
    float t  = TIME * aurora_speed * 0.4;

    vec2 aUV1 = vec2(az + sin(az * 2.0 + 1.0 + t) * 0.35 + sin(az * 4.0 - t * 1.5) * 0.10, el);
    vec2 aUV2 = vec2(az + cos(az * 2.5 - 0.5 - t * 0.8) * 0.40 + sin(az * 1.5 + t * 1.2) * 0.20, el);
    vec2 aUV3 = vec2(az + sin(az * 1.8 + 2.0 + t * 0.5) * 0.35, el);

    float b1 = exp(-pow((aUV1.y - 0.32) / 0.11, 2.0));
    float b2 = exp(-pow((aUV2.y - 0.47) / 0.14, 2.0));
    float b3 = exp(-pow((aUV3.y - 0.38) / 0.09, 2.0));

    b1 *= noise(aUV1 * vec2(4.0, 22.0)) + noise(aUV1 * vec2(13.0, 7.0)) * 0.38;
    b2 *= noise(aUV2 * vec2(6.0, 18.0)) + noise(aUV2 * vec2(20.0, 5.0)) * 0.28;
    b3 *= noise(aUV3 * vec2(5.0, 28.0)) + noise(aUV3 * vec2(9.0, 11.0)) * 0.42;

    vec3 col  = b3 * vec3(0.10, 0.80, 0.50) * 0.95;
    col      += b1 * vec3(0.30, 0.90, 0.70) * 1.05;
    col      += b2 * vec3(0.00, 0.65, 0.50) * 1.10;
    col      += b1 * vec3(0.55, 1.00, 0.80) * 0.55;

    col = hueRotate(col, aurora_hue);
    col *= smoothstep(0.97, 0.60, el);
    col *= (1.0 + bassPulse * 0.65);

    return col * aurora_intensity;
}

// ---- Canada Goose SDF ----

float birdSDF(vec2 p, float flap) {
    float body = length(p * vec2(1.0, 4.5)) - 0.012;
    float flapY = flap * abs(p.x) * 0.38;
    float wing  = max(
        length(vec2(abs(p.x) - 0.003, p.y - flapY) * vec2(0.85, 6.0)) - 0.055,
        abs(p.x) - 0.065
    );
    vec2 hp = p - vec2(0.018, 0.0);
    float head = length(hp * vec2(1.0, 2.2)) - 0.009;
    return min(body, min(wing, head));
}

void drawGeese(float az, float el, inout vec3 col) {
    if (el < 0.08) return;

    float formAz = mod(TIME * 0.04, PI * 2.0) - PI;
    float formEl = 0.33;
    if (abs(el - formEl) > 0.18) return;

    float OAZ[7]; float OEL[7];
    OAZ[0] =  0.000; OEL[0] =  0.000;
    OAZ[1] = -0.038; OEL[1] =  0.022;
    OAZ[2] = -0.038; OEL[2] = -0.022;
    OAZ[3] = -0.076; OEL[3] =  0.044;
    OAZ[4] = -0.076; OEL[4] = -0.044;
    OAZ[5] = -0.114; OEL[5] =  0.066;
    OAZ[6] = -0.114; OEL[6] = -0.066;

    for (int i = 0; i < 7; i++) {
        float daz = az - (formAz + OAZ[i]);
        daz -= floor(daz / (PI * 2.0) + 0.5) * PI * 2.0;
        float del = el - (formEl + OEL[i]);
        if (abs(daz) > 0.10 || abs(del) > 0.10) continue;
        float d = birdSDF(vec2(daz, del), sin(TIME * 3.5 + float(i) * 0.46));
        col = mix(col, col * 0.04 + vec3(0.008, 0.010, 0.014),
                  1.0 - smoothstep(0.0, 0.003, d));
    }
}

// ---- Maple leaf SDF ----

float mapleleaf(vec2 p) {
    float r = length(p);
    float a = atan(p.y, p.x);
    return r - (0.40 + 0.13 * cos(a * 5.0) + 0.055 * cos(a * 10.0) + 0.025 * cos(a * 3.0)) * 0.60;
}

// ---- Flag ray intersections ----

// Vertical cylinder (pole) intersection — axis along Y
float rayCylinder(vec3 ro, vec3 rd, vec3 pa, float r, float len) {
    vec2 oc = ro.xz - pa.xz;
    float a = dot(rd.xz, rd.xz);
    if (a < 0.0001) return -1.0;
    float b = dot(oc, rd.xz);
    float c = dot(oc, oc) - r * r;
    float h = b * b - a * c;
    if (h < 0.0) return -1.0;
    float t = (-b - sqrt(h)) / a;
    if (t < 0.05) return -1.0;
    float hitY = ro.y + rd.y * t;
    if (hitY < pa.y || hitY > pa.y + len) return -1.0;
    return t;
}

// Flat quad (flag face) — lies in the Z plane at orig.z, extends +X by fw and -Y by fh
float rayQuadFlag(vec3 ro, vec3 rd, vec3 orig, float fw, float fh, out vec2 uv) {
    float denom = rd.z;
    if (abs(denom) < 0.0001) { uv = vec2(0.0); return -1.0; }
    float t = (orig.z - ro.z) / denom;
    if (t < 0.05) { uv = vec2(0.0); return -1.0; }
    vec3 hit = ro + rd * t;
    uv.x = (hit.x - orig.x) / fw;
    uv.y = (orig.y - hit.y) / fh;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return -1.0;
    return t;
}

// ---- Flag coloring ----

vec3 flagColor(vec2 uv, vec3 lgt, float bassPulse) {
    // Canada flag: red | white+leaf | red (1:2:1 proportions)
    bool isRed = (uv.x < 0.25 || uv.x > 0.75);
    bool inLeaf = false;
    if (!isRed) {
        vec2 leafUV = (uv - vec2(0.5, 0.5)) * 2.0;
        inLeaf = mapleleaf(leafUV) < 0.0;
    }

    // Wind wave: perturb shading normal for waving look
    float wave = sin(uv.x * PI * 2.5 + TIME * 4.0) * uv.x * 0.35;
    vec3 faceN = normalize(vec3(0.0, wave, 1.0));
    float fdif = clamp(dot(faceN, lgt), 0.0, 1.0) * 0.5 + 0.55;

    vec3 col;
    if (isRed || inLeaf) {
        vec3 red = vec3(0.84, 0.04, 0.04);
        // Bass-reactive glow on red
        red += vec3(1.0, 0.12, 0.05) * bassPulse * flag_glow * 1.6;
        col = red * fdif;
    } else {
        // White — tinted by aurora light from above
        col = vec3(0.94, 0.94, 0.96) * fdif;
    }
    return col;
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

    // --- Moon direction ---
    float moonAz = moon_angle * 2.0 * PI;
    vec3  lgt    = normalize(vec3(cos(moonAz) * 0.97, 0.20, sin(moonAz) * 0.97));

    // --- Sky (aurora + stars + magic-box blotches) ---
    float el  = rd.y;
    float az  = atan(rd.x, rd.z);
    float az01 = az / PI;

    vec3 aurCol  = aurora(rd, bassPulse);
    float aurBrt = dot(aurCol, vec3(0.3, 0.6, 0.1));
    vec3 stCol   = stars(rd) * (1.0 - clamp(aurBrt * 2.2, 0.0, 1.0));
    float blotch = smoothstep(12.0, 25.0, magicBox((vec2(az01, el) + 3.5) * 5.5));
    stCol += vec3(0.45, 0.75, 0.90) * pow(blotch, 1.6) * 0.35
           * (0.5 + 0.5 * sin(TIME * 1.3 + az01 * 3.5));
    vec3 skyBase = mix(vec3(0.010, 0.018, 0.050), vec3(0.025, 0.055, 0.120),
                       smoothstep(-0.15, 0.55, el));
    vec3 bg = skyBase + stCol + aurCol;

    // Geese in sky
    vec3 geeseBg = bg;
    drawGeese(az, el, geeseBg);

    // --- Flag world positions (x, z) ---
    const int NUM_FLAGS = 5;
    float FX[5]; float FZ[5];
    FX[0] = -28.0; FZ[0] =  65.0;
    FX[1] =  42.0; FZ[1] =  95.0;
    FX[2] = -12.0; FZ[2] = 145.0;
    FX[3] =  58.0; FZ[3] = 175.0;
    FX[4] = -38.0; FZ[4] = 215.0;

    const float POLE_H = 4.0;
    const float FLAG_W = 2.4;
    const float FLAG_H = 1.2;
    const float POLE_R = 0.07;

    // --- Flag ray intersection ---
    float bestFlagT  = draw_distance;
    int   bestFlagI  = -1;
    vec2  bestFlagUV = vec2(0.0);
    bool  isFlagPole = false;

    for (int i = 0; i < NUM_FLAGS; i++) {
        float fy = terrain(vec2(FX[i], FZ[i]) * 0.05 / terrain_scale) * 5.5 + 1.0;
        vec3 base = vec3(FX[i], fy, FZ[i]);

        float tp = rayCylinder(ro, rd, base, POLE_R, POLE_H);
        if (tp > 0.0 && tp < bestFlagT) {
            bestFlagT = tp; bestFlagI = i; isFlagPole = true;
        }

        vec2 fuv;
        float tf = rayQuadFlag(ro, rd, base + vec3(0.0, POLE_H, 0.0), FLAG_W, FLAG_H, fuv);
        if (tf > 0.0 && tf < bestFlagT) {
            bestFlagT = tf; bestFlagI = i; bestFlagUV = fuv; isFlagPole = false;
        }
    }

    // --- Terrain raymarching ---
    vec3  p;
    float t = heightMapTracing(ro, rd, p);

    vec3 col;

    if (t < draw_distance) {
        // ---- Terrain surface ----
        float eps  = max(t * 0.002, 0.02);
        vec3  n    = getNormal(p, eps);
        n = bump(p, n, t);

        float crv  = curv(p, 2.5);
        float crv2 = curv(p, 0.5) * 2.5;

        float amb  = clamp(0.5 + 0.5 * n.y, 0.0, 1.0);
        float dif  = clamp(dot(n, lgt), 0.0, 1.0);
        float bac  = clamp(dot(n, normalize(vec3(-lgt.x, 0.0, -lgt.z))), 0.0, 1.0);
        float spe  = pow(clamp(dot(reflect(rd, n), lgt), 0.0, 1.0), 80.0);
        float fre  = pow(clamp(1.0 + dot(n, rd), 0.0, 1.0), 2.0);

        // Moon light + bass pulse
        float sunPulse = 1.0 + bassPulse * 2.5;
        vec3 brdf = amb * vec3(0.05, 0.07, 0.14);  // cool blue sky bounce
        brdf += bac * vec3(0.06, 0.05, 0.04);
        brdf += (1.2 * sunPulse) * dif * vec3(0.72, 0.78, 0.92);  // cold moonlight

        // Snow / rock / forest / frozen-lake coloring
        float slope    = clamp(n.y, 0.0, 1.0);
        float snowAmt  = smoothstep(snow_line - 0.8, snow_line + 1.8, p.y) * pow(slope, 0.5);
        float forestAmt = smoothstep(snow_line - 2.0, snow_line - 4.5, p.y)
                        * clamp(slope * 2.5, 0.0, 1.0) * (1.0 - snowAmt);
        float lakeAmt  = smoothstep(2.4, 0.8, p.y) * pow(slope, 5.0);

        vec3 snowCol   = vec3(0.84, 0.90, 0.98) + crv2 * 0.03;
        vec3 rockCol   = vec3(0.36, 0.33, 0.30) * (0.65 + crv * 0.45);
        vec3 forestCol = vec3(0.05, 0.11, 0.07);
        vec3 lakeCol   = vec3(0.07, 0.13, 0.25);

        col  = mix(rockCol, snowCol, snowAmt);
        col  = mix(col, forestCol, forestAmt);
        col  = mix(col, lakeCol, lakeAmt);
        col += clamp(crv * 0.5, -0.5, 0.5) * vec3(0.12, 0.10, 0.09);

        col  = col * brdf + col * spe * 0.06 + 0.05 * fre * col;
        col *= crv  * 0.7 + 1.0;
        col *= crv2 * 0.5 + 1.0;

    } else {
        col = geeseBg;
    }

    // --- Flag overlay (closer than terrain) ---
    if (bestFlagI >= 0 && bestFlagT < t) {
        if (isFlagPole) {
            col = vec3(0.60, 0.58, 0.55);  // silver pole
        } else {
            col = flagColor(bestFlagUV, lgt, bassPulse);
        }
        t = bestFlagT;
    }

    // --- Aurora scatter at horizon (additive glow on terrain) ---
    float scatter = clamp(dot(lgt, rd) * 0.4 + 0.4, 0.0, 1.0);
    col += aurCol * 0.12 * smoothstep(draw_distance * 0.5, draw_distance, t);

    // --- Distance fog toward dark sky ---
    vec3 fogCol = mix(vec3(0.01, 0.02, 0.05), bg * 0.5,
                      clamp(scatter * 0.6, 0.0, 1.0));
    col = mix(col, fogCol, smoothstep(draw_distance * 0.55, draw_distance, t));
    if (t >= draw_distance) col = geeseBg;

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
