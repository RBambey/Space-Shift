// ============================================================
//  WARPER — v1.2
//  Created by RBambey
//  Based on polar-warp tunnel shader (Shadertoy)
//  Procedural hash replaces iChannel0 noise texture
// ============================================================

// ---- Sin-free hash2 — polynomial, two values in one pass ----
// Replaces the sin()-based hash: eliminates ~400 sin() calls per pixel.
vec2 hash2(vec2 p) {
    p  = fract(p * vec2(443.897, 441.423));
    p += dot(p, p.yx + 19.19);
    return fract(vec2(p.x * p.y, (p.x + p.y) * p.x));
}

// ---- 2D rotation ----
vec2 rot2(vec2 v, float a) {
    float c = cos(a), s = sin(a);
    return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// ============================================================
vec4 renderMain() {

    // ---- Centered, aspect-normalised coordinates ----
    // _uvc.x already has aspect ratio baked in, so use RENDERSIZE.y uniformly for both
    // axes — avoids double-applying aspect and keeps circles perfectly round.
    vec2 p = _uvc * (2.0 * RENDERSIZE.y / sqrt(RENDERSIZE.x * RENDERSIZE.y)) * 0.1;

    // ---- 2D camera from script.js ----
    // Pitch/yaw offset scaled for ~60° effective range; roll rotates the view
    p -= vec2(warp_yaw * 0.09, warp_pitch * 0.05);
    p  = rot2(p, warp_roll);

    // ---- Inversion warp — invScale audio-reactive so centre sphere breathes with bass ----
    // At silence: sphere radius = sqrt(0.001) ≈ 0.032; at peak bass: sqrt(0.005) ≈ 0.071
    float invScale = 0.001 + syn_BassLevel * bass_reactivity * 0.004;
    float pLen0    = length(p);
    float f        = pLen0 - invScale / pLen0;
    p -= p / dot(p, p) * invScale;

    // ---- Hoist loop-invariant values out of both loops ----
    float pLen   = max(length(p), 1e-5);          // post-inversion length (guard zero)
    float tOff   = warp_time * sign(f);            // travel offset — same for every i, j
    float kAngle = atan(p.y, p.x) / PI + 100.0;   // angular coordinate — same for every i, j

    // Colour phase offsets: vec3(0,2,4)/3*PI — precomputed constant
    const vec3 kPhase = vec3(0.0, 2.09440, 4.18879);

    // ---- Main accumulation loop ----
    vec4 c = vec4(0.0, 0.0, 0.0, 1.0);

    for (float i = 1.0; i < 14.0; i++) {
        float kY0   = 0.003 / pLen * i;
        float denom = 0.8 * kY0 + 1.0;         // hoisted — constant across inner loop
        float fade  = 1.0 - i / 14.0;           // hoisted — constant across inner loop
        float colA  = warp_time - i * 0.65;     // hoisted — partial colour angle (j term inside)
        vec2  k     = vec2(kAngle, kY0 + tOff);

        for (float j = 0.0; j < 12.0; j++) {   // 16 → 12: 25% fewer iterations
            vec2 texCoord  = floor(fract((k + j / 16.0) / 2.0) * 2.0
                                   + i * 7.0 + j * 4.0)
                             / 256.0 + j * 137.0 / 256.0;
            vec2 texSample = hash2(texCoord) * 0.9 + 0.05;

            vec2  o   = fract(k + j / 12.0) - texSample;
            float v   = max(0.3 / (length(o) / 0.08) - 0.01, 0.0);
            vec3  col = sin(colA + j * 0.25 + kPhase) * 0.5 + 0.5;

            c.xyz += min(v * v, 3.5) * col / denom * fade;  // v*v replaces pow(v,2)
        }
    }

    // ---- Bass hit pulses brightness ----
    c.xyz *= 1.0 + syn_BassHits * bass_reactivity * 0.5;

    return c;
}
