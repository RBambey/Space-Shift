// ============================================================
//  BLACK HOLE — v2.0
//  Created by RBambey
//  Architecture based on Retro 70s Gas Giant (mrange / RBambey)
//  Black hole visual: "Singularity" by @XorDev (shadertoy.com/view/tsBXW3)
//  Camera flies above the accretion disk. Bass hits pulse the inner disk.
// ============================================================

// ---- Color utilities (from gas giant) ----
const vec4 hsv2rgb_K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
vec3 hsv2rgb(vec3 c) {
    vec3 p = abs(fract(c.xxx + hsv2rgb_K.xyz) * 6.0 - hsv2rgb_K.www);
    return c.z * mix(hsv2rgb_K.xxx, clamp(p - hsv2rgb_K.xxx, 0.0, 1.0), c.y);
}

vec3 tanh_approx(vec3 x) {
    vec3 x2 = x * x;
    return clamp(x * (27.0 + x2) / (27.0 + 9.0 * x2), -1.0, 1.0);
}

// ---- Math constants ----
const float TAU   = 2.0 * PI;
const float PI_2  = 0.5 * PI;

// ---- Hash / stars (from gas giant) ----
float hash(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 58.233))) * 13758.5453);
}

float hash3f(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

vec3 hash3v(vec3 p) {
    p = fract(p * mat3(vec3(0.1031, 0.1030, 0.0973),
                       vec3(0.1031, 0.1997, 0.1030),
                       vec3(0.0973, 0.1030, 0.1997)));
    p += dot(p, p.yxz + 33.33);
    return fract(vec3((p.x + p.y) * p.z, (p.x + p.z) * p.y, (p.y + p.z) * p.x));
}

float gridNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i),             hash(i + vec2(1,0)), u.x),
               mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), u.x), u.y);
}

float atan_approx(float y, float x) {
    float cosatan2 = x / (abs(x) + abs(y));
    float t = PI_2 - cosatan2 * PI_2;
    return y < 0.0 ? -t : t;
}

float acos_approx(float x) {
    return atan_approx(sqrt(max(0.0, 1.0 - x * x)), x);
}

vec3 to_spherical(vec3 p) {
    float r = length(p);
    return vec3(r, acos_approx(p.z / r), atan_approx(p.y, p.x));
}

vec3 stars(vec3 Rd) {
    float Z = TAU / 200.0;
    vec3 col = vec3(0.0);
    float a = 1.0;
    for (int i = 0; i < 3; ++i) {
        Rd = Rd.zxy;
        vec2 s = to_spherical(Rd).yz;
        vec2 n = floor(s / Z + 0.5);
        vec2 c = s - Z * n;
        float h  = sin(s.x);
        float h0 = hash(n + 123.4 * float(i + 1));
        float h1 = fract(8667.0 * h0);
        float h3 = fract(9977.0 * h0);
        c.y *= h;
        col += a * hsv2rgb(vec3(-0.4 * h1, sqrt(h3),
                                 step(h0, 0.1 * h) * h1 * vec3(7e-6) / (7e-8 + dot(c, c))));
        Z *= 0.5;
        a *= 0.5;
    }
    return col;
}

// ---- FBM for disk texture banding ----
float fbm(float x) {
    float a = 1.0, h = 0.0;
    for (int i = 0; i < 5; ++i) {
        h += a * sin(x);
        x *= 2.03;
        x += 123.4;
        a *= 0.55;
    }
    return abs(h);
}

// ---- Ray utilities ----
float ray_plane(vec3 ro, vec3 rd, vec4 p) {
    return -(dot(ro, p.xyz) + p.w) / dot(rd, p.xyz);
}

