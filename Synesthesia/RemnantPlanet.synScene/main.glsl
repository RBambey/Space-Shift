// ============================================================
//  REMNANT PLANET — v1.1
//  RBambey
//  Mandelbox fractal by David Hoskins (CC-BY-NC-SA 3.0).
//  https://www.shadertoy.com/view/XljGDz
//  6-DOF flight from Ocean Planet by RBambey.
//
//  Mandelbox SDF with orbit-trap colouring, soft shadows,
//  and a moving spotlight that orbits the camera.
//  Temporal accumulation smooths edges between frames.
// ============================================================

#define SCALE       2.8
#define MINRAD2     0.25
#define WORLD_SCALE 0.55  // < 1 zooms into the fractal — wider tunnels, more open spaces

float minRad2                 = clamp(MINRAD2, 1.0e-9, 1.0);
float absScalem1              = abs(SCALE - 1.0);
float AbsScaleRaisedTo1mIters = pow(abs(SCALE), float(1 - 10));
vec4  mboxScale               = vec4(SCALE, SCALE, SCALE, abs(SCALE)) / minRad2;

vec3 tile(vec3 pos) {
    return mod(pos * WORLD_SCALE + 3.5, 7.0) - 3.5;
}

vec3 surfaceCol1 = vec3(0.80, 0.00, 0.00);  // deep red base
vec3 surfaceCol2 = vec3(0.40, 0.40, 0.50);  // grey-blue mid
vec3 surfaceCol3 = vec3(0.50, 0.30, 0.00);  // amber edge

const vec3 SUN_DIR  = normalize(vec3( 0.35,  0.10,  0.30));
const vec3 SUN_DIR2 = normalize(vec3(-0.35, -0.10, -0.30));  // opposite fill light

// ---- Procedural 3D noise ----

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

// ---- Mandelbox SDF (7 iterations) ----

float Map(vec3 pos) {
    vec3 tp = tile(pos);
    vec4 p  = vec4(tp, 1.0), p0 = p;
    for (int i = 0; i < 7; i++) {
        p.xyz  = clamp(p.xyz, -1.0, 1.0) * 2.0 - p.xyz;
        float r2 = dot(p.xyz, p.xyz);
        p     *= clamp(max(minRad2 / r2, minRad2), 0.0, 1.0);
        p      = p * mboxScale + p0;
    }
    return ((length(p.xyz) - absScalem1) / p.w - AbsScaleRaisedTo1mIters) / WORLD_SCALE;
}

// ---- Surface colour (orbit trap, 5 iterations) ----

vec3 Colour(vec3 pos) {
    vec3  tp = tile(pos);
    vec3  p  = tp, p0 = tp;
    float trap = 1.0;
    for (int i = 0; i < 5; i++) {
        p.xyz  = clamp(p.xyz, -1.0, 1.0) * 2.0 - p.xyz;
        float r2 = dot(p.xyz, p.xyz);
        p     *= clamp(max(minRad2 / r2, minRad2), 0.0, 1.0);
        p      = p * mboxScale.xyz + p0.xyz;
        trap   = min(trap, r2);
    }
    vec2 c = clamp(vec2(0.3333 * log(dot(p, p)) - 1.0, sqrt(trap)), 0.0, 1.0);

    // Teal seam — travels outward on bass hit via syn_BassTime
    float pulse = mod(length(pos) - syn_BassTime * colour_speed * 2.0, 16.0);
    float seam  = pow(smoothstep(0.0, 0.3, pulse) * smoothstep(0.6, 0.3, pulse), 10.0);
    vec3  s1    = mix(surfaceCol1, vec3(0.4, 3.0, 5.0), seam);

    vec3 col = mix(mix(s1, surfaceCol2, c.y), surfaceCol3, c.x);

    // Sharp saturation burst on bass hit
    float bassHit = pow(syn_BassLevel, 2.0);
    vec3  lum     = vec3(dot(col, vec3(0.2126, 0.7152, 0.0722)));
    return mix(col, mix(lum, col, 5.0), bassHit);
}

// ---- Normal (finite differences) ----

vec3 GetNormal(vec3 pos, float dist) {
    float eps = dist * 0.0011;
    vec2  e   = vec2(eps, 0.0);
    return normalize(vec3(
        Map(pos + e.xyy) - Map(pos - e.xyy),
        Map(pos + e.yxy) - Map(pos - e.yxy),
        Map(pos + e.yyx) - Map(pos - e.yyx)));
}

// ---- Procedural sky (3 octaves) ----

float GetSky(vec3 dir) {
    dir *= 2.3;
    float t = procNoise(dir);
    t += procNoise(dir * 2.1) * 0.50;
    t += procNoise(dir * 4.3) * 0.25;
    return t;
}

// ---- Soft shadow (6 steps) ----

float Shadow(vec3 ro, vec3 rd) {
    float res = 1.0, t = 0.05;
    for (int i = 0; i < 6; i++) {
        float h = Map(ro + rd * t);
        res = min(6.0 * h / t, res);
        t  += h;
    }
    return max(res, 0.0);
}

