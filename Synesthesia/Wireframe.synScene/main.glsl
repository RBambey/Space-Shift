// ============================================================
//  WIREFRAME — v1.1
//  Created by RBambey
//  Grand Canyon wireframe fly-through with Ocean Planet camera.
//  SDF canyon (floor + two walls + fork pillar) rendered as a
//  fwidth()-antialiased world-space grid with glow halos.
//  v1.1: bumpy terrain floor, terrain collision, bass reactivity.
// ============================================================

// ---- Hue → saturated RGB (HSV S=1 V=1) ----
vec3 hue2rgb(float h) {
    return clamp(abs(fract(h + vec3(0.0, 1.0/3.0, 2.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

// ---- Canyon path: 4-frequency sine, all zero at z=0 ----
// Frequencies are ~golden-ratio spaced to avoid repetition.
vec2 path(float z) {
    float s = 0.018;
    return vec2(
        sin(z * s)        * 30.0 +
        sin(z * s * 1.37) * 18.0 +
        sin(z * s * 2.61) *  8.0 +
        sin(z * s * 4.07) *  3.0,
        0.0
    );
}

// ---- Canyon half-width (gentle variation around canyon_width/2) ----
float halfWidth(float z) {
    return canyon_width * 0.5 *
        (1.0 + 0.12 * sin(z * 0.031) + 0.08 * cos(z * 0.057 + 2.0));
}

// ---- Canyon floor height (world-space undulation) ----
// 3-frequency sine/cos. Mirrored exactly in script.js floorHeight().
// Max ∇h ≈ 0.80 → SDF Lipschitz ≈ 1.28; step multiplier 0.75 keeps march safe.
float floorHeight(vec2 xz) {
    return sin(xz.x * 0.08 + xz.y * 0.05)         * 2.5
         + sin(xz.x * 0.17 + xz.y * 0.12 + 1.7)   * 1.5
         + cos(xz.x * 0.29 + xz.y * 0.21 + 3.1)   * 0.7;
}

// ---- Scene SDF ----
// Convention: positive = air (keep marching), near-zero = surface, negative = solid.
float scene(vec3 p) {
    vec2  c   = path(p.z);
    float px  = p.x - c.x;          // lateral offset from canyon center
    float hw  = halfWidth(p.z);

    float dL  =  px + hw;            // distance inside left wall  (+ = inside canyon)
    float dR  = -px + hw;            // distance inside right wall (+ = inside canyon)
    float dF  = p.y - floorHeight(p.xz);   // distance above terrain floor

    // Fork pillar: central rock island, present for ~240 of every 600 units.
    // +200 offset ensures no pillar right at the starting position.
    float fz  = fract((p.z + 200.0) / 600.0);
    float act = smoothstep(0.20, 0.35, fz) * smoothstep(0.80, 0.65, fz);
    float phw = hw * 0.20 * act;
    float dP  = (phw > 0.1) ? (abs(px) - phw) : 1e10;

    return min(min(dL, dR), min(dF, dP));
}

// ---- Wire-glow: sharp core + exponential halo, fwidth()-antialiased ----
// Bass hits expand the halo radius — shockwave effect through the grid.
float wireGlow(float coord, float spacing) {
    float f    = fract(coord / spacing);
    float fw   = min(fwidth(coord / spacing) * 1.5, 0.4); // clamp at grazing angles
    float d    = min(f, 1.0 - f);
    float core = 1.0 - smoothstep(fw * 0.8, fw * 2.5, d);
    float hr   = fw * (6.0 + syn_BassHits * bass_reactivity * 10.0);
    float halo = exp(-d / max(hr, 0.015)) * 0.28;
    return core + halo;
}

// ---- 3-axis world-space grid with sine-wave coord warping ----
// ny/nz/nx offsets make lines gently wavy — geological strata / cracked rock.
float gridVal(vec3 p) {
    float sp  = 4.5;
    float spZ = 4.95;               // slightly different depth spacing: richer cross-pattern
    vec2  c   = path(p.z);
    float px  = p.x - c.x;         // lateral position relative to canyon center

    float ny = sin(p.z * 0.47 + px * 0.30) * 0.40;
    float nz = cos(p.y * 0.40 + px * 0.20) * 0.35;
    float nx = sin(p.z * 0.30 + p.y * 0.60) * 0.30;

    float wy = wireGlow(p.y + ny, sp);      // horizontal strata rings
    float wz = wireGlow(p.z + nz, spZ);     // depth columns running along canyon
    float wx = wireGlow(px  + nx, sp);      // lateral arches across the width

    return max(max(wx, wy), wz);
}

vec4 renderMain() {
    // ---- Camera (identical pattern to Ocean Planet / Mars / Starfall) ----
    vec3 ro     = vec3(cam_x, cam_y, cam_z);
    vec3 cRight = vec3(cam_rx, cam_ry, cam_rz);
    vec3 cUp    = vec3(cam_ux, cam_uy, cam_uz);
    vec3 cFwd   = vec3(cam_fx, cam_fy, cam_fz);
    vec2 uv     = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd     = normalize(cFwd + cRight * uv.x + cUp * uv.y);

    // ---- Background color ----
    // bg_color = 0  → pure black  (hue * 0² * 0.2 = 0).
    // bg_color > 0  → dim hue that cycles through spectrum as slider increases.
    vec3 bgCol = hue2rgb(bg_color) * (bg_color * bg_color) * 0.20;

    // ---- Raymarch ----
    float t   = 0.05;
    bool  hit = false;
    for (int i = 0; i < 160; i++) {
        vec3  p = ro + rd * t;
        float d = scene(p);
        if (d < 0.02)                     { hit = true; break; }
        if (d < 0.0 || t > draw_distance) break;
        t += max(d * 0.75, 0.01);  // 0.75 × Lipschitz(1.28) = 0.96 < 1 — safe with bumpy floor
    }

    if (!hit) return vec4(bgCol, 1.0);

    // ---- Surface shading ----
    vec3  p    = ro + rd * t;
    float w    = gridVal(p);
    float fog  = exp(-t * 0.006);           // depth cue: distant lines grow dim
    vec3  wCol = hue2rgb(wire_hue);
    vec3  col  = mix(bgCol, wCol * clamp(w, 0.0, 1.5), fog);

    // ---- Audio: bass hits flash wireframe; sustained bass elevates glow ----
    col *= 1.0 + syn_BassHits  * bass_reactivity * 1.5
               + syn_BassLevel * bass_reactivity * 0.6;

    return vec4(col, 1.0);
}
