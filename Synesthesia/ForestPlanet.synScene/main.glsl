// ============================================================
//  FOREST PLANET — v2.0
//  RBambey
//  Tree SDF technique from "Frosted Forest" by eiffie (CC-BY-NC-SA 3.0).
//  6-DOF flight from Ocean Planet by RBambey.
//
//  Trees: reed-tube SDFs with 3 levels of fractal branching (KIFS).
//         Per-tile hashes give each tree unique branching depth, tier
//         height, and canopy splay. Wind sway scales with height.
//  Look:  vivid greens lit by warm sun, purple fill in shadow, yellow
//         hotspots on brightest faces, hard ground shadows.
//  Render: 4-checkpoint near-surface accumulation — thin branch tips
//          become translucent. Temporal accumulation smooths texture.
// ============================================================

// World scale. Trees ~8 units tall; camera typically 2–40 units up.
const float TREE_SCALE = 8.0;

// Fixed sun direction (azimuth 0.15 turn, elevation sin=0.18).
// Pre-computed: cos(54°)*cos(10.4°), 0.18, sin(54°)*cos(10.4°) ≈ unit length.
const vec3 SUN_DIR = vec3(0.578, 0.180, 0.796);
const vec3 SUN_COL = vec3(1.0, 0.82, 0.52);   // warm amber-gold

// Globals set once per pixel at the start of renderMain
float iY;          // per-ray SDF conservatism (eiffie technique)
float g_randState; // per-pixel random seed

// ---- Utilities --------------------------------------------------------

float linstep(float a, float b, float t) {
    return clamp((t - a) / (b - a), 0.0, 1.0);
}

float rand2() {
    g_randState = fract(sin(g_randState * 127.1 + 311.7) * 43758.5453);
    return g_randState;
}

// ---- Tree primitive ----------------------------------------------------

// Tapered cylinder: height y∈[0,1], radius 0.02→0
float reed(vec3 p) {
    return max(length(p.xz) - 0.02 + p.y * 0.02,
               abs(p.y - 0.5) - 0.5);
}

// ---- Scene SDF ---------------------------------------------------------
// Trees tile every 2×TREE_SCALE world units. Three per-tile hashes give
// each tree a distinct branching depth, tier height, and canopy splay.

float DE(vec3 p0) {
    vec3  p  = p0 / TREE_SCALE;

    // Tile hashes — computed before wind to avoid boundary jitter
    float tx = floor(p.x * 0.5);
    float tz = floor(p.z * 0.5);
    float h1 = fract(sin(tx * 127.1  + tz * 311.7 ) * 43758.5453);
    float h2 = fract(sin(tx * 269.5  + tz *  83.3 ) * 43758.5453);
    float h3 = fract(sin(tx *  12.9  + tz *  78.23) * 43758.5453);

    float rnd   = tree_density - 0.5 + h1 * 2.5;   // branching levels 0–3
    float yStep = 0.26 + h2 * 0.38;                  // tier height (2.1–5.1 wu)
    float splay = 0.10 + h3 * 0.44;                  // canopy spread

    // Wind sway — amplitude grows with height
    float dy = wind_strength * 0.2 * clamp(p.y + 0.4, 0.0, 1.0);
    p += sin(p.zxy + 2.0 * sin(p.yzx)) * dy;

    float dg = p.y;               // ground plane
    float d  = 100.0, dr = 1.0;

    p.xz  = mod(p.xz, 2.0) - 1.0;
    p.xz  = abs(p.xz);
    p.xz -= p.y * p.y * splay;
    d     = reed(p) / dr;

    // 3 levels of scale×2 + 45° XZ fold (break is valid here: predicate is monotonic)
    for (int i = 0; i < 3; i++) {
        if (float(i) > rnd) break;
        p.y  -= yStep;
        p    *= 2.0;  dr *= 2.0;
        p.xz  = abs(vec2(p.x + p.z, p.x - p.z)) * 0.707;
        p.xz -= p.y * p.y * splay;
        d     = min(d, reed(p) / dr);
    }

    // Ground ×2 overestimates safely; iY makes canopy steps conservative
    return min(dg * 2.0, d * (1.0 - 0.5 * dy) / iY) * TREE_SCALE;
}

// ---- Normal (tetrahedron finite differences, 4 DE calls) ---------------

vec3 getForestNormal(vec3 p, float eps) {
    const vec2 k = vec2(1.0, -1.0);
    return normalize(
        k.xyy * DE(p + k.xyy * eps) +
        k.yyx * DE(p + k.yyx * eps) +
        k.yxy * DE(p + k.yxy * eps) +
        k.xxx * DE(p + k.xxx * eps)
    );
}

// ---- Shadows -----------------------------------------------------------

