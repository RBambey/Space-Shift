// ============================================================
//  WARPER — v1.0
//  Created by RBambey
//  Based on polar-warp tunnel shader (Shadertoy)
//  Procedural hash replaces iChannel0 noise texture
// ============================================================

const float PI = 3.14159265;

// ---- Hash (replaces iChannel0 noise texture) ----
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash2(vec2 p) {
    return vec2(hash(p), hash(p + vec2(1.7, 3.1)));
}

// ---- 2D rotation ----
vec2 rot2(vec2 v, float a) {
    float c = cos(a), s = sin(a);
    return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// ============================================================
vec4 renderMain() {

    // ---- Centered, aspect-normalised coordinates ----
    // Matches original: p = (p + p - r) / sqrt(r.x * r.y) * 0.1
    vec2 p = _uvc * 2.0 * RENDERSIZE / sqrt(RENDERSIZE.x * RENDERSIZE.y) * 0.1;

    // ---- 2D camera from script.js ----
    // Pitch/yaw shift the vortex centre; roll rotates the view
    p -= vec2(warp_yaw, warp_pitch) * 0.04;
    p  = rot2(p, warp_roll);

    // ---- Inversion warp (from original) ----
    float f = length(p) - 0.001 / length(p);
    p -= p / dot(p, p) * 0.001;

    // ---- Speed — bass swells the rate ----
    float speed = fly_speed * (1.0 + syn_BassLevel * bass_reactivity * 0.4);

    // ---- Main accumulation loop ----
    vec4 c = vec4(0.0, 0.0, 0.0, 1.0);

    for (float i = 1.0; i < 14.0; i++) {
        // kY0 = k.y before time offset; used in denominator to match original
        float kY0  = 0.003 / length(p) * i;
        float tSgn = TIME * speed * sign(f);
        vec2  k    = vec2(atan(p.y, p.x) / PI + 100.0, kY0 + tSgn);

        for (float j = 0.0; j < 16.0; j++) {
            // Procedural replacement for texture(iChannel0, ...).xy
            vec2 texCoord = floor(fract((k + j / 16.0) / 2.0) * 2.0
                                  + i * 7.0 + j * 4.0)
                            / 256.0 + j * 137.0 / 256.0;
            vec2 texSample = hash2(texCoord) * 0.9 + 0.05;

            vec2 o = fract(k + j / 12.0) - texSample;

            c.xyz += min(
                pow(max(0.3 / (length(o) / 0.08) - 0.01, 0.0), 2.0)
                * (sin((j * 0.25 - i * 0.65) + TIME * speed
                       + vec3(0.0, 2.0, 4.0) / 3.0 * PI) * 0.5 + 0.5),
                3.5)
                / (0.8 * kY0 + 1.0)
                * (1.0 - i / 14.0);
        }
    }

    // ---- Bass hit pulses brightness ----
    c.xyz *= 1.0 + syn_BassHits * bass_reactivity * 0.5;

    return c;
}
