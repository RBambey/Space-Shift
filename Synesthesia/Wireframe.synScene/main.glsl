// ============================================================
//  WIREFRAME — v3.0
//  Created by RBambey
//  True low-poly facets: each triangle uses actual 3D tessellated
//  vertex positions (floor height field, wall surface with path
//  curve + protrusions).  Flat normal per face drives dim shading
//  so each polygon is visually distinct.  Edges glow at the actual
//  3D mesh boundaries, not a UV-space grid overlay.
//  v1.1: bumpy floor, terrain collision, bass reactivity.
//  v1.2: path scales with canyon_width; wall sliding collision.
//  v2.0: polygon edges; wall protrusions; bass ripple wave.
//  v3.0: 3D tessellated vertices; flat-face shading; green default.
// ============================================================

// ---- Hue → saturated RGB (HSV S=1 V=1) ----
// Formula: 0 = red, 0.33 = blue, 0.67 = green  (verified by evaluation).
vec3 hue2rgb(float h) {
    return clamp(abs(fract(h + vec3(0.0, 1.0/3.0, 2.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

// ---- Canyon path (amplitudes scale with canyon_width) ----
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

// ---- Canyon half-width ----
float halfWidth(float z) {
    return canyon_width * 0.5 *
        (1.0 + 0.12 * sin(z * 0.031) + 0.08 * cos(z * 0.057 + 2.0));
}

// ---- Floor height — mirrored exactly in script.js ----
// Max |∇h| ≈ 0.80 → SDF Lipschitz ≈ 1.28.
float floorHeight(vec2 xz) {
    return sin(xz.x * 0.08 + xz.y * 0.05)         * 2.5
         + sin(xz.x * 0.17 + xz.y * 0.12 + 1.7)   * 1.5
         + cos(xz.x * 0.29 + xz.y * 0.21 + 3.1)   * 0.7;
}

// ---- Wall protrusions (independent per side, scaled with width) ----
// wallVar() uses only p.y and p.z, so the x argument is irrelevant.
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
float scene(vec3 p) {
    vec2  c   = path(p.z);
    float px  = p.x - c.x;
    float hw  = halfWidth(p.z);
    vec2  wv  = wallVar(p);

    float dL  =  px + hw - wv.x;
    float dR  = -px + hw - wv.y;
    float dF  = p.y - floorHeight(p.xz);

    float fz  = fract((p.z + 200.0) / 600.0);
    float act = smoothstep(0.20, 0.35, fz) * smoothstep(0.80, 0.65, fz);
    float phw = hw * 0.20 * act;
    float dP  = (phw > 0.1) ? (abs(px) - phw) : 1e10;

    return min(min(dL, dR), min(dF, dP));
}

// ---- Tessellation vertex helpers ----
// Return the actual 3D world-space position of a mesh vertex, which is
// what makes edges follow the terrain shape instead of a UV overlay.

vec3 fVert(float xi, float zj) {
    return vec3(xi, floorHeight(vec2(xi, zj)), zj);
}

// wallVar() only reads p.y and p.z so passing x=0 is fine.
vec3 wVertL(float zi, float yj) {
    vec2  pc = path(zi);
    float hw = halfWidth(zi);
    float bL = wallVar(vec3(0.0, yj, zi)).x;
    return vec3(pc.x - hw + bL, yj, zi);
}

vec3 wVertR(float zi, float yj) {
    vec2  pc = path(zi);
    float hw = halfWidth(zi);
    float bR = wallVar(vec3(0.0, yj, zi)).y;
    return vec3(pc.x + hw - bR, yj, zi);
}

// ---- Min barycentric coordinate of p in triangle (v0,v1,v2) ----
// 0 at any edge → ~0.33 at centroid.  Clamped ≥ 0 to absorb the small
// difference between the smooth SDF hit point and the tessellated plane.
float minBary(vec3 p, vec3 v0, vec3 v1, vec3 v2) {
    vec3  e0  = v1 - v0,  e1  = v2 - v0,  ep  = p - v0;
    float d00 = dot(e0, e0), d01 = dot(e0, e1), d11 = dot(e1, e1);
    float d20 = dot(ep, e0), d21 = dot(ep, e1);
    float den = max(d00 * d11 - d01 * d01, 1e-8);
    float bv  = (d11 * d20 - d01 * d21) / den;
    float bw  = (d00 * d21 - d01 * d20) / den;
    return max(min(1.0 - bv - bw, min(bv, bw)), 0.0);
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

    // ---- Identify hit surface ----
    vec3  p   = ro + rd * t;
    vec2  c   = path(p.z);
    float px  = p.x - c.x;
    float hw  = halfWidth(p.z);
    vec2  wv  = wallVar(p);
    float dL  =  px + hw - wv.x;
    float dR  = -px + hw - wv.y;
    float dF  = p.y - floorHeight(p.xz);

    // ---- Find tessellated triangle + flat normal ----
    // Quads split on diagonal (lowT = lower-left triangle, !lowT = upper-right).
    // Winding orders chosen so cross product points toward canyon interior.
    float cs  = poly_size;
    vec3  v0, v1, v2, flatN;

    if (dF <= dL && dF <= dR) {
        // Floor — grid snapped in (x, z), height from floorHeight()
        vec2 ci   = floor(p.xz / cs) * cs;
        bool lowT = (fract(p.x / cs) + fract(p.z / cs) < 1.0);
        if (lowT) {
            v0 = fVert(ci.x,    ci.y);
            v1 = fVert(ci.x+cs, ci.y);
            v2 = fVert(ci.x,    ci.y+cs);
        } else {
            v0 = fVert(ci.x+cs, ci.y);
            v1 = fVert(ci.x+cs, ci.y+cs);
            v2 = fVert(ci.x,    ci.y+cs);
        }
        // cross(v2-v0, v1-v0) → +y (upward) for both winding types ✓
        flatN = normalize(cross(v2 - v0, v1 - v0));

    } else {
        float zi   = floor(p.z / cs) * cs;
        float yj   = floor(p.y / cs) * cs;
        bool  lowT = (fract(p.z / cs) + fract(p.y / cs) < 1.0);

        if (dL < dR) {
            // Left wall — 3D vertices account for path curve + protrusions.
            // Normal should point +x (into canyon).
            if (lowT) {
                v0 = wVertL(zi,    yj);     v1 = wVertL(zi+cs, yj);
                v2 = wVertL(zi,    yj+cs);
            } else {
                v0 = wVertL(zi+cs, yj);     v1 = wVertL(zi+cs, yj+cs);
                v2 = wVertL(zi,    yj+cs);
            }
            // cross(v2-v0, v1-v0) → +x for a flat left wall ✓
            flatN = normalize(cross(v2 - v0, v1 - v0));

        } else {
            // Right wall — normal should point -x (into canyon).
            if (lowT) {
                v0 = wVertR(zi,    yj);     v1 = wVertR(zi+cs, yj);
                v2 = wVertR(zi,    yj+cs);
            } else {
                v0 = wVertR(zi+cs, yj);     v1 = wVertR(zi+cs, yj+cs);
                v2 = wVertR(zi,    yj+cs);
            }
            // cross(v1-v0, v2-v0) → -x for a flat right wall ✓
            flatN = normalize(cross(v1 - v0, v2 - v0));
        }
    }

    float b = minBary(p, v0, v1, v2);

    // ---- Edge glow ----
    // fwidth(b) keeps lines ~2px wide regardless of distance.
    // Halo radius expands on syn_BassHits — shockwave mechanic.
    float fw   = min(fwidth(b), 0.35);
    float core = 1.0 - smoothstep(fw * 0.5, fw * 2.5, b);
    float hr   = fw * (5.0 + syn_BassHits * bass_reactivity * 10.0);
    float halo = exp(-b / max(hr, 0.001)) * 0.35;
    float edgeVal = core + halo;

    // ---- Flat-face shading ----
    // Hemispherical wrap (0.5 + 0.5*dot) maps all normals to [0,1] so
    // every face — including back-facing ones — gets some value.
    // Light from upper-right-front:
    //   floor (normal ≈ +y)     → bright  (~0.19)
    //   left wall (normal ≈ +x) → medium  (~0.14)
    //   right wall (norm ≈ -x)  → dim     (~0.10)
    // Path curvature and protrusions rotate each polygon's normal slightly,
    // giving each face a unique shade — the low-poly topology reads clearly.
    vec3  L       = normalize(vec3(0.3, 1.0, 0.2));
    float faceDim = 0.04 + (0.5 + 0.5 * dot(flatN, L)) * 0.16;

    // Face brightness fills the interior; edge core always overrides it.
    float w = edgeVal + faceDim * (1.0 - core);

    // ---- Bass ripple wave — identical to Flying Synth terrainColor() ----
    // syn_BassTime advances faster during bass → rings rush outward on hit,
    // freeze at silence.  t (ray depth) is the distance metric.
    float ripple = sin(t * 0.6 - syn_BassTime * 7.0);
    ripple = pow(clamp(ripple * 0.5 + 0.5, 0.0, 1.0), 3.0);
    ripple *= syn_BassLevel * bass_reactivity;

    w = w * (1.0 + ripple * 2.5) + ripple * 0.12;

    // ---- Final color ----
    float fog  = exp(-t * 0.006);
    vec3  wCol = hue2rgb(wire_hue);
    vec3  col  = mix(bgCol, wCol * clamp(w, 0.0, 1.5), fog);
    col *= 1.0 + syn_BassLevel * bass_reactivity * 0.6;

    return vec4(col, 1.0);
}
