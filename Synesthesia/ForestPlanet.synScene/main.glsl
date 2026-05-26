// ============================================================
//  FROSTED FOREST — v1.1
//  Created by RBambey
//  Tree SDF and rendering technique from "Frosted Forest"
//  by eiffie (CC-BY-NC-SA 3.0)
//  Strandbeest creature removed; pure forest remains.
//  Flying controls from Ocean Planet by RBambey.
//
//  Architecture:
//    - Trees are reed/tube SDFs with 3 levels of fractal branching
//      (KIFS: scale×2 + 45° XZ fold per level). Each 2×2 tile has
//      a different number of branching levels → natural variety.
//    - Wind sway via sin-displaced coordinates, scaled by height.
//    - "Jungle" look: lush greens on all surfaces; purple-tinted
//      shadows created by lerping between a purple fill light and
//      warm golden key light based on N·L. Fuzzy shadows blend
//      toward vivid purple rather than plain darkening.
//    - iY: per-ray SDF scale from eiffie — allows larger steps
//      looking up through sparse canopy, conservative looking down.
//    - Motion blur (temporal accumulation) smooths the per-frame
//      random jitter that creates the soft needle texture.
// ============================================================

// ================================================================
//  SCALE
//  World space is TREE_SCALE × bigger than eiffie's original coords.
//  Trees: ~8 world units tall.  Camera: typically 2–40 world units.
// ================================================================
const float TREE_SCALE = 8.0;

// ================================================================
//  TREE SDF — reed tube with fractal branching (from eiffie)
//
//  reed(): tapered cylinder, height y=[0,1], radius 0.02→0
// ================================================================
float reed(vec3 p) {
    return max(length(p.xz) - 0.02 + p.y * 0.02,
               abs(p.y - 0.5) - 0.5);
}

// Per-ray SDF conservatism factor (set once per pixel in renderMain)
float iY;

// ================================================================
//  RANDOM — seeded per pixel per frame, used for march jitter
// ================================================================
float g_randState;

float rand2() {
    g_randState = fract(sin(g_randState * 127.1 + 311.7) * 43758.5453);
    return g_randState;
}

// ================================================================
//  SCENE SDF
//
//  Beestie creature completely removed from original.
//  Trees tile every 2 original units = 2×TREE_SCALE world units.
//
//  Per-tile variety: three independent hash values drive uncorrelated
//  variation in branching depth, tier height, and canopy splay so
//  each tree has a distinct character — short/tall, wide/narrow.
// ================================================================
float DE(vec3 p0) {
    vec3 p = p0 / TREE_SCALE;    // work in original-shader coordinates

    // --- Per-tile hashes: computed before wind moves the position ---
    // Using three uncorrelated hash functions avoids periodic patterns
    float tx = floor(p.x * 0.5);
    float tz = floor(p.z * 0.5);
    float h1 = fract(sin(tx * 127.1  + tz * 311.7 ) * 43758.5453);  // branching
    float h2 = fract(sin(tx * 269.5  + tz *  83.3 ) * 43758.5453);  // tier height
    float h3 = fract(sin(tx *  12.9  + tz *  78.23) * 43758.5453);  // splay

    // Branching levels (0–3): hash-driven → no periodic grid pattern
    float rnd   = tree_density - 0.5 + h1 * 2.5;

    // Tier height: short stumpy trees vs tall elegant ones
    // 0.26–0.64 in original coords → 2.1–5.1 world units per tier
    float yStep = 0.26 + h2 * 0.38;

    // Branch splay: narrow columnar vs wide drooping canopy
    float splay = 0.10 + h3 * 0.44;

    // Wind sway — amplitude increases with height
    float dy = wind_strength * 0.2 * clamp(p.y + 0.4, 0.0, 1.0);
    p += sin(p.zxy + 2.0 * sin(p.yzx)) * dy;

    float dg = p.y;               // ground plane distance
    float d  = 100.0, dr = 1.0;

    // XZ tile: trees repeat every 2 original units
    p.xz  = mod(p.xz, 2.0) - 1.0;
    p.xz  = abs(p.xz);
    p.xz -= p.y * p.y * splay;   // per-tree canopy spread

    d = reed(p) / dr;

    // Fractal branching: 3 levels of scale×2 + 45° XZ fold
    for (int i = 0; i < 3; i++) {
        if (float(i) > rnd) continue;
        p.y  -= yStep;            // per-tree tier height
        p    *= 2.0;  dr *= 2.0;
        p.xz  = abs(vec2(p.x + p.z, p.x - p.z)) * 0.707;
        p.xz -= p.y * p.y * splay;
        d     = min(d, reed(p) / dr);
    }

    // World-space distance: ground overestimate × 2 keeps march fast;
    // iY makes steps conservative looking up through canopy
    return min(dg * 2.0, d * (1.0 - 0.5 * dy) / iY) * TREE_SCALE;
}

