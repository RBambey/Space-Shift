// ============================================================
//  REMNANT PLANET — v1.0
//  RBambey
//  Mandelbox fractal by David Hoskins (CC-BY-NC-SA 3.0).
//  https://www.shadertoy.com/view/XljGDz
//  6-DOF flight from Ocean Planet by RBambey.
//
//  Mandelbox SDF with 9-iteration folding, orbit-trap colouring,
//  soft shadows, and a moving spotlight that orbits the camera.
//  Anti-aliasing via 4 neighbouring surface shading samples.
//  Temporal accumulation smooths noise between frames.
// ============================================================

#define SCALE     2.8
#define MINRAD2   0.25

float minRad2              = clamp(MINRAD2, 1.0e-9, 1.0);
float absScalem1           = abs(SCALE - 1.0);
float AbsScaleRaisedTo1mIters = pow(abs(SCALE), float(1 - 10));
vec4  mboxScale            = vec4(SCALE, SCALE, SCALE, abs(SCALE)) / minRad2;

// Tile the world into [-2, 2] cells with period 4 — infinite Mandelbox copies
vec3 tile(vec3 pos) {
    return mod(pos + 2.0, 4.0) - 2.0;
}

// Surface orbit-trap colours — modified per-pixel inside Colour()
vec3 surfaceCol1 = vec3(0.80, 0.00, 0.00);  // deep red base
vec3 surfaceCol2 = vec3(0.40, 0.40, 0.50);  // grey-blue mid
vec3 surfaceCol3 = vec3(0.50, 0.30, 0.00);  // amber edge

const vec3 SUN_DIR    = normalize(vec3(0.35, 0.10, 0.30));
const vec3 SUN_COLOUR = vec3(1.00, 0.95, 0.80);

// ---- Procedural 3D noise (replaces iChannel0 texture) ------

float noiseHash(vec3 p) {
    p  = fract(p * vec3(127.1, 311.7, 74.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y * p.z);
}

float procNoise(vec3 x) {
    vec3 i = floor(x), f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(noiseHash(i),               noiseHash(i + vec3(1,0,0)), f.x),
            mix(noiseHash(i + vec3(0,1,0)), noiseHash(i + vec3(1,1,0)), f.x), f.y),
        mix(mix(noiseHash(i + vec3(0,0,1)), noiseHash(i + vec3(1,0,1)), f.x),
            mix(noiseHash(i + vec3(0,1,1)), noiseHash(i + vec3(1,1,1)), f.x), f.y),
        f.z);
}

// ---- Mandelbox SDF -----------------------------------------
// 9 iterations of sphere-fold + box-fold. Distance estimate
// stored in p.w (DE standard technique for IFS fractals).

float Map(vec3 pos) {
    vec3  tp = tile(pos);              // fold into nearest tile cell [-2, 2]
    vec4  p  = vec4(tp, 1.0), p0 = p;
    for (int i = 0; i < 9; i++) {
        p.xyz  = clamp(p.xyz, -1.0, 1.0) * 2.0 - p.xyz;
        float r2 = dot(p.xyz, p.xyz);
        p     *= clamp(max(minRad2 / r2, minRad2), 0.0, 1.0);
        p      = p * mboxScale + p0;
    }
    return (length(p.xyz) - absScalem1) / p.w - AbsScaleRaisedTo1mIters;
}

// ---- Surface colour (orbit trap) ---------------------------
// c.x = log final distance (detail lines), c.y = closest orbit approach.
// Pulsing neon seam driven by TIME and colour_speed control.

