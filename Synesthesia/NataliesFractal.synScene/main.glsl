// ============================================================
//  NATALIE'S FRACTAL — v4.0  (Infinite Fractal Cosmos)
//  Created by RBambey
//  Inspired by "Mandelbrot Pattern Decoration" (Shane)
//  Flying controls from Ocean Planet by RBambey
//
//  Architecture:
//    - A Mandelbox fractal is tiled infinitely in all directions
//      via domain repetition, so there is always structure in
//      every direction, no matter how far you fly.
//    - Each ray accumulates volumetric glow from nearby fractal
//      surfaces (not just the hit point), creating a glowing
//      nebula feel rather than hard geometry.
//    - Orbit-trap coloring + decorative circle-grid overlay from
//      the inspiration shader are applied to both glow and surface.
// ============================================================

// ---- Compile-time loop bounds ----
const int FOLD_ITER   = 10;
const int MARCH_STEPS = 90;

// How large each tiling cell is (fractal repeats every TILE_SIZE units)
// Fractal object occupies roughly radius 1.8 within each cell.
const float TILE_SIZE = 6.0;

// ---- Bioluminescent palette ----
// Cycles: lime-green → medium green → deep ocean blue → teal/cyan → back
// G channel is always dominant (never drops to red/orange territory).
// base_hue knob shifts between warmer lime and cooler cyan tones.
vec3 fractalPalette(float t, float hue) {
    vec3 a = vec3(0.05, 0.60, 0.40);   // base: green-teal midpoint
    vec3 b = vec3(0.05, 0.35, 0.35);   // amplitude: G stays ≥ 0.25 always
    vec3 c = vec3(1.00, 1.00, 1.00);
    vec3 d = vec3(0.50, 0.00, 0.25) + vec3(hue); // phases → hue shifts cyan ↔ lime
    return a + b * cos(6.28318 * (c * t + d));
}

// ================================================================
//  Mandelbox Distance Estimator
//
//  box_scale (typically -1.5 to -3.0) shapes the fractal:
//    -1.5 = dense corridors    -2.0 = balanced    -3.0 = crystal
//
//  Accumulates orbit trap (trap.xyz = min|z| per axis,
//  trap.w = min|z|²) for coloring.
// ================================================================
float mandelboxDE(vec3 z, out vec4 trap) {
    vec3  c  = z;
    float dz = 1.0;
    float s  = abs(box_scale);
    trap = vec4(1e10);

    for (int i = 0; i < FOLD_ITER; i++) {
        // Box fold: reflect about ±1 cube faces
        z = clamp(z, -1.0, 1.0) * 2.0 - z;

        // Sphere fold: push near-origin orbits outward
        float r2 = dot(z, z);
        if (r2 < 0.25) {
            z  *= 4.0;
            dz *= 4.0;
        } else if (r2 < 1.0) {
            z  /= r2;
            dz /= r2;
        }

        // Scale and translate (box_scale is negative → reflection + scale)
        z  = box_scale * z + c;
        dz = dz * s + 1.0;

        // Accumulate orbit trap
        trap = min(trap, vec4(abs(z), dot(z, z)));
    }

    return (length(z) - (s - 1.0) / s) / dz;
}

// ================================================================
//  Scene: Mandelbox tiled infinitely in all directions
//
//  Domain repetition via mod() tiles the fractal every TILE_SIZE
//  units so it exists everywhere in space simultaneously.
//  A boundary-distance guard prevents step-size discontinuities
//  at tile edges.
// ================================================================
float sceneDE(vec3 p, out vec4 trap) {
    // Map world position to nearest tile's local coordinates
    vec3 lp    = mod(p + TILE_SIZE * 0.5, TILE_SIZE) - TILE_SIZE * 0.5;
    float d    = mandelboxDE(lp, trap);

    // Clamp step to stay within tile (avoids jump artifacts at boundaries)
    float half = TILE_SIZE * 0.5;
    float dBound = min(min(half - abs(lp.x), half - abs(lp.y)), half - abs(lp.z));
    return min(d, dBound * 0.9 + 0.01);
}

// ---- Normal via tetrahedron finite differences ----
vec3 getSceneNormal(vec3 p) {
    const float eps = 0.001;
    vec4 trap;
    const vec2 k = vec2(1.0, -1.0);
    return normalize(
        k.xyy * sceneDE(p + k.xyy * eps, trap) +
        k.yyx * sceneDE(p + k.yyx * eps, trap) +
        k.yxy * sceneDE(p + k.yxy * eps, trap) +
        k.xxx * sceneDE(p + k.xxx * eps, trap)
    );
}