// ================================================================
//  UTILITIES
// ================================================================
float linstep(float a, float b, float t) {
    return clamp((t - a) / (b - a), 0.0, 1.0);
}

// Normal via tetrahedron finite differences (4 DE calls)
vec3 getForestNormal(vec3 p, float eps) {
    const vec2 k = vec2(1.0, -1.0);
    return normalize(
        k.xyy * DE(p + k.xyy * eps) +
        k.yyx * DE(p + k.yyx * eps) +
        k.yxy * DE(p + k.yxy * eps) +
        k.xxx * DE(p + k.xxx * eps)
    );
}

// ================================================================
//  FUZZY SHADOW (simplified from eiffie — 8-step fuzzy cone)
//  Applied only to the closest surface hit for performance.
// ================================================================
float FuzzyShadow(vec3 ro, vec3 rd, float lightDist, float rCoC) {
    float t = 0.05, s = 1.0;
    for (int i = 0; i < 8; i++) {
        if (t > lightDist) break;
        float r = rCoC + t * 0.05;
        float d = DE(ro + rd * t) + r * 0.5;
        s *= linstep(-r, r, d);
        t += abs(d) * (0.85 + 0.15 * rand2());
    }
    return clamp(s, 0.0, 1.0);
}

// ================================================================
//  GROUND SHADOW — hard shadows cast by trunks/branches onto floor
//
//  Uses more steps and sets iY correctly for upward shadow rays
//  (camera ray iY would be wrong — sun is going up through canopy).
//  Tight, near-constant penumbra so trunk shadows read as solid dark.
// ================================================================
float groundShadow(vec3 ro, vec3 rd) {
    float savedIY = iY;
    iY = 1.0 + max(0.0, 2.0 * rd.y);  // conservative upward stepping through canopy

    float t = 0.05, s = 1.0;
    for (int i = 0; i < 22; i++) {
        if (t > 62.0 || s < 0.01) break;
        float r  = 0.14 + t * 0.008;          // tight cone — stays narrow at distance
        float d  = DE(ro + rd * t) + r * 0.3;
        s *= linstep(-r, r, d);
        t += max(abs(d), r * 0.25) * (0.9 + 0.1 * rand2());
    }

    iY = savedIY;
    return clamp(s, 0.0, 1.0);
}

// ================================================================
//  SKY — cool winter blue, warm golden low sun
// ================================================================
vec3 forestSky(vec3 rd, vec3 L, vec3 sunCol) {
    vec3  horizon = vec3(0.18, 0.58, 0.72);   // clean cyan-blue horizon, no green muddiness
    vec3  zenith  = vec3(0.04, 0.12, 0.85);   // deep saturated blue zenith
    float y       = clamp(rd.y, 0.0, 1.0);
    vec3  sky     = mix(horizon, zenith, pow(y, 0.55));

    // Warm amber-gold sun haze low on the horizon
    sky = mix(sky, vec3(0.72, 0.60, 0.22), exp(-abs(rd.y) * 8.0) * 0.20);

    // Sun disc + glow — small crisp disc with narrow halo
    float sunDot  = dot(rd, L);
    float sunDisc = smoothstep(0.9994, 0.9998, sunDot);  // tight disc (~2° radius)
    float sunGlow = pow(max(sunDot, 0.0), 64.0) * 0.40   // tight bright inner halo
                  + pow(max(sunDot, 0.0), 10.0) * 0.08;  // narrow wider corona
    sky += sunCol * sunDisc * 2.5;
    sky += sunCol * sunGlow;

    return sky;
}

