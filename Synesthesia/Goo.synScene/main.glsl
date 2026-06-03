// ============================================================
//  GOO — v1.0
//  RBambey
//  Original shader by Kamil Kolaczynski (revers) — 2016
//  CC-BY-NC-SA 3.0 https://creativecommons.org/licenses/by-nc-sa/3.0/
//  Raymarching/noise/lighting by iq https://iquilezles.org/articles/smin
//  Camera path by Shane "Subterranean Fly-Through"
//    https://www.shadertoy.com/view/XlXXWj
//  Wet-stone specular trick by TDM
//    https://www.shadertoy.com/view/ldSSzV
//  6-DOF flight mechanics from Remnant Planet by RBambey
// ============================================================

const float FOV               = 0.4;
const float MarchDumping      = 0.7579;
const float Far               = 38.925;
const int   MaxSteps          = 128;
const float TunnelSmoothFactor = 2.0;
const float TunnelRadius      = 0.85660005;
const float TunnelFreqA       = 0.18003;
const float TunnelFreqB       = 0.25;
const float TunnelAmpA        = 3.6230998;
const float TunnelAmpB        = 2.4324;
const float NoiseIsoline      = 0.319;
const float NoiseScale        = 2.9980001;
const vec3  Color             = vec3(0.085, 0.658, 1.0);

#define M_NONE -1.0
#define M_NOISE 1.0

float hash(float h) {
    return fract(sin(h) * 43758.5453123);
}

float noise(vec3 x) {
    vec3 p = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float n = p.x + p.y * 157.0 + 113.0 * p.z;
    return mix(
        mix(mix(hash(n + 0.0),   hash(n + 1.0),   f.x),
            mix(hash(n + 157.0), hash(n + 158.0), f.x), f.y),
        mix(mix(hash(n + 113.0), hash(n + 114.0), f.x),
            mix(hash(n + 270.0), hash(n + 271.0), f.x), f.y), f.z);
}

float fbm(vec3 p) {
    float f = 0.0;
    f  = 0.5000 * noise(p);
    p *= 2.01;
    f += 0.2500 * noise(p);
    p *= 2.02;
    f += 0.1250 * noise(p);
    return f;
}

// Smooth maximum — by iq
float smax(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(a, b, h) + k * h * (1.0 - h);
}

// Sinusoidal tunnel centreline
vec2 path(float z) {
    return vec2(TunnelAmpA * sin(z * TunnelFreqA), TunnelAmpB * cos(z * TunnelFreqB));
}

float noiseDist(vec3 p) {
    p = p / NoiseScale;
    return (fbm(p) - NoiseIsoline) * NoiseScale;
}

vec2 map(vec3 p) {
    float d  = noiseDist(p);
    float d2 = length(p.xy - path(p.z)) - TunnelRadius;
    d = smax(d, -d2, TunnelSmoothFactor);
    return vec2(d, M_NOISE);
}

vec2 castRay(vec3 ro, vec3 rd) {
    float precis = 0.002;
    float t = 0.0;
    float m = M_NONE;
    for (int i = 0; i < MaxSteps; i++) {
        vec2 res = map(ro + rd * t);
        if (res.x < precis || t > Far) break;
        t += res.x * MarchDumping;
        m  = res.y;
    }
    if (t > Far) m = M_NONE;
    return vec2(t, m);
}

float softshadow(vec3 ro, vec3 rd, float mint, float tmax) {
    float res = 1.0;
    float t   = mint;
    for (int i = 0; i < 16; i++) {
        float h = map(ro + rd * t).x;
        res = min(res, 8.0 * h / t);
        t  += clamp(h, 0.02, 0.10);
        if (h < 0.001 || t > tmax) break;
    }
    return clamp(res, 0.0, 1.0);
}

