// ============================================================
//  OCEAN SUNSET — v1.0
//  Created by RBambey
//  Ocean shader based on "Seascape" by Alexander Alekseev (TDM)
//  https://www.shadertoy.com/view/Ms2SD1
//  Flying controls from FlyingSynth by RBambey
// ============================================================

// ---- Ocean globals (set each frame in renderMain before use) ----
float g_seaHeight;
float g_seaChoppy;
float g_seaFreq;
float g_seaTime;
mat2  octave_m = mat2(1.6, 1.2, -1.2, 1.6);

const int   NUM_STEPS    = 8;
const int   ITER_GEOMETRY = 3;
const int   ITER_FRAGMENT = 5;
const vec3  SEA_BASE     = vec3(0.02, 0.07, 0.18);
const vec3  SEA_WATER_COLOR = vec3(0.38, 0.22, 0.08);

// ---- Noise ----
float hash(vec2 p) {
    float h = dot(p, vec2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

float noise(in vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return -1.0 + 2.0 * mix(
        mix(hash(i + vec2(0.0,0.0)), hash(i + vec2(1.0,0.0)), u.x),
        mix(hash(i + vec2(0.0,1.0)), hash(i + vec2(1.0,1.0)), u.x),
        u.y);
}

// ---- Ocean wave octave ----
float sea_octave(vec2 uv, float choppy) {
    uv += noise(uv);
    vec2 wv  = 1.0 - abs(sin(uv));
    vec2 swv = abs(cos(uv));
    wv = mix(wv, swv, wv);
    return pow(1.0 - pow(wv.x * wv.y, 0.65), choppy);
}

// ---- Bass ripple — expanding ring from camera position ----
// Returns a 0..1 amplitude boost at world XZ position xz.
// The ring travels outward driven by syn_BassTime so it naturally
// follows bass energy rather than spiking all waves at once.
float bassRippleAt(vec2 xz) {
    float dist = length(xz - vec2(cam_x, cam_z));
    float ring = sin(dist * 0.4 - syn_BassTime * 7.0);
    ring = pow(clamp(ring * 0.5 + 0.5, 0.0, 1.0), 3.0);
    return ring * syn_BassLevel;
}

// ---- Height map (coarse — geometry pass) ----
float map(vec3 p) {
    float freq   = g_seaFreq;
    float amp    = g_seaHeight + bassRippleAt(p.xz) * wave_height * 2.5;
    float choppy = g_seaChoppy;
    vec2  uv = p.xz; uv.x *= 0.75;
    float d, h = 0.0;
    for (int i = 0; i < ITER_GEOMETRY; i++) {
        d  = sea_octave((uv + g_seaTime) * freq, choppy);
        d += sea_octave((uv - g_seaTime) * freq, choppy);
        h += d * amp;
        uv *= octave_m; freq *= 1.9; amp *= 0.22;
        choppy = mix(choppy, 1.0, 0.2);
    }
    return p.y - h;
}

// ---- Height map (detailed — shading pass) ----
float map_detailed(vec3 p) {
    float freq   = g_seaFreq;
    float amp    = g_seaHeight + bassRippleAt(p.xz) * wave_height * 2.5;
    float choppy = g_seaChoppy;
    vec2  uv = p.xz; uv.x *= 0.75;
    float d, h = 0.0;
    for (int i = 0; i < ITER_FRAGMENT; i++) {
        d  = sea_octave((uv + g_seaTime) * freq, choppy);
        d += sea_octave((uv - g_seaTime) * freq, choppy);
        h += d * amp;
        uv *= octave_m; freq *= 1.9; amp *= 0.22;
        choppy = mix(choppy, 1.0, 0.2);
    }
    return p.y - h;
}

// ---- Surface normal (finite differences) ----
vec3 getNormal(vec3 p, float eps) {
    vec3 n;
    n.y = map_detailed(p);
    n.x = map_detailed(vec3(p.x + eps, p.y, p.z)) - n.y;
    n.z = map_detailed(vec3(p.x, p.y, p.z + eps)) - n.y;
    n.y = eps;
    return normalize(n);
}

// ---- Ray-ocean intersection (8-step bisection) ----
float heightMapTracing(vec3 ori, vec3 dir, out vec3 p) {
    float tm   = 0.0;
    float tx   = 1000.0;
    float hx   = map(ori + dir * tx);
    if (hx > 0.0) { p = ori + dir * tx; return tx; }
    float hm   = map(ori + dir * tm);
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

// ---- Lighting helpers ----
float diffuse(vec3 n, vec3 l, float p) {
    return pow(dot(n, l) * 0.4 + 0.6, p);
}
float specular(vec3 n, vec3 l, vec3 e, float s) {
    float nrm = (s + 8.0) / (PI * 8.0);
    return pow(max(dot(reflect(e, n), l), 0.0), s) * nrm;
}

// ---- Sky — blends dawn / midday / dusk via sky_time (0/0.5/1) ----
// Helper: blend three values at t=0, t=0.5, t=1
vec3 blend3(vec3 a, vec3 b, vec3 c, float t) {
    return mix(mix(a, b, clamp(t * 2.0, 0.0, 1.0)),
                    c, clamp(t * 2.0 - 1.0, 0.0, 1.0));
}

vec3 skyColor(vec3 rd, vec3 sunDir, vec3 sunCol) {
    float y = clamp(rd.y, 0.0, 1.0);

    // Per-time zenith / mid / horizon colours
    vec3 zenith  = blend3(vec3(0.30, 0.28, 0.55),   // dawn  — soft lavender
                          vec3(0.10, 0.32, 0.78),   // midday — rich blue
                          vec3(0.05, 0.02, 0.18),   // dusk  — deep indigo
                          sky_time);
    vec3 mid     = blend3(vec3(0.90, 0.42, 0.38),   // dawn  — coral pink
                          vec3(0.28, 0.52, 0.88),   // midday — sky blue
                          vec3(0.55, 0.12, 0.08),   // dusk  — rich red
                          sky_time);
    vec3 horizon = blend3(vec3(1.00, 0.72, 0.55),   // dawn  — peach gold
                          vec3(0.68, 0.84, 1.00),   // midday — pale blue
                          vec3(1.00, 0.55, 0.10),   // dusk  — amber
                          sky_time);
    vec3 haze    = blend3(vec3(1.00, 0.60, 0.45),   // dawn
                          vec3(0.80, 0.90, 1.00),   // midday
                          vec3(1.00, 0.45, 0.10),   // dusk
                          sky_time);

    float hBlend = pow(1.0 - y, 2.5);
    vec3 sky = mix(mix(zenith, mid, pow(1.0 - y, 1.2)), horizon, hBlend);

    // Horizon haze
    sky += haze * exp(-abs(rd.y) * 5.0) * 0.35;

    // Sun disc + glow — disc shrinks as sun rises (midday = tighter, brighter)
    float sunH    = sunDir.y;                          // 0 = horizon, 1 = overhead
    float discEdge = mix(0.9988, 0.9995, sunH);        // wider disc when low
    float sunDot  = dot(rd, sunDir);
    float sunDisc = smoothstep(discEdge, discEdge + 0.0006, sunDot);
    float sunGlow = pow(max(sunDot, 0.0), mix(32.0, 128.0, sunH)) * 0.8;
    sky += sunCol * sunDisc * mix(3.0, 5.0, sunH);
    sky += sunCol * sunGlow;

    return sky;
}

// ---- Ocean shading ----
vec3 getSeaColor(vec3 p, vec3 n, vec3 l, vec3 eye, vec3 dist, vec3 sunDir, vec3 sunCol) {
    float fresnel   = 1.0 - max(dot(n, -eye), 0.0);
    fresnel         = pow(fresnel, 3.0) * 0.65;

    vec3 reflected  = skyColor(reflect(eye, n), sunDir, sunCol);
    vec3 refracted  = SEA_BASE + diffuse(n, l, 80.0) * SEA_WATER_COLOR * 0.12;
    vec3 color      = mix(refracted, reflected, fresnel);

    float atten = max(1.0 - dot(dist, dist) * 0.001, 0.0);
    color += SEA_WATER_COLOR * (p.y - g_seaHeight) * 0.18 * atten;

    // Specular glitter tinted to match sun colour
    color += sunCol * specular(n, l, eye, 60.0);

    return color;
}

// ================================================================
vec4 renderMain() {

    // --- Set ocean parameters for this frame ---
    g_seaHeight     = wave_height;
    g_seaChoppy     = sea_choppiness;
    g_seaFreq       = 0.16;
    g_seaTime       = TIME * sea_speed * 0.8;

    // --- Camera ---
    vec3 ro     = vec3(cam_x, cam_y, cam_z);
    vec3 cRight = vec3(cam_rx, cam_ry, cam_rz);
    vec3 cUp    = vec3(cam_ux, cam_uy, cam_uz);
    vec3 cFwd   = vec3(cam_fx, cam_fy, cam_fz);
    vec2 uv  = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd  = normalize(cFwd + cRight * uv.x + cUp * uv.y);

    // Sun: low on left at dawn, overhead at midday, low on right at dusk
    vec3 sunDir = normalize(blend3(vec3(-0.5, 0.10, 0.9),
                                   vec3( 0.1, 1.00, 0.3),
                                   vec3( 0.3, 0.08, 1.0),
                                   sky_time));
    vec3 sunCol = blend3(vec3(1.0, 0.80, 0.65),   // dawn  — soft pink-white
                         vec3(1.0, 0.98, 0.88),   // midday — near white
                         vec3(1.0, 0.75, 0.30),   // dusk  — warm gold
                         sky_time);

    // --- Sky layer ---
    vec3 skyCol = skyColor(rd, sunDir, sunCol);

    // --- Ocean trace (only for rays that point downward) ---
    if (rd.y >= -0.001) {
        return vec4(skyCol, 1.0);
    }

    vec3  p;
    float t    = heightMapTracing(ro, rd, p);
    vec3  dist = p - ro;

    float epsNrm = dot(dist, dist) * (0.1 / RENDERSIZE.x);
    vec3  n      = getNormal(p, epsNrm);

    vec3 seaCol = getSeaColor(p, n, sunDir, rd, dist, sunDir, sunCol);

    // Fog: blend toward the horizon sky colour at distance
    vec3  horizonDir = normalize(vec3(rd.x, 0.0, rd.z));
    vec3  fogCol     = skyColor(horizonDir, sunDir, sunCol);
    float fog        = exp(-t * (3.0 / draw_distance));
    vec3  col        = mix(fogCol, seaCol, fog);

    // Gamma correction (match Seascape's 0.75 gamma)
    col = pow(max(col, vec3(0.0)), vec3(0.75));

    return vec4(col, 1.0);
}