// ================================================================
vec4 renderMain() {

    // ---- Seed random state from pixel + time ----
    // Combined with motion_blur, the per-frame jitter creates the
    // smooth frosted texture through temporal accumulation.
    g_randState = fract(sin(dot(_uv * RENDERSIZE,
                                vec2(12.9898, 78.233))
                            + TIME * 3.71) * 43758.5453);

    // ---- Camera (Ocean Planet 6-DOF basis) ----
    vec3 ro     = vec3(cam_x, cam_y, cam_z);
    vec3 cRight = vec3(cam_rx, cam_ry, cam_rz);
    vec3 cUp    = vec3(cam_ux, cam_uy, cam_uz);
    vec3 cFwd   = vec3(cam_fx, cam_fy, cam_fz);
    vec2 uv     = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd     = normalize(cFwd + cRight * uv.x + cUp * uv.y);

    // ---- Sun direction (fixed: azimuth 0.15 turn, elevation sin=0.18) ----
    // Pre-computed: normalize(cos(54°)*cos(10.4°), 0.18, sin(54°)*cos(10.4°))
    vec3  L      = normalize(vec3(0.578, 0.180, 0.796));
    vec3  sunCol = vec3(1.0, 0.82, 0.52);    // warm amber-gold sun

    // ---- SDF scale adjustment (eiffie's technique) ----
    // Larger iY when looking upward → smaller steps through canopy
    iY = 1.0 + max(0.0, 2.0 * rd.y);

    // ---- Background sky ----
    vec3 bcol = forestSky(rd, L, sunCol);

    // ================================================================
    //  Ray march with 4-checkpoint frosted accumulation
    //
    //  When the ray comes within branch_fuzz of a surface, it stores
    //  a checkpoint rather than immediately stopping. Up to 4 of these
    //  are collected, then shaded and composited back-to-front.
    //  Each checkpoint contributes partial opacity proportional to how
    //  far inside the fuzz radius it reached — thin needles (whose
    //  radius < branch_fuzz) become translucent and ghostly.
    // ================================================================
    vec4  col  = vec4(bcol, 0.0);    // rgb=color accumulator, a=opacity
    float rCoC = branch_fuzz;        // fuzz radius in world units

    float h[4];
    h[0] = 0.0;  h[1] = 0.0;  h[2] = 0.0;  h[3] = 0.0;
    int H = 0;

    float t = 0.05;
    for (int i = 0; i < 70; i++) {
        if (col.w > 0.9 || t > draw_distance) break;
        float d = DE(ro + rd * t);
        if (d < rCoC && H < 4) { h[H] = t;  H++; }
        d *= 0.85 + 0.15 * rand2();            // jitter: fuzz + banding prevention
        t += max(d, rCoC * 0.1);               // minimum step avoids infinite loop
    }

    // ---- Shade checkpoints far→near (back-to-front) ----
    for (int i = 3; i >= 0; i--) {
        if (h[i] == 0.0) continue;

        vec3  p    = ro + rd * h[i];
        float dHit = DE(p);
        vec3  N    = getForestNormal(p, rCoC * 1.2);
        if (dot(N, N) < 0.01) N = -rd;         // fallback: facing camera

        float localY = p.y / TREE_SCALE;        // 0=ground, ~1=canopy

        // ---- Material ----
        // Top-facing surfaces: bright leaf green catches light
        // Side-facing surfaces: deep forest bark
        float topFace  = smoothstep(0.0, 0.7, N.y);
        float isGround = smoothstep(0.12, 0.0, localY) * topFace;

        vec3 barkCol   = vec3(0.06, 0.52, 0.05);   // vivid forest green bark
        vec3 leafCol   = mix(vec3(0.10, 0.65, 0.08),   // vivid mid-green (sides)
                             vec3(0.22, 0.98, 0.08),    // electric bright green (tops)
                             topFace);
        vec3 groundCol = vec3(0.06, 0.52, 0.05);   // vivid bright moss floor
        vec3 scol = mix(mix(barkCol, leafCol, topFace * 0.6),
                        groundCol, isGround);

        // ---- Lighting: purple shadow, bright green sun, warm yellow highlights ----
        float ndotl   = clamp(dot(N, L), 0.0, 1.0);
        float hotspot = smoothstep(0.55, 1.0, ndotl) * (0.4 + topFace * 0.6);
        vec3 sunDiffuse  = scol * vec3(1.05, 0.95, 0.78) * ndotl;
        vec3 purpleFill  = vec3(0.14, 0.02, 0.32) * (1.0 - ndotl);
        vec3 yellowHot   = vec3(0.60, 0.52, 0.02) * hotspot;  // warm yellow on brightest faces
        float spec       = pow(max(dot(reflect(rd, N), L), 0.0), 10.0) * 0.70;
        scol = sunDiffuse + purpleFill + yellowHot + sunCol * spec;

        // ---- Shadow ----
        if (localY < 0.15) {
            // Ground: hard shadow with 22 steps + correct iY for upward rays.
            // Gives solid dark pools around trunks and branch shadow streaks.
            vec3  shadowP = p + vec3(0.0, 0.03, 0.0);   // nudge off flat ground
            float shadow  = groundShadow(shadowP, L);
            scol += vec3(0.08, 0.01, 0.20) * (1.0 - shadow);   // purple tint in shadow
            scol *= 0.15 + shadow * 0.85;                        // very dark under trees
        } else if (i == 0) {
            // Nearest surface (tree/trunk): soft fuzzy shadow
            vec3  shadowP = p + N * max(0.0, -dHit + 0.02);
            float shadow  = FuzzyShadow(shadowP, L, 55.0, rCoC);
            scol += vec3(0.10, 0.01, 0.24) * (1.0 - shadow);
            scol *= 0.40 + shadow * 0.60;
        }

        // ---- Bass: subtle canopy brightness pulse ----
        scol *= 1.0 + syn_BassLevel * bass_reactivity * 0.3;

        // ---- Distance fog → sky color (very gentle — preserve vivid surface colors) ----
        float fogAmt = 1.0 - exp(-h[i] / (draw_distance * 2.8));
        scol = mix(scol, bcol, fogAmt);

        // ---- Back-to-front alpha composite ----
        // alpha: 0 when just at fuzz boundary, 1 when well inside surface
        float alpha = (1.0 - col.w) * linstep(-rCoC, rCoC, -dHit);
        col = mix(col, vec4(scol, min(col.w + alpha, 1.0)), alpha);
    }

    // Composite accumulated surface over sky
    vec3 finalCol = mix(bcol, col.rgb, col.w);

    // ---- Gamma + saturation boost — vivid, punchy, no muddiness ----
    finalCol = pow(max(finalCol, vec3(0.0)), vec3(0.85));
    float lum = dot(finalCol, vec3(0.299, 0.587, 0.114));
    finalCol  = mix(vec3(lum), finalCol, 1.45);   // +45% saturation

    // ---- Vignette ----
    vec2 q = _uv;
    finalCol *= pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.1) * 0.9 + 0.1;

    // ---- Motion blur — temporal accumulation smooths the noise ----
    // Higher motion_blur = smoother frosted texture, softer motion
    vec4 past = texture(syn_FinalPass, _uv);
    finalCol = mix(finalCol, past.rgb, motion_blur);

    return vec4(finalCol, 1.0);
}