// ================================================================
vec4 renderMain() {

    // ---- Camera (Ocean Planet basis-vector system) ----
    vec3 ro     = vec3(cam_x, cam_y, cam_z);
    vec3 cRight = vec3(cam_rx, cam_ry, cam_rz);
    vec3 cUp    = vec3(cam_ux, cam_uy, cam_uz);
    vec3 cFwd   = vec3(cam_fx, cam_fy, cam_fz);

    // ---- Ray direction (proper 3D perspective) ----
    vec2 uv = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd  = normalize(cFwd + cRight * uv.x + cUp * uv.y);

    // ---- Shared time offset (audio + animation) ----
    float timeOff = syn_BassTime * color_speed * 0.05
                  + TIME        * color_speed * 0.015;

    // ================================================================
    //  Ray march with accumulated volumetric glow
    //
    //  Each step contributes a glow pulse proportional to how close
    //  the ray passes to a fractal surface.  This creates a nebula-
    //  like corona around every structure rather than hard silhouettes.
    // ================================================================
    vec3  glowColor = vec3(0.0);
    bool  hit       = false;
    float hitT      = 0.0;
    vec4  hitTrap   = vec4(0.0);
    float t         = 0.05;

    for (int i = 0; i < MARCH_STEPS; i++) {
        vec3 p  = ro + rd * t;
        vec4 trap;
        float d = sceneDE(p, trap);

        // ---- Volumetric glow ----
        // Linear falloff (not d²) — stays finite even when d→0.
        // Per-step cap prevents any single sample from dominating.
        float glow = glow_amount * 0.004 / (0.08 + d * 5.0);
        glow = min(glow, 0.06);  // hard cap: max 0.06 per step
        float depthFade = exp(-t * 1.5 / draw_distance);

        // Plain palette color for glow (pattern overlay is surface-only — see below)
        float palT = trap.w * 2.0 + timeOff;
        vec3  sampleCol = fractalPalette(palT, base_hue);

        glowColor += sampleCol * glow * depthFade;

        // ---- Surface hit? ----
        if (d < 0.0004 * (1.0 + t * 0.4)) {
            hit     = true;
            hitT    = t;
            hitTrap = trap;
            break;
        }

        // Conservative step; abs(d) handles rare negative-DE interior case
        t += max(abs(d), 0.003) * 0.5;
        if (t > draw_distance) break;
    }

    // ================================================================
    //  Surface shading (adds to the glow accumulation if hit)
    // ================================================================
    if (hit) {
        vec3 p = ro + rd * hitT;
        vec3 n = getSceneNormal(p);

        // Surface base color from orbit trap layers
        float c1 = 1.0 - exp(-hitTrap.w * 2.0);
        float c2 = 1.0 - exp(-hitTrap.x * 3.5);
        float c3 = 1.0 - exp(-hitTrap.y * 3.5);
        vec3 colA = fractalPalette(c1 * 2.0 + timeOff,        base_hue);
        vec3 colB = fractalPalette(c2 * 2.0 + timeOff + 0.33, base_hue + 0.15);
        vec3 colC = fractalPalette(c3 * 2.0 + timeOff + 0.66, base_hue + 0.30);
        vec3 surfCol = mix(mix(colA, colB, c2), colC, c3 * 0.5);

        // Decorative pattern on surface
        vec2 suv = hitTrap.xy / max(pattern_scale * 0.25, 0.001);
        float pt  = -(TIME * color_speed + syn_BassTime * color_speed * 0.15);
        mat2  pr2 = mat2(cos(pt), sin(pt), -sin(pt), cos(pt));
        suv = abs(mod(suv * pr2, 1.0/8.0) - 1.0/16.0);
        float spat = smoothstep(0.0, 0.012, length(suv) - 1.0/32.0);
        spat = min(spat, smoothstep(0.0, 0.012,
               abs(max(suv.x, suv.y) - 1.0/16.0) - 0.04/16.0));

        float sdir = mod(c1 * 8.0, 2.0) < 1.0 ? -1.0 : 1.0;
        vec3 spatCol = sdir < 0.0
            ? surfCol * min(spat, 1.0)
            : (sqrt(max(surfCol, vec3(0.0))) * 0.5 + 0.7) * max(1.0 - spat, 0.0);
        surfCol = mix(surfCol, spatCol, 0.65);

        // Lighting
        vec3  lDir = normalize(vec3(1.2, 1.5, 0.8));
        float diff = max(dot(n, lDir), 0.0) * 0.65 + 0.35;
        float spec = pow(max(dot(reflect(-lDir, n), -rd), 0.0), 32.0) * 0.4;
        surfCol = surfCol * diff + vec3(spec * (0.4 + c1 * 0.6));

        // Cheap AO: darker in the hit because the glow already lights it
        surfCol *= 0.85;

        // Depth fog toward glow color
        surfCol *= exp(-hitT * 2.0 / draw_distance);

        glowColor += surfCol;
    }

    // ================================================================
    //  Final compositing
    // ================================================================

    // Bass brightness pulse
    glowColor *= 1.0 + syn_BassLevel * 0.5;

    // Background: very dim directional color so "empty" areas aren't dead black
    vec3 bgCol = fractalPalette(
        dot(rd, vec3(0.3, 0.6, 0.7)) * 0.3 + timeOff * 0.2 + 0.5,
        base_hue + 0.5
    ) * 0.04;
    // Sparse star field
    vec3  sv = floor(rd * 280.0);
    float sh = fract(sin(dot(sv, vec3(12.9898, 78.233, 45.164))) * 43758.5453);
    bgCol += vec3(pow(max(sh - 0.978, 0.0) / 0.022, 2.0)) * (0.5 + syn_BassLevel * 0.5);

    vec3 col = glowColor + bgCol * max(1.0 - length(glowColor) * 2.0, 0.0);

    // Vignette
    col *= pow(16.0 * (1.0-_uv.x)*(1.0-_uv.y)*_uv.x*_uv.y, 1.0/8.0) * 1.15;

    // Reinhard tone map: maps [0, ∞) → [0, 1) so overexposure → vivid, never white
    col /= (col + vec3(1.0));

    // Gamma (sqrt ≈ 2.0)
    return vec4(sqrt(max(col, vec3(0.0))), 1.0);
}