// ---- Gaussian blur helper (bloom passes) ----
vec3 gb(sampler2D pp, ivec2 dir, ivec2 xy) {
    const float blurriness = 200.0;
    ivec2 sz = textureSize(pp, 0) - 1;
    vec3 col = texelFetch(pp, xy, 0).xyz;
    float w, ws = 1.0, I;
    for (int i = 1; i < 25; ++i) {
        I = float(i);
        w = exp(-(I * I) / blurriness);
        ivec2 off = i * dir;
        col += w * (texelFetch(pp, clamp(xy - off, ivec2(0), sz), 0).xyz
                  + texelFetch(pp, clamp(xy + off, ivec2(0), sz), 0).xyz);
        ws += 2.0 * w;
    }
    col /= ws;
    return col;
}

// ---- Black hole — Singularity by @XorDev, adapted ----
// Bass: rim narrows on hits (brighter ring) + additive orange pulse.
vec3 blackHole(vec2 p) {
    float i = 0.2, a;
    vec2 d = vec2(-1.0, 1.0);
    vec2 b = p - i * d;
    vec2 c = p * mat2(1.0, 1.0, d / (0.1 + i / dot(b, b)));
    a = dot(c, c);
    vec2 v = c * mat2(cos(0.5 * log(a) + TIME * i + vec4(0.0, 33.0, 11.0, 0.0))) / i;
    vec2 w = vec2(0.0);

    for (; i++ < 9.0; w += 1.0 + sin(v))
        v += 0.7 * sin(v.yx * i + TIME) / i + 0.5;

    float rimWidth = 0.03 + abs(length(p) - 0.7) / (1.0 + syn_BassLevel * 5.0);
    i = length(sin(v / 0.3) * 0.4 + c * (3.0 + d));

    vec4 O = 1.0 - exp(-exp(c.x * vec4(0.6, -0.4, -1.0, 0.0))
                        / w.xyyx
                        / (2.0 + i * i / 4.0 - i)
                        / (0.5 + 1.0 / a)
                        / rimWidth);

    float pulse = exp(-pow(abs(length(p) - 0.7), 2.0) * 40.0) * syn_BassLevel * 1.5;
    O.rgb += vec3(1.0, 0.45, 0.1) * pulse;
    return clamp(O.rgb, 0.0, 1.5);
}

