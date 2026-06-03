// ============================================================
//  MONSTER — v1.0
//  RBambey
//  Original shader "Lowlands juggernauts" by evvvvil_
//  https://www.twitch.tv/evvvvil_
//  Flight mechanics from Ocean Planet by RBambey
// ============================================================

// Procedural fbm noise — replaces iChannel0 texture from original
float hashf(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noisef(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hashf(i),                   hashf(i + vec2(1.0, 0.0)), f.x),
               mix(hashf(i + vec2(0.0, 1.0)),  hashf(i + vec2(1.0, 1.0)), f.x), f.y);
}
vec4 texNoise(vec2 uv) {
    float f  = 0.0;
    f += noisef(uv * 0.125) * 0.500;
    f += noisef(uv * 0.250) * 0.250;
    f += noisef(uv * 0.500) * 0.125;
    f += noisef(uv * 1.000) * 0.125;
    f  = pow(f, 1.2);
    return vec4(f * 0.45 + 0.05);
}

// ---- Per-pixel globals (GLSL zero-inits these per invocation) ----
vec2  eps = vec2(0.0035, -0.0035);
float tt, gB, gR, tnoi;
vec3  np, bp, op, pp, po, sno, al, ld;

// ---- SDF helpers ----
// mat2 rotation by angle r (standard counter-clockwise)
mat2 rot2(float r) { return mat2(cos(r), sin(r), -sin(r), cos(r)); }

float smin(float d1, float d2, float k) {
    float h = max(k - abs(d1 - d2), 0.0);
    return min(d1, d2) - h * h * 0.25 / k;
}

// Mercury / Flopine octan mirror
vec2 mo(vec2 p, vec2 d) { p = abs(p) - d; if (p.y > p.x) p = p.yx; return p; }

// Jagged rock displacement — multi-scale noise with sharpened peaks
float rockDisp(vec2 p) {
    float n = noisef(p * 0.20) * 3.0
            + noisef(p * 0.70) * 1.0
            + noisef(p * 2.50) * 0.40
            + noisef(p * 8.00) * 0.12;
    return pow(n / 4.52, 0.60) * 1.5;   // sharpen toward spiky peaks, max ~1.5
}

// ---- Scene SDF — monsters scattered on a flat XZ ground plane ----
vec2 mp(vec3 p) {
    np = p;

    // 2D grid in XZ — one monster per 80x80 ground cell
    float CELL = 160.0;
    vec2 cellID = floor(p.xz / CELL);

    // Three uncorrelated per-cell random values (2D dot-product hash)
    float h1 = fract(sin(dot(cellID, vec2(127.1, 311.7))) * 43758.5453);
    float h2 = fract(sin(dot(cellID, vec2(269.5, 183.3))) * 73156.8765);
    float h3 = fract(sin(dot(cellID, vec2(419.2, 371.9))) * 53421.2341);

    // Scatter only in XZ; Y stays as world height (ground plane)
    p.xz = mod(p.xz, CELL) - CELL * 0.5;
    p.xz -= (vec2(h1, h2) - 0.5) * 50.0;  // ±25-unit scatter in X/Z
    p.xz = rot2(h3 * 6.2832) * p.xz;       // random yaw 0–360°

    op  = p;
    p.y += sin(np.z * 0.2 + tt) * 3.0 - 5.0;
    pp  = p;
    pp.xz  = mo(pp.xz, vec2(1.0));
    pp.yz  = rot2(-(1.2 + sin(p.y * 0.5 + tt) * 0.3)) * pp.yz;
    pp.yz  = mo(pp.yz, vec2(0.5, 1.0));
    pp.xy  = mo(pp.xy, vec2(2.5));
    tnoi   = texNoise((np.xz + vec2(20.0, tt * 2.0)) * 0.018).r;

    vec2 t = vec2(length(p) - 5.0, 5.0);    // SHELL BLUE
    t.x = max(abs(t.x) - 0.4, abs(pp.z) - 0.5);
    bp = pp; bp.xy = rot2(0.9) * bp.xy;
    t.x = smin(t.x, 0.6 * max(length(bp.xz) - max(1.4 - tnoi * 4.0, 0.45), p.y - 2.0), 1.0);

    float frill = sin(pp.y * 15.0) * 0.03;

    vec2 h = vec2(length(p) - 5.5, 6.0);   // SHELL WHITE
    h.x = max(h.x, abs(pp.z) - 0.2);
    h.x = max(h.x, -(length(p) - 4.0 + frill));
    bp = pp; bp.xy = rot2(-0.4585) * bp.xy; // original: bp.xy *= r2(0.4585)
    h.x = min(0.8 * length(bp.yz + vec2(2.0, 0.0)) - 0.1 + abs(bp.x) * 0.02, h.x);
    t = t.x < h.x ? t : h;

    h = vec2(length(p) - 5.4, 3.0);        // SHELL BLACK
    h.x = abs(h.x) - 0.2;
    h.x = max(h.x, abs(pp.z) - 0.3);
    h.x = max(h.x, abs(abs(abs(pp.x) - 1.0) - 0.5) - 0.25);
    t = t.x < h.x ? t : h;

    h = vec2(length(p) - 3.0 + frill, 5.0);  // CORE
    pp.xy = rot2(0.6) * pp.xy;              // original: pp.xy *= r2(-0.6)
    h.x = smin(h.x, 0.8 * length(pp.xz - vec2(0.2, 1.0 + tnoi * 3.0)) - 0.4 + frill, 3.0);
    t = t.x < h.x ? t : h;

    h.x = min(h.x, 0.2 * length(cos(np * 0.2) - 1.5));   // TERRAIN SOFT ORBS (world space)
    gB += 0.1 / (0.1 + h.x * h.x * 40.0);

    h = vec2(length(p) - 3.0 + frill, 5.0);  // RED CORE
    pp.xy = rot2(0.1) * pp.xy;              // original: pp.xy *= r2(-0.1)
    h.x = smin(h.x, length(pp.xz - vec2(0.2, 1.1 + tnoi * 3.0)) - 0.2 + frill, 3.0);
    h.x = smin(h.x, 0.6 * length(abs(bp + vec3(2.0, 2.0 + tnoi * 5.0, 0.0)) - 2.0) - 0.7, 1.0);
    gR += 0.1 / (0.1 + h.x * h.x * (80.0 - 79.9 * sin(op.y * 0.2 + tt + 1.0)));
    t = t.x < h.x ? t : h;

    // Rocky ground — evaluated in world space (np) so it lies flat regardless of cell
    float gnd = np.y + 8.0 - rockDisp(np.xz * 0.5);
    t = t.x < gnd ? t : vec2(gnd, 2.0);

    t.x *= 0.7;
    return t;
}