// Soft shadow cone for tree surfaces (8 steps, fuzzy penumbra)
float fuzzyShadow(vec3 ro, vec3 rd, float maxDist, float fuzzR) {
    float t = 0.05, s = 1.0;
    for (int i = 0; i < 8; i++) {
        if (t > maxDist) break;
        float r = fuzzR + t * 0.05;
        float d = DE(ro + rd * t) + r * 0.5;
        s *= linstep(-r, r, d);
        t += abs(d) * (0.85 + 0.15 * rand2());
    }
    return clamp(s, 0.0, 1.0);
}

// Hard ground shadow (16 steps, resets iY for upward rays through canopy)
float groundShadow(vec3 ro, vec3 rd) {
    float savedIY = iY;
    iY = 1.0 + max(0.0, 2.0 * rd.y);

    float t = 0.05, s = 1.0;
    for (int i = 0; i < 16; i++) {
        if (t > 62.0 || s < 0.01) break;
        float r = 0.14 + t * 0.008;
        float d = DE(ro + rd * t) + r * 0.3;
        s *= linstep(-r, r, d);
        t += max(abs(d), r * 0.25) * (0.9 + 0.1 * rand2());
    }

    iY = savedIY;
    return clamp(s, 0.0, 1.0);
}

// ---- Cloud noise (4-octave value FBM) ----------------------------------

float cloudHash(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 17.5);
    return fract(p.x * p.y);
}

float cloudNoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(cloudHash(i),             cloudHash(i + vec2(1,0)), f.x),
               mix(cloudHash(i + vec2(0,1)), cloudHash(i + vec2(1,1)), f.x), f.y);
}

float cloudFBM(vec2 p) {
    const mat2 m = mat2(1.6, 1.2, -1.2, 1.6);
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * cloudNoise(p);
        p  = m * p;
        a *= 0.5;
    }
    return v;
}

// ---- Sky ---------------------------------------------------------------
// sunDot = dot(rd, SUN_DIR), pre-computed by caller to avoid recomputing.

vec3 forestSky(vec3 rd, float sunDot) {
    // Base gradient: cyan-blue horizon → deep blue zenith
    float y   = clamp(rd.y, 0.0, 1.0);
    vec3  sky = mix(vec3(0.08, 0.22, 0.80), vec3(0.03, 0.08, 0.88), pow(y, 0.55));
    sky = mix(sky, vec3(0.72, 0.60, 0.22), exp(-abs(rd.y) * 8.0) * 0.20);  // sun haze

    // Clouds — overhead only, fade to zero below 24°
    if (rd.y > 0.12) {
        // Flat-plane projection: ray intersects cloud layer at altitude 80.
        // Unlike rd.xz/rd.y, this stays spread-out when looking straight up.
        float tCloud = max(80.0 - cam_y, 1.0) / rd.y;
        vec2  uv     = rd.xz * tCloud * 0.007 + TIME * vec2(0.005, 0.002);
        float c      = cloudFBM(uv * 1.8) * 0.70 + cloudFBM(uv * 4.2 + vec2(5.3, 2.1)) * 0.30;
        float alpha  = smoothstep(0.22, 0.52, c) * cloud_cover
                     * smoothstep(0.12, 0.40, rd.y);
        float dense  = smoothstep(0.48, 0.90, c);
        vec3  cCol   = mix(vec3(0.96, 0.98, 0.95), vec3(0.55, 0.62, 0.76), dense * 0.55)
                     * (sunDot * 0.15 + 0.85);
        cCol        += SUN_COL * pow(max(sunDot, 0.0), 8.0) * 0.10 * alpha;
        sky          = mix(sky, cCol, alpha);
    }

    // Sun disc + glow
    float sunDisc = smoothstep(0.9994, 0.9998, sunDot);
    float sunGlow = pow(max(sunDot, 0.0), 64.0) * 0.40
                  + pow(max(sunDot, 0.0), 10.0) * 0.08;
    sky += SUN_COL * (sunDisc * 2.5 + sunGlow);

    return sky;
}

// ---- Main --------------------------------------------------------------