// Near-field disk: 2D XZ DDA, spheres centered at y=0.
// Returns vec4(rgb, hit_t) on hit, vec4(0) on miss.
vec4 diskNear(vec3 ro, vec3 rd) {
    const float VSIZE    = 20.0;
    const float RROCK    = 8.0;
    const float NEARDIST = 600.0;
    const float innerR   = 300.0, outerR = 2000.0;
    vec2 bhCenter = vec2(ro.x, ro.z + 1000.0);

    // Clip t range to where |ro.y + rd.y*t| <= RROCK (sphere could be hit)
    if (abs(rd.y) < 1e-5) return vec4(0.0);
    float ta = (-RROCK - ro.y) / rd.y;
    float tb = ( RROCK - ro.y) / rd.y;
    if (ta > tb) { float tmp = ta; ta = tb; tb = tmp; }
    float tS = max(ta, 0.001);
    float tE = min(tb, NEARDIST);
    if (tS >= tE) return vec4(0.0);

    // 2D DDA in XZ
    vec2 rp  = ro.xz + rd.xz * tS;
    vec2 vox = floor(rp / VSIZE);
    vec2 stp = sign(rd.xz + 1e-10);
    vec2 dlt = VSIZE / max(abs(rd.xz), vec2(1e-6));
    vec2 nxt = (vox * VSIZE + max(stp, vec2(0.0)) * VSIZE - rp)
               / (rd.xz + stp * 1e-8);

    for (int i = 0; i < 48; i++) {
        if (tS + min(nxt.x, nxt.y) > tE) break;

        // Rock sphere centered at y=0
        vec3  vcen  = vec3((vox.x + 0.5) * VSIZE, 0.0, (vox.y + 0.5) * VSIZE);
        float d2bh  = length(vcen.xz - bhCenter);

        if (d2bh > innerR && d2bh < outerR) {
            float ld1 = smoothstep(0.35, 0.75, gridNoise(vox * 0.003));
            float ld2 = smoothstep(0.30, 0.70, gridNoise(vox * 0.011));
            if (hash3f(vec3(vox, 0.0)) < ld1 * ld2 * 0.90) {
                vec3  oc   = ro - vcen;
                float b    = dot(oc, rd);
                float c    = dot(oc, oc) - RROCK * RROCK;
                float disc = b * b - c;
                if (disc > 0.0) {
                    float sqD = sqrt(disc);
                    float t   = -b - sqD;
                    if (t < tS || t > tE) t = -b + sqD;  // try exit face if entry missed
                    if (t > tS && t < tE) {
                        vec3  hitP = ro + rd * t;
                        vec3  nrm  = normalize(hitP - vcen);
                        vec3  hv   = hash3v(vec3(vox, 0.0));
                        float u    = clamp((d2bh - innerR) / (outerR - innerR), 0.0, 1.0);

                        // Rocky color: inner orange-white → outer dark amber
                        vec3 rock  = mix(vec3(1.1, 0.55, 0.14), vec3(0.22, 0.11, 0.04), u);
                        rock      *= 0.5 + 0.5 * hv.x;

                        // Top-lit: camera is above, so top hemisphere is visible and bright
                        float litUp = max(0.0, nrm.y);

                        // Per-rock BH glow: direction to BH varies by ring position
                        vec2  toBH2 = bhCenter - vcen.xz;
                        vec3  bhDir = normalize(vec3(toBH2.x, 0.0, toBH2.y));
                        float litBH = max(0.0, dot(nrm, bhDir));

                        vec3  col = rock * (0.2 + 0.6 * litUp + 0.2 * litBH);
                        col      += vec3(1.0, 0.35, 0.05) * pow(litBH, 3.0) * 0.6;

                        float fog = exp(-t * 0.0006);
                        col      *= disk_brightness * fog
                                  * (1.0 + syn_BassLevel * 0.8 * exp(-u * 3.0));
                        return vec4(col, t);
                    }
                }
            }
        }

        // Advance 2D DDA
        if (nxt.x < nxt.y) { nxt.x += dlt.x; vox.x += stp.x; }
        else                { nxt.y += dlt.y; vox.y += stp.y; }
    }
    return vec4(0.0);
}

