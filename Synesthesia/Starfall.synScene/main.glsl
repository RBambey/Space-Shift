// ============================================================
//  STARFALL — v1.0
//  Created by RBambey
//  Based on "Smaller Waterfall" by mrange (CC0 1.0)
//  https://www.shadertoy.com/view/mtyGWy
//  Adapted to 3D spherical sky with Ocean Planet flying camera.
//  The 4D ray march is replaced by spherical projection of the
//  ray direction; 14 depth layers give parallax as you fly.
// ============================================================

vec4 renderMain() {

    // ---- Camera ----
    vec3 ro     = vec3(cam_x, cam_y, cam_z);
    vec3 cRight = vec3(cam_rx, cam_ry, cam_rz);
    vec3 cUp    = vec3(cam_ux, cam_uy, cam_uz);
    vec3 cFwd   = vec3(cam_fx, cam_fy, cam_fz);
    vec2 uv     = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd     = normalize(cFwd + cRight * uv.x + cUp * uv.y);

    // ---- Spherical coords of ray direction ----
    // az: azimuth around world Y, normalised to [-0.5, 0.5]
    // el: elevation in radians, range [-PI/2, PI/2]
    float az = atan(rd.x, rd.z) * (0.5 / PI);
    float el = asin(clamp(rd.y, -0.9999, 0.9999));

    // ---- Background: deep space ----
    vec4 O = vec4(0.01, 0.005, 0.02, 0.0);           // dark purple-blue base
    O.xyz += vec3(0.02, 0.04, 0.10)
           * pow(max(dot(rd, cFwd), 0.0), 10.0);     // subtle forward glow

    // ---- Streak parameters (from original shader) ----
    float T  = starfall_time;        // accumulated time × fall_speed (from script.js)
    vec2  Y  = vec2(5e-3, 1.0);     // column width (az), row height (el radians)
    float sz = 5e-4;                // dot/streak radius

    // AA kernel — computed once before the loop from the base az/el coordinates
    vec2 r = vec2(length(fwidth(vec2(az, el))));

    // ---- 14 depth layers ----
    // j=0 is the closest layer (brightest, largest, most parallax, fastest scroll).
    // j=13 is the farthest (dim, tiny, barely shifts, slow scroll).
    // Four depth cues stack: scroll speed, dot size, brightness, and parallax shift.
    for (float j = 0.0; j < 14.0; j += 1.0) {
        float depth = j + 1.0;
        float inv_d = 1.0 / depth;

        // Parallax: closer layers shift much more with lateral camera movement
        float az_p = az + cam_x * 0.008 * inv_d;
        float el_p = el - cam_y * 0.005 * inv_d;

        // Slight az sub-sample offset per layer — increases visible streak density
        vec2 C = vec2(az_p + j * Y.x / 8.0, el_p);

        // Fall: strong speed differential — closest layer 5× faster than farthest.
        // Close streaks zip past; far ones drift. This is the primary depth cue.
        C.y -= T * (0.2 + inv_d * 0.8);

        // Unique random value per (layer, az-cell, el-cell).
        // vec3(float, vec2) constructs vec3(j+1, floor(C/Y).x, floor(C/Y).y) — valid GLSL.
        float i = fract(sin(dot(vec3(j + 1.0, floor(C / Y)),
                               vec3(7.0, 73.1, 37.7))) * 4375.5);

        // Position within cell, wrapped to [-Y/2, Y/2]
        vec2 P = C - (T + T * i) * vec2(0.0, 1.0);
        P -= round(P / Y) * Y;

        // Per-streak colour: full-spectrum HSL-like cycle driven by time + random phase.
        // col.w oscillates 0-2 and gates overall brightness (streaks pulse in/out).
        vec4 col = 1.0 + sin(T + 7.0 * fract(8663.0 * i) + vec4(0.0, 1.0, 2.0, 4.0));

        // Depth-scaled dot size: close streaks appear physically larger.
        // j=0: sz*3 (big), j=13: sz*1.07 (tiny)
        float sz_d = sz * (1.0 + inv_d * 2.0);

        // Streak shape (from original):
        //   Shape A — exp(19*P.y) weight:
        //     P.y > 0 → circular distance → glowing round HEAD of streak
        //     P.y < 0 → |P.x| only (max clamps y to 0) → narrow TAIL fades away
        //   Shape B — constant weight 3: pure dot at center
        // The exp(19*P.y) makes the head very bright just above P.y=0 and fades the tail.
        vec2 sdf = vec2(
            length(max(P, vec2(-1.0, 0.0))),  // A: head circle / tail horizontal slice
            length(P)                          // B: dot
        ) - sz_d;

        float brightness = exp(-j * 0.4);     // sharp falloff — close layers pop, far ones recede
        O += dot(smoothstep(r, -r, sdf), vec2(exp(19.0 * P.y), 3.0))
             * col * col.w * brightness;
    }

    // ---- Bass reactivity ----
    O.xyz *= 1.0 + syn_BassHits * bass_reactivity * 0.5;   // hit pulse
    O.xyz += vec3(0.005, 0.01, 0.02) * syn_BassLevel * bass_reactivity; // sustained glow

    // ---- Tonemap: sqrt(tanh(O − bias)) from original ----
    // Clamp before sqrt to avoid NaN on dark pixels where O < bias.
    vec3 bias = vec3(0.04, 0.08, 0.02);
    return vec4(sqrt(max(tanh(O.xyz - bias), vec3(0.0))), 1.0);
}
