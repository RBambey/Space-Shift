// ============================================================
//  MARS — v1.0
//  Created by RBambey
//  Terrain inspired by "Sirenian Dawn" by nimitz
//  (shadertoy.com/view/XsyGWV), CC BY-NC-SA 3.0
//  Procedural derivative-warped FBM terrain, Martian palette
// ============================================================

// ---- Hash ----
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// ---- Value noise (replaces texture lookups in fbm/bump) ----
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i),             hash(i + vec2(1, 0)), u.x),
               mix(hash(i + vec2(0,1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// ---- Gradient noise with analytic derivatives (replaces textureLod in terrain) ----
vec3 noised(vec2 x) {
    vec2 i  = floor(x), f = fract(x);
    vec2 u  = f * f * (3.0 - 2.0 * f);
    vec2 du = 6.0 * f * (1.0 - f);
    float a = hash(i),             b = hash(i + vec2(1, 0));
    float c = hash(i + vec2(0,1)), d = hash(i + vec2(1, 1));
    float v = a + (b-a)*u.x + (c-a)*u.y + (a-b-c+d)*u.x*u.y;
    return vec3(v, du * vec2((b-a) + (a-b-c+d)*u.y, (c-a) + (a-b-c+d)*u.x));
}

// ---- Terrain — 4-octave derivative-warped FBM ----
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
    return p.y - terrain(p.xz * 0.07 / terrain_scale) * 3.5 - 1.0;
}

// ---- Ray-terrain intersection (forward scan + bisect) ----
float heightMapTracing(vec3 ro, vec3 rd, out vec3 p) {
    float t = 0.1, stepSize = 0.1;
    for (int i = 0; i < 50; i++) {
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
        stepSize = max(0.5, h * 0.6);
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
    vec3  d  = vec3(bnoise(p.zx + e.xy) - n0, 1.0, bnoise(p.zx + e.yx) - n0) / e.x * 0.025;
    d -= n * dot(n, d);
    return normalize(n - d);
}

// ---- Surface curvature (drives ridge/valley color contrast) ----
float curv(vec3 p, float w) {
    vec2 e = vec2(-1.0, 1.0) * w;
    return 0.15 / e.y * (map(p + e.yxx) + map(p + e.xxy) + map(p + e.xyx) + map(p + e.yyy) - 4.0 * map(p));
}

// ---- FBM for fog animation ----
float fbm2(vec2 p) {
    float z = 0.5, rz = 0.;
    for (int i = 0; i < 3; i++) {
        rz += noise(p) * z;
        z  *= 0.5;
        p  *= 2.0;
    }
    return rz;
}

// ---- Dust haze fog ----
vec3 fog(vec3 ro, vec3 rd, vec3 col, float ds, vec3 lgt) {
    vec3  pos = ro + rd * ds;
    float mx  = (fbm2(pos.zx * 0.1 - TIME * 0.05) - 0.5) * 0.2;

    float rdyAbs = abs(rd.y);
    float fog_integral = (rdyAbs < 0.001) ? ds : (1.0 - exp(-ds * rd.y)) / rd.y;
    float den = fog_density * 0.3 * exp(-ro.y) * max(fog_integral, 0.0);

    float sdt     = max(dot(rd, lgt), 0.0);
    vec3  fogCol  = mix(vec3(0.50, 0.16, 0.09) * 1.2,
                        vec3(1.05, 0.48, 0.28) * 1.3,
                        pow(sdt, 2.0) + mx * 0.5);
    return mix(col, fogCol, clamp(den + mx, 0.0, 1.0));
}

// ---- Horizon atmosphere scatter ----
vec3 scatter(vec3 ro, vec3 rd, vec3 lgt) {
    float sd   = max(dot(lgt, rd) * 0.5 + 0.5, 0.0);
    float dtp  = 13.0 - (ro + rd * draw_distance).y * 3.5;
    float hori = clamp((dtp + 1500.0) / 1500.0, 0.0, 1.0)
               - clamp((dtp - 11.0)   / 489.0,  0.0, 1.0);
    hori *= pow(sd, 0.04);
    vec3 col = vec3(0.0);
    col += pow(hori, 200.0) * vec3(1.0, 0.52, 0.22) * 3.0;
    col += pow(hori, 25.0)  * vec3(0.98, 0.34, 0.12) * 0.3;
    col += pow(hori, 7.0)   * vec3(0.95, 0.28, 0.10) * 0.8;
    return col * scatter_amount;
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
    float res = RENDERSIZE.x * 0.8;
    for (float i = 0.0; i < 3.0; i++) {
        vec3  q  = fract(rd * (0.15 * res)) - 0.5;
        vec3  id = floor(rd * (0.15 * res));
        vec2  rn = nmzHash33(id).xy;
        float c2 = (1.0 - smoothstep(0.0, 0.6, length(q)))
                 * step(rn.x, 0.0005 + i * i * 0.001);
        c  += c2 * (mix(vec3(1.0, 0.55, 0.25), vec3(0.9, 0.85, 1.0), rn.y) * 0.25 + 0.75);
        rd *= 1.4;
    }
    return c * c * 0.7;
}

// ---- Horizon mountain range (angular space — position fixed regardless of camera) ----
float hmh(float az) {
    float h = noise(vec2(az * 3.2,  0.30)) * 0.50
            + noise(vec2(az * 6.7,  1.91)) * 0.28
            + noise(vec2(az * 14.1, 4.53)) * 0.15
            + noise(vec2(az * 29.3, 7.82)) * 0.07;
    return max(h - 0.40, 0.0) * (1.0 / 0.60);
}

vec4 horizonMountains(vec3 rd, vec3 lgt) {
    float el = rd.y;
    if (el > 0.22 || el < -0.02) return vec4(0.0);

    float az = atan(rd.x, rd.z);
    float mh = hmh(az) * 0.16;           // max peak ~0.16 elevation angle

    if (el > mh) return vec4(0.0);        // above silhouette → sky

    // Lighting normal from azimuth slope
    float eps = 0.006;
    float dh  = (hmh(az + eps) - hmh(az - eps)) * 0.16;
    vec3  n   = normalize(vec3(-dh * cos(az), eps * 4.0, -dh * sin(az)));

    float diff  = max(dot(n, lgt), 0.0);
    float elT   = clamp(el / max(mh, 0.001), 0.0, 1.0);
    float shade = 0.18 + diff * 0.65 + smoothstep(0.0, 0.7, elT) * 0.12;

    vec3 mtnCol = vec3(0.32, 0.17, 0.11) * shade;

    // Horizon haze — sunward warm rust, shadowed dark red
    float sdt     = max(dot(rd, lgt) * 0.5 + 0.5, 0.0);
    vec3  haze    = mix(vec3(0.28, 0.10, 0.06), vec3(0.82, 0.34, 0.16), pow(sdt, 1.5));
    float hazeAmt = mix(0.65, 0.28, elT);  // base very hazy, peaks more defined

    return vec4(mix(mtnCol, haze, hazeAmt), 1.0);
}

// ================================================================
vec4 renderMain() {

    // --- Camera ---
    vec3 ro     = vec3(cam_x, cam_y, cam_z);
    vec3 cRight = vec3(cam_rx, cam_ry, cam_rz);
    vec3 cUp    = vec3(cam_ux, cam_uy, cam_uz);
    vec3 cFwd   = vec3(cam_fx, cam_fy, cam_fz);
    vec2 uv     = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd     = normalize(cFwd + cRight * uv.x + cUp * uv.y);

    // --- Sun direction ---
    float sunAz = sun_angle * 2.0 * PI;
    float sinEl = sun_elevation;
    float cosEl = sqrt(max(1.0 - sinEl * sinEl, 0.0));
    vec3  lgt   = normalize(vec3(cos(sunAz) * cosEl, sinEl, sin(sunAz) * cosEl));

    // --- Sky background ---
    vec3 scatt = scatter(ro, rd, lgt);
    vec3 bg    = stars(rd) * (1.0 - clamp(dot(scatt, vec3(1.3)), 0.0, 1.0));
    vec3 col   = bg;

    // --- Trace ---
    vec3  p;
    float t = heightMapTracing(ro, rd, p);

    // --- Surface shading ---
    if (t < draw_distance) {
        float eps = max(t * 0.002, 0.02);
        vec3  n   = getNormal(p, eps);
        n = bump(p, n, t);

        float amb  = clamp(0.5 + 0.5 * n.y, 0.0, 1.0);
        float dif  = clamp(dot(n, lgt), 0.0, 1.0);
        float bac  = clamp(dot(n, normalize(vec3(-lgt.x, 0.0, -lgt.z))), 0.0, 1.0);
        float spe  = pow(clamp(dot(reflect(rd, n), lgt), 0.0, 1.0), 500.0);
        float fre  = pow(clamp(1.0 + dot(n, rd), 0.0, 1.0), 2.0);

        float bassAmt = syn_BassLevel * bass_reactivity;
        vec3  brdf    = amb * vec3(0.10, 0.08, 0.07);
        brdf += bac * vec3(0.18, 0.06, 0.04);
        brdf += (2.3 + bassAmt * 0.8) * dif * vec3(0.85, 0.28, 0.17);

        col = vec3(0.32, 0.17, 0.11);
        float crv  = curv(p, 2.0);
        float crv2 = curv(p, 0.4) * 2.5;
        col += clamp(crv * 0.9, -1.0, 1.0) * vec3(0.28, 0.18, 0.10);
        col  = col * brdf + col * spe * 0.1 + 0.1 * fre * col;
        col *= crv  * 1.0 + 1.0;
        col *= crv2 * 1.0 + 1.0;
    }

    // --- Atmosphere ---
    col  = fog(ro, rd, col, t, lgt);
    col  = mix(col, bg, smoothstep(draw_distance - 150.0, draw_distance, t));
    col += scatt;

    // --- Horizon mountains (angular-space backdrop, never reachable) ---
    if (t >= draw_distance) {
        vec4 mtn = horizonMountains(rd, lgt);
        if (mtn.a > 0.5) col = mtn.rgb + scatt;
    }

    // --- Tonemap + gamma ---
    col = pow(max(col, vec3(0.0)), vec3(0.93, 1.0, 1.0));
    col = mix(col, smoothstep(0.0, 1.0, col), 0.2);

    // --- Vignette ---
    vec2 q = _uv;
    col *= pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.12) * 0.9 + 0.1;

    // --- Motion blur ---
    vec4 past = texture(syn_FinalPass, _uv);
    col = mix(col, past.rgb, motion_blur);

    return vec4(col, 1.0);
}