vec3 Colour(vec3 pos) {
    vec3  tp = tile(pos);              // fold into nearest tile cell [-2, 2]
    vec3  p  = tp, p0 = tp;
    float trap = 1.0;
    for (int i = 0; i < 6; i++) {
        p.xyz  = clamp(p.xyz, -1.0, 1.0) * 2.0 - p.xyz;
        float r2 = dot(p.xyz, p.xyz);
        p     *= clamp(max(minRad2 / r2, minRad2), 0.0, 1.0);
        p      = p * mboxScale.xyz + p0.xyz;
        trap   = min(trap, r2);
    }
    vec2 c = clamp(vec2(0.3333 * log(dot(p, p)) - 1.0, sqrt(trap)), 0.0, 1.0);

    // Neon pulse: bright teal seam travelling outward from origin
    float pulse = mod(length(pos) - TIME * 1.5 * colour_speed, 16.0);
    float seam  = pow(smoothstep(0.0, 0.3, pulse) * smoothstep(0.6, 0.3, pulse), 10.0);
    vec3  s1    = mix(surfaceCol1, vec3(0.4, 3.0, 5.0), seam);

    return mix(mix(s1, surfaceCol2, c.y), surfaceCol3, c.x);
}

// ---- Normal (forward differences, 6 Map calls) -------------

vec3 GetNormal(vec3 pos, float dist) {
    float eps = dist * 0.0011;
    vec2  e   = vec2(eps, 0.0);
    return normalize(vec3(
        Map(pos + e.xyy) - Map(pos - e.xyy),
        Map(pos + e.yxy) - Map(pos - e.yxy),
        Map(pos + e.yyx) - Map(pos - e.yyx)));
}

// ---- Procedural sky ----------------------------------------

float GetSky(vec3 dir) {
    dir *= 2.3;
    float t = procNoise(dir);
    t += procNoise(dir * 2.1) * 0.50;
    t += procNoise(dir * 4.3) * 0.25;
    t += procNoise(dir * 7.9) * 0.125;
    return t;
}

// ---- Soft shadow (8 steps) ---------------------------------

float Shadow(vec3 ro, vec3 rd) {
    float res = 1.0, t = 0.05;
    for (int i = 0; i < 8; i++) {
        float h = Map(ro + rd * t);
        res = min(6.0 * h / t, res);
        t  += h;
    }
    return max(res, 0.0);
}

// ---- Binary subdivison refinement (6 bisects) --------------

float BinarySubdivision(vec3 rO, vec3 rD, vec2 t) {
    float hw;
    for (int i = 0; i < 6; i++) {
        hw  = dot(t, vec2(0.5));
        float d = Map(rO + hw * rD);
        t   = mix(vec2(t.x, hw), vec2(hw, t.y), step(0.0005, d));
    }
    return hw;
}

// ---- Primary ray march (100 steps, max t = 12) -------------

vec2 Scene(vec3 rO, vec3 rD, float jitter) {
    float t    = 0.05 + 0.05 * jitter;
    float oldT = 0.0, glow = 0.0;
    bool  hit  = false;
    vec2  dist;
    for (int j = 0; j < 100; j++) {
        if (t > 20.0) break;
        float h = Map(rO + t * rD);
        if (h < 0.0005) { dist = vec2(oldT, t);  hit = true;  break; }
        glow += clamp(0.05 - h, 0.0, 0.4);
        oldT  = t;
        t    += h + t * 0.001;
    }
    if (!hit) t = 1000.0;
    else      t = BinarySubdivision(rO, rD, dist);
    return vec2(t, clamp(glow * 0.25, 0.0, 1.0));
}

// ---- Spotlight lens flare ----------------------------------

vec3 LightSource(vec3 toSpot, vec3 rd, float hitDist) {
    if (length(toSpot) >= hitDist) return vec3(0.0);
    float a = max(dot(normalize(toSpot), rd), 0.0);
    float g = pow(a, 500.0) + pow(a, 5000.0) * 0.2;
    return vec3(1.0, 0.18, 0.04) * g;   // hot red-orange ember
}

// ---- Post effects ------------------------------------------

vec3 PostEffects(vec3 rgb, vec2 xy) {
    // Contrast + saturation + brightness
    rgb = mix(vec3(0.5),
              mix(vec3(dot(vec3(0.2125, 0.7154, 0.0721), rgb * 1.5)),
                  rgb * 1.5, 1.5),
              1.08);
    // Vignette
    rgb *= 0.5 + 0.5 * pow(20.0 * xy.x * xy.y * (1.0 - xy.x) * (1.0 - xy.y), 0.2);
    // Gamma (display-correct 2.2)
    return pow(max(rgb, vec3(0.0)), vec3(1.0 / 2.2));
}