// ============================================================
vec4 renderMain() {

    // ---- PASS 0 — Main render ----
    if (PASSINDEX == 0) {

        vec3 ro     = vec3(cam_x, cam_y, cam_z);
        vec3 cRight = vec3(cam_rx, cam_ry, cam_rz);
        vec3 cUp    = vec3(cam_ux, cam_uy, cam_uz);
        vec3 cFwd   = vec3(cam_fx, cam_fy, cam_fz);
        vec2 uv     = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
        vec3 Rd     = normalize(cFwd + cRight * uv.x + cUp * uv.y);

        // 2 — Accretion disk: near voxel rocks + far noise plane
        vec3 diskFront = vec3(0.0);
        vec3 diskBack  = vec3(0.0);

        // Near field: DDA sphere rocks (always closer than BH → diskFront)
        vec4 nearR   = diskNear(ro, Rd);
        bool nearHit = (nearR.w > 0.0);
        if (nearHit) diskFront += nearR.xyz;

        // Far field: flat plane with Reinder-style density alpha (genuine 0 gaps)
        if (!nearHit && ro.y > 0.0 && abs(Rd.y) > 0.0001) {
            float t = -ro.y / Rd.y;
            if (t > 0.5) {
                vec3  hit      = ro + Rd * t;
                vec2  bhCenter = vec2(ro.x, ro.z + 1000.0);
                float dist     = length(hit.xz - bhCenter);

                const float innerR = 300.0, outerR = 2000.0;
                float diskMask = smoothstep(innerR - 80.0, innerR, dist)
                               * smoothstep(outerR, outerR - 200.0, dist);

                if (diskMask > 0.001) {
                    float u = clamp((dist - innerR) / (outerR - innerR), 0.0, 1.0);

                    // Tightened thresholds + grazing-angle suppression
                    float d1    = smoothstep(0.35, 0.75, gridNoise(hit.xz * 0.003));
                    float d2    = smoothstep(0.30, 0.70, gridNoise(hit.xz * 0.012));
                    float band  = 0.5 + 0.5 * sin(dist * 0.015 + TIME * 0.015);
                    float graze = smoothstep(0.0, 0.10, abs(Rd.y));
                    float dens  = d1 * d2 * band * diskMask * graze;

                    if (dens > 0.002) {
                        float ng   = gridNoise(hit.xz * 0.06);
                        vec3  rock = mix(vec3(1.1, 0.58, 0.15), vec3(0.24, 0.12, 0.04), u);
                        rock      *= 0.55 + 0.45 * ng;

                        float brightness = disk_brightness * (1.4 - u * 0.9) * dens;
                        brightness      += syn_BassLevel * 0.8 * exp(-u * 3.0);

                        float fog = exp(-t * 0.0004);
                        vec3  dc  = rock * brightness * fog;

                        if (Rd.z * t < 1000.0) diskFront += dc;
                        else                    diskBack  += dc;
                    }
                }
            }
        }

        // 1 — Background + stars + disk-back (behind BH)
        vec3 col = vec3(0.0);
        if (show_stars > 0.5) col += stars(Rd);
        col += diskBack;

        // 3 — Black hole (Singularity, fixed at world +Z)
        if (Rd.z > 0.01) {
            vec2 bhP = (vec2(Rd.x, Rd.y) / Rd.z) * (2.0 / 0.7) / bh_scale;
            float _cr = cos(bh_rotation * 6.28318);
            float _sr = sin(bh_rotation * 6.28318);
            bhP = vec2(_cr * bhP.x - _sr * bhP.y, _sr * bhP.x + _cr * bhP.y);
            float bhFade = smoothstep(3.0, 1.5, length(bhP));
            if (bhFade > 0.001) col = mix(col, blackHole(bhP), bhFade);
        }

        // Disk-front composited on top of BH
        col += diskFront;

        return vec4(col, 1.0);


    // ---- PASS 1 — Bloom threshold (extract bright pixels from BuffA) ----
    } else if (PASSINDEX == 1) {
        vec3 c = texelFetch(BuffA, ivec2(_xy), 0).xyz;
        c *= smoothstep(0.2, 0.5, dot(vec3(0.2126, 0.7152, 0.0722), c));
        return vec4(c, 1.0);


    // ---- PASS 2 — Horizontal Gaussian blur ----
    } else if (PASSINDEX == 2) {
        return vec4(gb(BuffB, ivec2(3, 0), ivec2(_xy)), 1.0);


    // ---- PASS 3 — Vertical Gaussian blur + blend ----
    } else if (PASSINDEX == 3) {
        vec3 b = gb(BuffC, ivec2(0, 3), ivec2(_xy));
        vec3 p = texelFetch(BuffB, ivec2(_xy), 0).xyz;
        return vec4(mix(b, p, 0.95), 1.0);


    // ---- PASS 4 — Final composite ----
    } else {
        vec3 scene = texelFetch(BuffA, ivec2(_xy), 0).xyz;
        vec3 bloom = texelFetch(BuffD, ivec2(_xy), 0).xyz;
        vec3 MC    = hsv2rgb(vec3(OFF + 0.1, 0.7, 1.0));

        vec3 c = scene;
        c += bloom * MC * bloom_amount;
        c  = max(c, 0.0);
        c  = tanh_approx(c);
        c  = sqrt(c);
        return vec4(c, 1.0);
    }
}
