// ============================================================
//  FOREST PLANET — v3.0
//  RBambey
//  Tree SDF technique from "Frosted Forest" by eiffie (CC-BY-NC-SA 3.0).
//  6-DOF flight from Ocean Planet by RBambey.
//
//  Trees: reed-tube SDFs with 3 levels of fractal branching (KIFS).
//         Per-tile hashes give each tree unique branching depth, tier
//         height, and canopy splay. Wind sway scales with height.
//  Render: solid opaque single-hit raymarching. No transparency.
// ============================================================

const float TREE_SCALE = 8.0;

const vec3 SUN_DIR = vec3(0.578, 0.180, 0.796);
const vec3 SUN_COL = vec3(1.0, 0.82, 0.52);

const float HIT_EPS  = 0.04;   // surface hit threshold (world units)
const float NORM_EPS = 0.05;   // normal finite-difference step

// ---- Tree primitive ----------------------------------------------------

// Tapered cylinder capped with a hemisphere at the tip
float reed(vec3 p, float dr) {
    float cone = max(length(p.xz) - 0.02 + p.y * 0.02,
                     abs(p.y - 0.5) - 0.5);
    float cap  = length(p - vec3(0.0, 1.0, 0.0)) - 0.008 * dr;
    return min(cone, cap) / dr;
}

// ---- Scene SDF ---------------------------------------------------------

float DE(vec3 p0) {
    vec3  p  = p0 / TREE_SCALE;

    float tx = floor(p.x * 0.5);
    float tz = floor(p.z * 0.5);
    float h1 = fract(sin(tx * 127.1  + tz * 311.7 ) * 43758.5453);
    float h2 = fract(sin(tx * 269.5  + tz *  83.3 ) * 43758.5453);
    float h3 = fract(sin(tx *  12.9  + tz *  78.23) * 43758.5453);
    float h4 = fract(sin(tx * 173.6  + tz * 153.9 ) * 43758.5453);

    float rnd    = tree_density - 0.5 + h1 * 2.5;
    float yStep  = 0.26 + h2 * 0.38;
    float splay  = 0.10 + h3 * 0.44;
    float hScale = h4 > 0.5 ? 0.5 : 1.0;

    float dy = wind_strength * 0.2 * clamp(p.y + 0.4, 0.0, 1.0);
    p += sin(p.zxy + 2.0 * sin(p.yzx)) * dy;

    float dg = p.y;
    float d  = 100.0, dr = 1.0;

    p.y  *= hScale;
    p.xz  = mod(p.xz, 2.0) - 1.0;
    p.xz  = abs(p.xz);
    { float sy = clamp(p.y, -1.0, 1.0); p.xz -= sy * sy * splay; }
    d     = reed(p, dr);

    for (int i = 0; i < 3; i++) {
        if (float(i) > rnd) break;
        p.y  -= yStep;
        p    *= 2.0;  dr *= 2.0;
        p.xz  = abs(vec2(p.x + p.z, p.x - p.z)) * 0.707;
        { float sy = clamp(p.y, -1.0, 1.0); p.xz -= sy * sy * splay; }
        d     = min(d, reed(p, dr));
    }

    return min(dg * TREE_SCALE,
               d * (1.0 - 0.5 * dy) * TREE_SCALE);
}

// ---- Normal (tetrahedron finite differences) ---------------------------

vec3 getNormal(vec3 p) {
    const vec2 k = vec2(1.0, -1.0);
    return normalize(
        k.xyy * DE(p + k.xyy * NORM_EPS) +
        k.yyx * DE(p + k.yyx * NORM_EPS) +
        k.yxy * DE(p + k.yxy * NORM_EPS) +
        k.xxx * DE(p + k.xxx * NORM_EPS)
    );
}

// ---- Shadow (soft penumbra, standard Quilez method) --------------------