// ---- Shading at surface point p ----------------------------

vec3 renderColour(vec3 p, vec2 ret, vec3 rd, vec3 spotLight, vec3 cw) {
    vec3  nor     = GetNormal(p, ret.x);
    vec3  spot    = spotLight - p;
    float atten   = length(spot);
    spot /= atten;

    float shaSpot = Shadow(p, spot);
    float shaSun  = Shadow(p, SUN_DIR);
    float bri     = max(dot(spot,    nor), 0.0) / pow(atten, 1.5) * 0.25;
    float briSun  = max(dot(SUN_DIR, nor), 0.0) * 0.20;

    // Cache surface colour — Colour() has a global side effect so call it once
    vec3  surf = Colour(p);
    vec3  col  = surf * bri * shaSpot + surf * briSun * shaSun;

    vec3 ref = reflect(rd, nor);
    col += pow(max(dot(spot,    ref), 0.0), 10.0) * 2.0 * shaSpot * bri;
    col += pow(max(dot(SUN_DIR, ref), 0.0), 10.0) * 2.0 * shaSun  * briSun;

    // Camera headlight — directional from camera forward, no falloff, no shadow.
    // Ensures surfaces directly in view are never completely dark.
    float briHead = max(dot(cw, nor), 0.0) * 0.18;
    col += surf * briHead;

    // Bass pulse
    col *= 1.0 + syn_BassLevel * bass_reactivity * 0.5;
    return col;
}

// ---- Main --------------------------------------------------

vec4 renderMain() {
    // Camera basis from script.js uniforms (6-DOF flight)
    vec3 ro = vec3(cam_x, cam_y, cam_z);
    vec2 sc  = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 cu  = vec3(cam_rx, cam_ry, cam_rz);   // right
    vec3 cv  = vec3(cam_ux, cam_uy, cam_uz);   // up
    vec3 cw  = vec3(cam_fx, cam_fy, cam_fz);   // forward
    vec3 rd  = normalize(sc.x * cu + sc.y * cv + 1.3 * cw);

    // Spotlight drifts slowly ahead of the camera on a wide lazy orbit
    vec3 spotLight = ro + cw * 1.5
                   + vec3(sin(TIME * 0.73),
                          cos(TIME * 0.51),
                          sin(TIME * 0.89)) * 1.20;

    // Sky: dark void with subtle procedural variation
    vec3 sky = vec3(0.03, 0.04, 0.05) * GetSky(rd);

    // Per-pixel jitter on initial step (reduces banding)
    float jitter = fract(sin(dot(_uv * RENDERSIZE, vec2(12.9898, 78.233))) * 43758.5453);
    vec2  ret    = Scene(ro, rd, jitter);

    vec3 col = vec3(0.0);
    if (ret.x < 900.0) {
        vec3 p = ro + ret.x * rd;
        col    = renderColour(p, ret, rd, spotLight, cw);

        // AA: shade 4 nearby surface positions using camera axes, average all 5.
        // Smooths fractal edges without extra ray marches.
        vec2 a = ret.x * (1.0 / RENDERSIZE.xy) * 2.0;
        col   += renderColour(p + cu * a.x, ret, rd, spotLight, cw);
        col   += renderColour(p - cu * a.x, ret, rd, spotLight, cw);
        col   += renderColour(p + cv * a.y, ret, rd, spotLight, cw);
        col   += renderColour(p - cv * a.y, ret, rd, spotLight, cw);
        col   *= 0.2;
    }

    // Fog into void + glow halo from fractal
    col  = mix(sky, col, min(exp(-ret.x * 0.15), 1.0));
    col += pow(abs(ret.y), 2.5) * vec3(0.01, 0.00, 0.03);

    // Spotlight lens flare
    col += LightSource(spotLight - ro, rd, ret.x);

    col  = PostEffects(col, _uv);

    // Temporal accumulation
    col  = mix(col, texture(syn_FinalPass, _uv).rgb, motion_blur);

    return vec4(col, 1.0);
}