// ---- Binary subdivision refinement (4 bisects) ----

float BinarySubdivision(vec3 rO, vec3 rD, vec2 t) {
    float hw;
    for (int i = 0; i < 4; i++) {
        hw        = dot(t, vec2(0.5));
        float d   = Map(rO + hw * rD);
        t         = mix(vec2(t.x, hw), vec2(hw, t.y), step(0.0005, d));
    }
    return hw;
}

// ---- Primary ray march (80 steps) ----

vec2 Scene(vec3 rO, vec3 rD, float jitter) {
    float t    = 0.05 + 0.05 * jitter;
    float oldT = 0.0, glow = 0.0;
    bool  hit  = false;
    vec2  dist;
    for (int j = 0; j < 80; j++) {
        if (t > 20.0) break;
        float h = Map(rO + t * rD);
        if (h < 0.0005) { dist = vec2(oldT, t); hit = true; break; }
        glow += clamp(0.05 - h, 0.0, 0.4);
        oldT  = t;
        t    += h + t * 0.001;
    }
    if (!hit) t = 1000.0;
    else      t = BinarySubdivision(rO, rD, dist);
    return vec2(t, clamp(glow * 0.25, 0.0, 1.0));
}

// ---- Spotlight lens flare ----

vec3 LightSource(vec3 toSpot, vec3 rd, float hitDist) {
    if (length(toSpot) >= hitDist) return vec3(0.0);
    float a = max(dot(normalize(toSpot), rd), 0.0);
    float g = pow(a, 500.0) + pow(a, 5000.0) * 0.2;
    return vec3(1.0, 0.18, 0.04) * g;
}

// ---- Post effects ----

vec3 PostEffects(vec3 rgb, vec2 xy) {
    rgb = mix(vec3(0.5),
              mix(vec3(dot(vec3(0.2125, 0.7154, 0.0721), rgb * 2.0)),
                  rgb * 2.0, 1.7),
              1.1);
    rgb *= 0.5 + 0.5 * pow(20.0 * xy.x * xy.y * (1.0 - xy.x) * (1.0 - xy.y), 0.2);
    return pow(max(rgb, vec3(0.0)), vec3(1.0 / 2.2));
}

// ---- Surface shading ----

vec3 renderColour(vec3 p, vec2 ret, vec3 rd, vec3 spotLight) {
    vec3  nor   = GetNormal(p, ret.x);
    vec3  spot  = spotLight - p;
    float atten = length(spot);
    spot /= atten;

    float shaSpot = Shadow(p, spot);
    float shaSun  = Shadow(p, SUN_DIR);
    float bri     = max(dot(spot,     nor), 0.0) / pow(atten, 1.5) * 0.45;
    float briSun  = max(dot(SUN_DIR,  nor), 0.0) * 0.40;
    float briSun2 = max(dot(SUN_DIR2, nor), 0.0) * 0.12;  // fill — no shadow

    vec3 surf = Colour(p);
    vec3 col  = surf * bri * shaSpot + surf * briSun * shaSun + surf * briSun2;

    vec3 ref = reflect(rd, nor);
    col += pow(max(dot(spot,     ref), 0.0), 10.0) * 4.0 * shaSpot * bri;
    col += pow(max(dot(SUN_DIR,  ref), 0.0), 10.0) * 4.0 * shaSun  * briSun;
    col += pow(max(dot(SUN_DIR2, ref), 0.0), 10.0) * 4.0 * briSun2;

    col *= 1.0 + syn_BassLevel * bass_reactivity * 0.5;
    return col;
}

// ================================================================
vec4 renderMain() {
    vec3 ro = vec3(cam_x, cam_y, cam_z);
    vec2 sc = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 cu = vec3(cam_rx, cam_ry, cam_rz);
    vec3 cv = vec3(cam_ux, cam_uy, cam_uz);
    vec3 cw = vec3(cam_fx, cam_fy, cam_fz);
    vec3 rd = normalize(sc.x * cu + sc.y * cv + 1.3 * cw);

    vec3 spotLight = ro + cw * 1.5
                   + vec3(sin(TIME * 0.73),
                          cos(TIME * 0.51),
                          sin(TIME * 0.89)) * 1.20;

    vec3  sky    = vec3(0.03, 0.04, 0.05) * GetSky(rd);
    float jitter = fract(sin(dot(_uv * RENDERSIZE, vec2(12.9898, 78.233))) * 43758.5453);
    vec2  ret    = Scene(ro, rd, jitter);

    vec3 col = vec3(0.0);
    if (ret.x < 900.0)
        col = renderColour(ro + ret.x * rd, ret, rd, spotLight);

    col  = mix(sky, col, min(exp(-ret.x * 0.15), 1.0));
    col += pow(abs(ret.y), 2.5) * vec3(0.01, 0.00, 0.03);
    col += LightSource(spotLight - ro, rd, ret.x);
    col  = PostEffects(col, _uv);
    col  = mix(col, texture(syn_FinalPass, _uv).rgb, motion_blur);

    return vec4(col, 1.0);
}
