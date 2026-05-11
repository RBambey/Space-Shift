// ============================================================
//  STAR FLIGHT — v1.2
//  Created by RBambey
//  Fly through a star field. Audio reactive.
// ============================================================

mat3 rotX(float a) { float c=cos(a),s=sin(a); return mat3(1,0,0, 0,c,-s, 0,s,c); }
mat3 rotY(float a) { float c=cos(a),s=sin(a); return mat3(c,0,s, 0,1,0, -s,0,c); }
mat3 rotZ(float a) { float c=cos(a),s=sin(a); return mat3(c,-s,0, s,c,0, 0,0,1); }

float hash1(float n) { return fract(sin(n) * 43758.5453); }
float hash1(vec2 p)  { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash1(vec3 p)  { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
vec3  hash3(vec3 p)  {
    return fract(sin(vec3(dot(p,vec3(127.1,311.7,74.7)),
                          dot(p,vec3(269.5,183.3,246.1)),
                          dot(p,vec3(113.5,271.9,124.6)))) * 43758.5453);
}

// ---- Render one star at screen position sUV ----
vec3 renderStar(vec2 pixUV, vec2 sUV, float h, vec3 h3, vec2 streak, float boost) {
    vec2 delta = pixUV - sUV;

    // Capsule distance — point when no streak, elongated when fast
    float dist2D;
    float sLen = length(streak);
    if (sLen > 0.001) {
        vec2  sDir = streak / sLen;
        float t    = clamp(dot(delta, sDir), 0.0, sLen);
        dist2D     = length(delta - sDir * t);
    } else {
        dist2D = length(delta);
    }

    // ---- Stellar classification ----
    // IMPORTANT: use h3.y for type, NOT h, because h is the threshold hash.
    // Only the top few % of h values survive the density test, so using h
    // would make every visible star fall into the same spectral class.
    // h3.y is independent of h and uniformly distributed across all stars.
    float hT   = h3.y;                          // type selector  [0,1]
    float lumV = fract(h3.x * 7.3 + h3.z);     // luminosity jitter [0,1]

    vec3  starCol;
    float sz;   // angular core radius (UV units)
    float lum;  // base luminosity

    if (hT < 0.18) {
        // O/B — blue, rare, very bright
        starCol = mix(vec3(0.50, 0.70, 1.00), vec3(0.75, 0.88, 1.00), h3.x);
        sz  = 0.0016 + h3.z * 0.003;
        lum = 2.0 + lumV * 3.5;
    } else if (hT < 0.40) {
        // A/F — white to warm white
        starCol = mix(vec3(0.95, 0.97, 1.00), vec3(1.00, 0.98, 0.92), h3.x);
        sz  = 0.001 + h3.z * 0.0018;
        lum = 0.9 + lumV * 1.1;
    } else if (hT < 0.62) {
        // G — yellow-white (sun-like)
        starCol = mix(vec3(1.00, 0.94, 0.74), vec3(1.00, 0.87, 0.52), h3.x);
        sz  = 0.0007 + h3.z * 0.0013;
        lum = 0.45 + lumV * 0.55;
    } else if (hT < 0.78) {
        // K — orange, dimmer
        starCol = mix(vec3(1.00, 0.70, 0.28), vec3(1.00, 0.53, 0.14), h3.x);
        sz  = 0.0005 + h3.z * 0.001;
        lum = 0.28 + lumV * 0.35;
    } else {
        // M — red dwarfs; only top 5% of M-type become red giants
        float giant = step(0.95, h3.z);
        starCol = mix(vec3(1.00, 0.30, 0.08), vec3(1.00, 0.50, 0.20), h3.x);
        sz  = mix(0.0005, 0.0045, giant);
        lum = mix(0.18, 2.2, giant) + lumV * 0.2;
    }

    float core = smoothstep(sz, 0.0, dist2D);

    // Gaussian glow — decays as exp(-d²) so it drops to near-zero within
    // 2–3 sigma, preventing bleed into neighbouring cells (no square halos).
    float sigma = sz * 3.5 + 0.0005;
    float dSig  = dist2D / sigma;
    float glow  = exp(-dSig * dSig) * 0.35 * lum;

    return starCol * (core * lum + glow) * (1.0 + boost * 1.8);
}

// ============================================================
vec4 renderMain() {

    vec3 ro        = vec3(cam_x, cam_y, cam_z);
    mat3 camRot    = rotY(cam_yaw) * rotZ(cam_roll) * rotX(cam_pitch);
    mat3 camRotInv = transpose(camRot);

    vec2 uv = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd = normalize(camRot * vec3(uv.x, uv.y, 1.0));

    // Bass pulse: expanding ring from screen centre
    float screenDist = length(_uv - 0.5) * 2.0;
    float ringPhase  = screenDist * 9.0 - syn_BassTime * 9.0;
    float bassRipple = pow(clamp(sin(ringPhase) * 0.5 + 0.5, 0.0, 1.0), 2.0) * syn_BassLevel;
    float bassBoost  = bassRipple * 2.5 + syn_BassLevel * 0.3;

    // Streak scale: quadratic so low speed = subtle, max speed = warp.
    float spd         = fly_speed / 300.0;
    float streakScale = spd * spd * 0.45 + spd * 0.005;

    // Deep space background
    vec3 col = vec3(0.0, 0.008, 0.035);

    // ---- Stars — three world-space scales ----
    if (star_count > 0.01) {

        // Scale A: close  (CELL=6, ~132 units depth)
        float CELL_A = 6.0;
        for (int i = 0; i < 22; i++) {
            float depth = (float(i) + 0.5) * CELL_A;
            vec3  P     = ro + rd * depth;
            vec3  cID   = floor(P / CELL_A);
            float h     = hash1(cID);
            // Cluster: coarse hash over groups of 5 cells creates dense/sparse regions
            float cluster = hash1(floor(cID / 5.0) * vec3(7.3, 11.7, 5.1));
            float thr_A   = 1.0 - star_count * 0.08 * (0.4 + cluster * 0.9);
            if (h > thr_A) {
                vec3 h3      = hash3(cID);
                vec3 starPos = (cID + 0.15 + h3 * 0.7) * CELL_A;
                vec3 sc      = camRotInv * (starPos - ro);
                if (sc.z > 0.1) {
                    vec2 sUV = sc.xy / sc.z;
                    if (abs(sUV.x) < 2.8 && abs(sUV.y) < 1.8) {
                        float rad   = length(sUV);
                        vec2 streak = (rad > 0.005) ? -normalize(sUV) * streakScale * rad : vec2(0.0);
                        col += renderStar(uv, sUV, h, h3, streak, bassBoost);
                    }
                }
            }
        }

        // Scale B: medium (CELL=22, ~484 units depth)
        float CELL_B = 22.0;
        for (int i = 0; i < 22; i++) {
            float depth = (float(i) + 0.5) * CELL_B;
            vec3  P     = ro + rd * depth;
            vec3  cID   = floor(P / CELL_B);
            float h     = hash1(cID);
            float cluster = hash1(floor(cID / 4.0) * vec3(13.1, 7.9, 3.7));
            float thr_B   = 1.0 - star_count * 0.12 * (0.4 + cluster * 0.9);
            if (h > thr_B) {
                vec3 h3      = hash3(cID);
                vec3 starPos = (cID + 0.15 + h3 * 0.7) * CELL_B;
                vec3 sc      = camRotInv * (starPos - ro);
                if (sc.z > 0.1) {
                    vec2 sUV = sc.xy / sc.z;
                    if (abs(sUV.x) < 2.8 && abs(sUV.y) < 1.8) {
                        float rad   = length(sUV);
                        vec2 streak = (rad > 0.005) ? -normalize(sUV) * streakScale * 0.55 * rad : vec2(0.0);
                        col += renderStar(uv, sUV, h, h3, streak, bassBoost);
                    }
                }
            }
        }

        // Scale C: distant (CELL=80, ~1440 units depth)
        float CELL_C = 80.0;
        for (int i = 0; i < 18; i++) {
            float depth = (float(i) + 0.5) * CELL_C;
            vec3  P     = ro + rd * depth;
            vec3  cID   = floor(P / CELL_C);
            float h     = hash1(cID);
            float cluster = hash1(floor(cID / 3.0) * vec3(5.7, 17.3, 9.1));
            float thr_C   = 1.0 - star_count * 0.18 * (0.4 + cluster * 0.9);
            if (h > thr_C) {
                vec3 h3      = hash3(cID);
                vec3 starPos = (cID + 0.15 + h3 * 0.7) * CELL_C;
                vec3 sc      = camRotInv * (starPos - ro);
                if (sc.z > 0.1) {
                    vec2 sUV = sc.xy / sc.z;
                    if (abs(sUV.x) < 2.8 && abs(sUV.y) < 1.8) {
                        float rad   = length(sUV);
                        vec2 streak = (rad > 0.005) ? -normalize(sUV) * streakScale * 0.25 * rad : vec2(0.0);
                        col += renderStar(uv, sUV, h, h3, streak, bassBoost) * 0.7;
                    }
                }
            }
        }
    }

    // Bass centre flash
    float centerGlow = exp(-screenDist * screenDist * 4.0) * syn_BassLevel;
    col += vec3(0.4, 0.6, 1.0) * centerGlow * 1.8;

    // Tone-map
    col = col / (col + 0.6);
    col = pow(col, vec3(0.85));

    return vec4(col, 1.0);
}