float shadow(vec3 ro, vec3 rd, float maxDist) {
    float t = 0.05, s = 1.0;
    for (int i = 0; i < 32; i++) {
        if (t > maxDist || s < 0.01) break;
        float d = DE(ro + rd * t);
        if (d < -0.01) { s = 0.0; break; }
        s = min(s, 8.0 * d / t);
        t += d * 0.8;
    }
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

vec3 forestSky(vec3 rd, float sunDot) {
    float y   = clamp(rd.y, 0.0, 1.0);
    vec3  sky = mix(vec3(0.08, 0.22, 0.80), vec3(0.03, 0.08, 0.88), pow(y, 0.55));
    sky = mix(sky, vec3(0.72, 0.60, 0.22), exp(-abs(rd.y) * 8.0) * 0.20);

    if (rd.y > 0.12) {
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

    float sunDisc = smoothstep(0.9994, 0.9998, sunDot);
    float sunGlow = pow(max(sunDot, 0.0), 64.0) * 0.40
                  + pow(max(sunDot, 0.0), 10.0) * 0.08;
    sky += SUN_COL * (sunDisc * 2.5 + sunGlow);

    return sky;
}

// ---- Main --------------------------------------------------------------

vec4 renderMain() {

    // Camera basis (6-DOF, driven by script.js via setUniform)
    vec3 ro = vec3(cam_x, cam_y, cam_z);
    vec2 sc = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd = normalize(vec3(cam_fx, cam_fy, cam_fz)
                      + vec3(cam_rx, cam_ry, cam_rz) * sc.x
                      + vec3(cam_ux, cam_uy, cam_uz) * sc.y);

    float sunDot = dot(rd, SUN_DIR);
    vec3  bcol   = forestSky(rd, sunDot);

    // ---- Ray march: find nearest surface ----
    float hitT = -1.0;
    float t    = 0.05;
    for (int i = 0; i < 220; i++) {
        if (t > draw_distance) break;
        float d = DE(ro + rd * t);
        if (d < HIT_EPS && d > -HIT_EPS * 0.5) { hitT = t;  break; }
        t += max(abs(d) * 0.75, HIT_EPS * 0.15);
    }

    // ---- No hit: return sky ----
    vec3 scol = bcol;

    if (hitT >= 0.0) {

        // ---- Shade hit point ----
        vec3  p    = ro + rd * hitT;
        float dHit = DE(p);
        vec3  N    = getNormal(p);
        if (dot(N, N) < 0.01) N = -rd;

        float localY   = p.y / TREE_SCALE;
        float topFace  = smoothstep(0.0, 0.7, N.y);
        float isGround = smoothstep(0.12, 0.0, localY) * topFace;

        // Material: bark / leaves / ground moss
        vec3 baseCol = mix(
            mix(vec3(0.06, 0.52, 0.05),
                mix(vec3(0.10, 0.65, 0.08), vec3(0.22, 0.98, 0.08), topFace),
                topFace * 0.6),
            vec3(0.06, 0.52, 0.05),
            isGround);

        // Lighting: ambient + sun + hotspot + specular
        float ndotl   = clamp(dot(N, SUN_DIR), 0.0, 1.0);
        float hotspot = smoothstep(0.55, 1.0, ndotl) * (0.4 + topFace * 0.6);
        vec3  ambient = vec3(0.03, 0.08, 0.02)
                      + vec3(0.03, 0.10, 0.02) * (dot(N, SUN_DIR) * 0.5 + 0.5);
        vec3  sun     = baseCol * SUN_COL * ndotl * 2.8;
        vec3  hot     = vec3(0.90, 0.78, 0.05) * hotspot * 2.5;
        vec3  spec    = SUN_COL * pow(max(dot(reflect(rd, N), SUN_DIR), 0.0), 10.0) * 0.50;
        scol          = baseCol * ambient + sun + hot + spec;

        // Shadow — ground gets deeper pools, canopy gets lighter penumbra
        float shad      = shadow(p + N * 0.05, SUN_DIR, 55.0);
        float shadowAmt = localY < 0.15 ? 0.10 : 0.25;
        vec3  shadowCol = baseCol * ambient * shadowAmt + vec3(0.05, 0.0, 0.10);
        scol = mix(shadowCol, scol, shad);

        scol *= 1.0 + syn_BassLevel * bass_reactivity * 0.3;
        scol  = mix(scol, vec3(0.06, 0.36, 0.08), 1.0 - exp(-hitT / (draw_distance * 2.5)));
    }

    // Post-process: gamma, saturation, vignette
    vec3 finalCol = pow(max(scol, vec3(0.0)), vec3(0.72));
    finalCol = mix(vec3(dot(finalCol, vec3(0.299, 0.587, 0.114))), finalCol, 1.45);
    finalCol *= pow(16.0 * _uv.x * _uv.y * (1.0 - _uv.x) * (1.0 - _uv.y), 0.1) * 0.9 + 0.1;

    return vec4(finalCol, 1.0);
}