// ---- Ray marcher ----
vec2 tr(vec3 ro, vec3 rd) {
    vec2 t = vec2(0.0);
    vec2 h = vec2(0.0);
    for (int i = 0; i < 128; i++) {
        h = mp(ro + rd * t.x);
        if (h.x < 0.0001 || t.x > render_distance) break;
        t.x += h.x; t.y = h.y;
    }
    if (t.x > render_distance) t.y = 0.0;
    return t;
}

// AO and soft-shadow — use globals po, sno, ld set in renderMain before calling
float calcAO(float d) { return clamp(mp(po + sno * d).x / d, 0.0, 1.0); }
float calcSH(float d) { return smoothstep(0.0, 1.0, mp(po + ld * d).x / d); }

vec4 renderMain() {
    vec2 uv = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);

    tt = mod(TIME * anim_speed, 62.82);
    gB = 0.0;
    gR = 0.0;

    vec3 ro = vec3(cam_x, cam_y, cam_z);
    vec3 cu = vec3(cam_rx, cam_ry, cam_rz);
    vec3 cv = vec3(cam_ux, cam_uy, cam_uz);
    vec3 cw = vec3(cam_fx, cam_fy, cam_fz);
    vec3 rd = normalize(cw + cu * uv.x + cv * uv.y);

    // Background — deep space purple
    vec3 fo = vec3(0.04, 0.02, 0.12);
    vec3 co = fo;
    ld = normalize(vec3(0.4, 0.8, -0.2));

    vec2  hit     = tr(ro, rd);
    float rayDist = hit.x;

    if (hit.y > 0.0) {
        po = ro + rd * rayDist;
        // Tetrahedral finite-difference normal
        sno = normalize(
            eps.xyy * mp(po + eps.xyy).x +
            eps.yyx * mp(po + eps.yyx).x +
            eps.yxy * mp(po + eps.yxy).x +
            eps.xxx * mp(po + eps.xxx).x
        );

        float dif = max(0.0, dot(sno, ld));
        float fr  = pow(1.0 + dot(sno, rd), 4.0);

        if (hit.y < 2.5) {
            // Material 2 — jagged shiny rock
            al = vec3(0.05, 0.07, 0.18);
            float ao   = calcAO(0.05) * calcAO(0.15);
            float spec = pow(max(0.0, dot(reflect(-ld, sno), -rd)), 40.0);
            co = al * ao * (dif * vec3(0.4, 0.7, 1.0) * 4.0 + calcSH(0.5))
               + vec3(0.5, 0.7, 1.0) * spec * 5.0 * calcSH(0.2);
            co = mix(co, fo * 0.5, clamp(fr * 0.3, 0.0, 0.35));
        } else {
            // Monster materials: 3=black shell, 5=blue, 6=white shell
            al = vec3(0.1, 0.3, 0.8);
            if (hit.y < 5.0) al = vec3(0.0);
            if (hit.y > 5.0) al = vec3(1.0);
            co = mix(
                al * (calcAO(0.05) * calcAO(0.1) + 0.35) * (dif * vec3(0.3, 0.6, 1.0) * 5.0 + calcSH(0.5)),
                fo, min(fr, 0.5)
            );
        }
        co = mix(fo, co, exp(-0.00005 * rayDist * rayDist * rayDist));
    }

    // Combine surface + blue glow (terrain orbs) + red glow (pulsing core)
    float beat = pow(syn_BassLevel, 2.0) * beat_strength;
    vec3 col = co + gB * (0.5 + beat * 1.5) * vec3(0.1, 0.3, 1.0)
                  + gR * (0.4 + beat * 1.2) * vec3(1.0, 0.2, 0.1);
    col = pow(max(col, vec3(0.0)), vec3(0.45));

    col *= 1.0 + syn_BassLevel * bass_reactivity * 0.5;
    col  = mix(col, texture(syn_FinalPass, _uv).rgb, motion_blur);

    return vec4(clamp(col, 0.0, 1.0), 1.0);
}
