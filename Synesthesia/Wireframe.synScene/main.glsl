// ============================================================
//  WIREFRAME — v2.0
//  Created by RBambey
//  Low-poly canyon fly-through — triangulated polygon edge glow
//  on a black background.  Walls have independent protrusions and
//  UV-skewed strata tilt for a sloped-facet look.  Bass ripple
//  wave identical to Flying Synth.
//  v1.1: bumpy floor, terrain collision, bass reactivity.
//  v1.2: path scales with canyon_width; wall sliding collision.
//  v2.0: faceted polygon edges; wall protrusions + strata tilt;
//        bass ripple ring wave.
// ============================================================

// ---- Hue → saturated RGB (HSV S=1 V=1) ----
vec3 hue2rgb(float h) {
    return clamp(abs(fract(h + vec3(0.0, 1.0/3.0, 2.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

// ---- Canyon path (amplitudes scale with canyon_width) ----
// All-sin, zero at z=0.  Golden-ratio frequencies avoid repetition.
// amp = canyon_width/200 → max deviation ≈ 62% of halfWidth at any width.
vec2 path(float z) {
    float s   = 0.018;
    float amp = canyon_width / 200.0;
    return vec2(
        (sin(z * s)        * 30.0 +
         sin(z * s * 1.37) * 18.0 +
         sin(z * s * 2.61) *  8.0 +
         sin(z * s * 4.07) *  3.0) * amp,
        0.0
    );
}

// ---- Canyon half-width (gentle variation) ----
float halfWidth(float z) {
    return canyon_width * 0.5 *
        (1.0 + 0.12 * sin(z * 0.031) + 0.08 * cos(z * 0.057 + 2.0));
}

// ---- Floor height — mirrored exactly in script.js ----
// Max |∇h| ≈ 0.80 → SDF Lipschitz ≈ 1.28 (floor dominates).
float floorHeight(vec2 xz) {
    return sin(xz.x * 0.08 + xz.y * 0.05)         * 2.5
         + sin(xz.x * 0.17 + xz.y * 0.12 + 1.7)   * 1.5
         + cos(xz.x * 0.29 + xz.y * 0.21 + 3.1)   * 0.7;
}

// ---- Wall protrusions ----
// Left and right walls get independent bumpy insets.
// Amplitude scales with sqrt(canyon_width/60) so narrow canyons
// stay navigable and wide ones get dramatic rocky walls.
// Max |∇wv| × scale ≤ 0.75 in y-z → SDF Lipschitz stays ≤ 1.28.
vec2 wallVar(vec3 p) {
    float scale = sqrt(canyon_width / 60.0);
    float bL = (sin(p.z * 0.067 + p.y * 0.11)       * 1.5
             +  sin(p.z * 0.131 + p.y * 0.08 + 2.1) * 0.8
             +  sin(p.z * 0.23  + p.y * 0.19 + 4.5) * 0.35) * scale;
    float bR = (sin(p.z * 0.067 + p.y * 0.11 + 3.7) * 1.5
             +  sin(p.z * 0.131 + p.y * 0.08 + 5.2) * 0.8
             +  sin(p.z * 0.23  + p.y * 0.19 + 1.3) * 0.35) * scale;
    return vec2(bL, bR);
}

// ---- Scene SDF ----
// Convention: positive = air (march), near-zero = surface, negative = solid.
float scene(vec3 p) {
    vec2  c   = path(p.z);
    float px  = p.x - c.x;
    float hw  = halfWidth(p.z);
    vec2  wv  = wallVar(p);

    float dL  =  px + hw - wv.x;        // left wall with protrusion
    float dR  = -px + hw - wv.y;        // right wall with protrusion
    float dF  = p.y - floorHeight(p.xz);

    // Fork pillar: central rock island, every 600 z-units.
    float fz  = fract((p.z + 200.0) / 600.0);
    float act = smoothstep(0.20, 0.35, fz) * smoothstep(0.80, 0.65, fz);
    float phw = hw * 0.20 * act;
    float dP  = (phw > 0.1) ? (abs(px) - phw) : 1e10;

    return min(min(dL, dR), min(dF, dP));
}

// ---- Triangulated polygon-edge glow ----
// Divides each quad into two triangles on the main diagonal.
// b = min barycentric coordinate: 0 at every edge, ~0.33 at centroid.
// Screen-space fwidth keeps line width constant regardless of distance.
float triEdge(vec2 uv, float cs) {
    vec2  f  = fract(uv / cs);
    float b  = (f.x + f.y < 1.0)
             ? min(f.x, min(f.y, 1.0 - f.x - f.y))      // lower-left triangle
             : min(1.0 - f.x, min(1.0 - f.y, f.x + f.y - 1.0));  // upper-right triangle
    float fw = min(fwidth(b), 0.35);                     // clamp for grazing angles
    float core = 1.0 - smoothstep(fw * 0.5, fw * 2.5, b);
    // Halo radius expands on bass hits — same shockwave mechanic as v1.x
    float hr   = fw * (5.0 + syn_BassHits * bass_reactivity * 10.0);
    float halo = exp(-b / max(hr, 0.001)) * 0.35;
    return core + halo;
}

vec4 renderMain() {
    // ---- Camera ----
    vec3 ro     = vec3(cam_x, cam_y, cam_z);
    vec3 cRight = vec3(cam_rx, cam_ry, cam_rz);
    vec3 cUp    = vec3(cam_ux, cam_uy, cam_uz);
    vec3 cFwd   = vec3(cam_fx, cam_fy, cam_fz);
    vec2 uv     = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd     = normalize(cFwd + cRight * uv.x + cUp * uv.y);

    // ---- Background ----
    vec3 bgCol = hue2rgb(bg_color) * (bg_color * bg_color) * 0.20;

    // ---- Raymarch ----
    // 0.75 × Lipschitz(1.28) = 0.96 < 1 — safe with bumpy floor + wall var.
    float t   = 0.05;
    bool  hit = false;
    for (int i = 0; i < 160; i++) {
        vec3  p = ro + rd * t;
        float d = scene(p);
        if (d < 0.02)                     { hit = true; break; }
        if (d < 0.0 || t > draw_distance) break;
        t += max(d * 0.75, 0.01);
    }

    if (!hit) return vec4(bgCol, 1.0);

    // ---- Determine which surface was hit ----
    vec3  p   = ro + rd * t;
    vec2  c   = path(p.z);
    float px  = p.x - c.x;
    float hw  = halfWidth(p.z);
    vec2  wv  = wallVar(p);
    float dL  =  px + hw - wv.x;
    float dR  = -px + hw - wv.y;
    float dF  = p.y - floorHeight(p.xz);

    float w;
    if (dF <= dL && dF <= dR) {
        // Floor — parameterise in (x, z)
        w = triEdge(p.xz, poly_size);
    } else {
        // Wall — parameterise in (z, y) with a slow strata tilt.
        // UV skew makes horizontal polygon edges run at a slight angle,
        // giving the visual impression of sloped, layered rock faces.
        // Pure UV effect: no physics impact, no Lipschitz change.
        float tilt = sin(p.z * 0.019) * 0.45;
        w = triEdge(vec2(p.z + tilt * p.y, p.y), poly_size);
    }

    // ---- Bass ripple wave — identical to Flying Synth terrainColor() ----
    // Ring pattern driven by syn_BassTime: advances faster during bass.
    // At silence rings freeze; on a hit they rush outward from camera.
    // Using t (ray depth) as distance metric — appropriate for a canyon.
    float ripple = sin(t * 0.6 - syn_BassTime * 7.0);
    ripple = pow(clamp(ripple * 0.5 + 0.5, 0.0, 1.0), 3.0);
    ripple *= syn_BassLevel * bass_reactivity;

    // Ripple brightens existing edges at the wavefront
    w = w * (1.0 + ripple * 2.5) + ripple * 0.12;

    // ---- Shading ----
    float fog  = exp(-t * 0.006);
    vec3  wCol = hue2rgb(wire_hue);
    vec3  col  = mix(bgCol, wCol * clamp(w, 0.0, 1.5), fog);

    // Sustained bass raises overall glow level
    col *= 1.0 + syn_BassLevel * bass_reactivity * 0.6;

    return vec4(col, 1.0);
}