vec4 renderMain() {

    // Seed per-pixel random state (combined with motion_blur creates frosted texture)
    g_randState = fract(sin(dot(_uv * RENDERSIZE, vec2(12.9898, 78.233))
                            + TIME * 3.71) * 43758.5453);

    // Camera basis (6-DOF, driven by script.js via setUniform)
    vec3 ro = vec3(cam_x, cam_y, cam_z);
    vec2 sc = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd = normalize(vec3(cam_fx, cam_fy, cam_fz)
                      + vec3(cam_rx, cam_ry, cam_rz) * sc.x
                      + vec3(cam_ux, cam_uy, cam_uz) * sc.y);

    // SDF step scale: conservative (small steps) when looking up through canopy
    iY = 1.0 + max(0.0, 2.0 * rd.y);

    float sunDot = dot(rd, SUN_DIR);
    vec3  bcol   = forestSky(rd, sunDot);

    // ---- Ray march: collect up to 4 near-surface checkpoints ----
    // Each checkpoint within fuzzR of a surface is shaded and composited
    // back-to-front. Branches thinner than fuzzR become translucent.
    float fuzzR = branch_fuzz;
    float h[4];
    h[0] = 0.0;  h[1] = 0.0;  h[2] = 0.0;  h[3] = 0.0;
    int  nHits = 0;
    vec4 col   = vec4(bcol, 0.0);

    float t = 0.05;
    for (int i = 0; i < 70; i++) {
        if (col.w > 0.9 || t > draw_distance) break;
        float d = DE(ro + rd * t);
        if (d < fuzzR && nHits < 4) { h[nHits] = t;  nHits++; }
        d *= 0.85 + 0.15 * rand2();
        t += max(d, fuzzR * 0.1);
    }

    // ---- Shade checkpoints back-to-front ----
    for (int i = 3; i >= 0; i--) {
        if (h[i] == 0.0) continue;

        vec3  p    = ro + rd * h[i];
        float dHit = DE(p);
        vec3  N    = getForestNormal(p, fuzzR * 1.2);
        if (dot(N, N) < 0.01) N = -rd;

        float localY   = p.y / TREE_SCALE;   // 0 = ground, ~1 = canopy top
        float topFace  = smoothstep(0.0, 0.7, N.y);
        float isGround = smoothstep(0.12, 0.0, localY) * topFace;

        // Material: bark → leaf (sides/tops) → ground moss
        vec3 baseCol = mix(
            mix(vec3(0.06, 0.52, 0.05),
                mix(vec3(0.10, 0.65, 0.08), vec3(0.22, 0.98, 0.08), topFace),
                topFace * 0.6),
            vec3(0.06, 0.52, 0.05),
            isGround);

        // Lighting: ambient + strong warm sun + hotspot + specular
        float ndotl   = clamp(dot(N, SUN_DIR), 0.0, 1.0);
        float hotspot = smoothstep(0.55, 1.0, ndotl) * (0.4 + topFace * 0.6);

        // Ambient: hemisphere — all warm green, no blue anywhere in shadows
        vec3 ambient  = vec3(0.03, 0.08, 0.02)
                      + vec3(0.03, 0.10, 0.02) * (dot(N, SUN_DIR) * 0.5 + 0.5);
        // Direct sun: strong — lit faces pop hard against dark shadows
        vec3 sun      = baseCol * SUN_COL * ndotl * 2.8;
        vec3 hot      = vec3(0.55, 0.48, 0.02) * hotspot;
        vec3 spec     = SUN_COL * pow(max(dot(reflect(rd, N), SUN_DIR), 0.0), 10.0) * 0.50;
        vec3 scol     = baseCol * ambient + sun + hot + spec;

        // Shadow — mix from very dark shadow color to full lit
        if (localY < 0.15) {
            // Ground: deep dark pools beneath trunks and branches
            float shadow   = groundShadow(p + vec3(0.0, 0.03, 0.0), SUN_DIR);
            vec3 shadowCol = baseCol * ambient * 0.10 + vec3(0.00, 0.01, 0.00);
            scol = mix(shadowCol, scol, shadow);
        } else if (i == 0) {
            // Nearest tree surface: soft fuzzy shadow
            vec3  sp       = p + N * max(0.0, -dHit + 0.02);
            float shadow   = fuzzyShadow(sp, SUN_DIR, 55.0, fuzzR);
            vec3 shadowCol = baseCol * ambient * 0.25 + vec3(0.00, 0.01, 0.00);
            scol = mix(shadowCol, scol, shadow);
        }

        scol *= 1.0 + syn_BassLevel * bass_reactivity * 0.3;                    // bass pulse
        vec3 fogCol = vec3(0.06, 0.36, 0.08);                                   // deep jungle green haze
        scol = mix(scol, fogCol, 1.0 - exp(-h[i] / (draw_distance * 2.5)));    // distance fog

        // Back-to-front alpha composite
        float alpha = (1.0 - col.w) * linstep(-fuzzR, fuzzR, -dHit);
        col = mix(col, vec4(scol, min(col.w + alpha, 1.0)), alpha);
    }

    vec3 finalCol = mix(bcol, col.rgb, col.w);

    // Gamma + saturation boost
    finalCol = pow(max(finalCol, vec3(0.0)), vec3(0.72));
    finalCol = mix(vec3(dot(finalCol, vec3(0.299, 0.587, 0.114))), finalCol, 1.45);

    // Vignette
    finalCol *= pow(16.0 * _uv.x * _uv.y * (1.0 - _uv.x) * (1.0 - _uv.y), 0.1) * 0.9 + 0.1;

    // Motion blur (temporal accumulation — smooths the per-frame fuzz noise)
    finalCol = mix(finalCol, texture(syn_FinalPass, _uv).rgb, motion_blur);

    return vec4(finalCol, 1.0);
}