vec3 calcNormal(vec3 pos) {
    vec2 eps = vec2(0.001, 0.0);
    return normalize(vec3(
        map(pos + eps.xyy).x - map(pos - eps.xyy).x,
        map(pos + eps.yxy).x - map(pos - eps.yxy).x,
        map(pos + eps.yyx).x - map(pos - eps.yyx).x));
}

float calcAO(vec3 pos, vec3 nor) {
    float occ = 0.0, sca = 1.0;
    for (int i = 0; i < 5; i++) {
        float hr    = 0.01 + 0.12 * float(i) / 4.0;
        vec3  aopos = nor * hr + pos;
        float dd    = map(aopos).x;
        occ += -(dd - hr) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}

vec3 render(vec3 ro, vec3 rd) {
    vec3 col = vec3(0.0);
    vec2 res = castRay(ro, rd);
    float t  = res.x;
    float m  = res.y;

    if (m > -0.5) {
        vec3 pos = ro + t * rd;
        vec3 nor = calcNormal(pos);

        // Base colour: depth-tinted blue + time-driven colour shift
        col  = Color + sin(t * 0.8) * 0.3;
        col += 0.3 * sin(vec3(0.15, 0.02, 0.10) * TIME * 6.0 * colour_speed);

        // Lighting
        float occ = calcAO(pos, nor);
        vec3  lig = -rd;
        float amb = clamp(0.5 + 0.5 * nor.y, 0.0, 1.0);
        float dif = clamp(dot(nor, lig), 0.0, 1.0);
        float fre = pow(clamp(1.0 + dot(nor, rd), 0.0, 1.0), 2.0);

        vec3  ref = reflect(rd, nor);
        float spe = pow(clamp(dot(ref, lig), 0.0, 1.0), 100.0);

        dif *= softshadow(pos, lig, 0.02, 2.5);

        vec3 brdf = vec3(0.0);
        brdf += 1.20 * dif * vec3(1.00, 0.90, 0.60);
        brdf += 1.20 * spe * vec3(1.00, 0.90, 0.60) * dif;

        // Wet-stone specular trick — TDM https://www.shadertoy.com/view/ldSSzV
        nor  = normalize(nor - normalize(pos) * 0.2);
        ref  = reflect(rd, nor);
        spe  = pow(clamp(dot(ref, lig), 0.0, 1.0), 100.0);
        brdf += 2.20 * spe * vec3(1.00, 0.90, 0.60) * dif;

        brdf += 0.40 * amb * vec3(0.50, 0.70, 1.00) * occ;
        brdf += 0.40 * fre * vec3(1.00, 1.00, 1.00) * occ;

        col = col * brdf;
        col = mix(col, vec3(0.0), 1.0 - exp(-0.005 * t * t));
    } else {
        // No geometry hit — show the goo surface colour rather than black
        col = Color + 0.3 * sin(vec3(0.15, 0.02, 0.10) * TIME * 6.0 * colour_speed);
    }
    return clamp(col, 0.0, 1.0);
}

vec4 renderMain() {
    // Build ray from 6-DOF camera uniforms set by script.js
    vec2 coord = 2.0 * _uv - 1.0;
    coord.x   *= RENDERSIZE.x / RENDERSIZE.y;
    coord     *= FOV;

    vec3 ro = vec3(cam_x, cam_y, cam_z);
    vec3 cu = vec3(cam_rx, cam_ry, cam_rz);   // right
    vec3 cv = vec3(cam_ux, cam_uy, cam_uz);   // up
    vec3 cw = vec3(cam_fx, cam_fy, cam_fz);   // forward
    vec3 rd = normalize(cw + coord.x * cu + coord.y * cv);

    vec3 col = render(ro, rd);

    // Bass pulse
    col *= 1.0 + syn_BassLevel * bass_reactivity * 0.5;

    // Gamma
    col = pow(col, vec3(0.4545));

    // Temporal accumulation
    col = mix(col, texture(syn_FinalPass, _uv).rgb, motion_blur);

    return vec4(col, 1.0);
}
