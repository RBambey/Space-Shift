// ============================================================
//  DINO PLANET — v0.2 (forked from Forest Planet v3.0)
//  RBambey
//  6-DOF flight from Ocean Planet by RBambey.
//
//  Trees: traditional conifers — a cylindrical trunk topped by a tapering
//         conical canopy (rippled radius for a layered-bough look).
//         Per-tile hashes give each tree its own height, girth, and jitter
//         off the grid. Wind sway scales with height; tree_density now
//         controls canopy fullness (0 = bare trunks, 1+ = full canopy).
//  Render: solid opaque single-hit raymarching. No transparency.
//
//  Dinos: sauropods built from smooth-blended capsule/ellipsoid SDFs,
//         proportions ported from Blender/DinoPlanet/dino_blockout.blend.
//         Sparsely placed one-per-cell (see DINO_CELL), walk-in-place gait
//         + grazing neck bob + tail sway, all driven by TIME.
// ============================================================

const float TREE_SCALE = 8.0;
const float DINO_CELL  = 120.0;   // world units per dino placement cell

float gDinoMix     = 0.0;   // 1.0 when DE()'s last winning branch was the dino
float gDinoHash    = 0.0;   // per-instance hash, for hide-color variation
float gTreeCanopy  = 0.0;   // 1.0 when the last winning tree part was canopy, not trunk

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

const vec3 SUN_DIR = vec3(0.770, 0.125, 0.626);   // low, dusk-angle sun
const vec3 SUN_COL = vec3(1.0, 0.45, 0.22);        // deep dusk orange

const float HIT_EPS  = 0.04;   // surface hit threshold (world units)
const float NORM_EPS = 0.05;   // normal finite-difference step

// ---- Pine tree primitive -------------------------------------------------

// Straight trunk: cylinder from y=0 to y=h, radius r.
float pineTrunk(vec3 p, float h, float r) {
    return max(length(p.xz) - r, abs(p.y - h * 0.5) - h * 0.5);
}

// Conical canopy: wide at y=0, tapering to a point at y=h. The radius wobble
// gives the silhouette a layered-bough texture instead of a smooth cone.
float pineCanopy(vec3 p, float h, float baseR) {
    float taper = clamp(p.y / h, 0.0, 1.0);
    float r     = baseR * (1.0 - taper);
    r          *= 1.0 + 0.12 * sin(p.y * 9.0 + baseR * 30.0);
    float cone  = max(length(p.xz) - max(r, 0.0), abs(p.y - h * 0.5) - h * 0.5);
    float tip   = length(p - vec3(0.0, h, 0.0)) - baseR * 0.03;  // rounds the apex
    return min(cone, tip);
}

float pineTree(vec3 p, float trunkH, float trunkR, float canopyH, float canopyR) {
    float trunk = pineTrunk(p, trunkH, trunkR);

    vec3  cp = p;
    cp.y -= trunkH * 0.30;   // canopy overlaps the lower trunk
    float canopy = pineCanopy(cp, canopyH, canopyR);

    gTreeCanopy = step(canopy, trunk);
    return min(trunk, canopy);
}

// ---- Dino primitives -----------------------------------------------------

float sdCapsule(vec3 p, vec3 a, vec3 b, float ra, float rb) {
    vec3  pa = p - a, ba = b - a;
    float h  = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - mix(ra, rb, h);
}

float sdEllipsoid(vec3 p, vec3 r) {
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

float dsmin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// One leg: capsule from hip/shoulder down to a foot that swings on `s`
// (an already-phased sine), plus a flattened foot pad.
float dinoLeg(float dAcc, vec3 p, float s, float legX, float legZBase, float topH, float r) {
    float footZ = legZBase + s * 0.9;
    float footY = 0.18 + max(0.0, s) * 0.35;
    vec3  top   = vec3(legX, topH,  legZBase);
    vec3  foot  = vec3(legX, footY, footZ);
    dAcc = dsmin(dAcc, sdCapsule(p, top, foot, r, r * 0.85), 0.4);
    dAcc = min(dAcc, sdEllipsoid(p - vec3(legX, footY - 0.02, footZ), vec3(r * 1.15, 0.18, r * 1.05)));
    return dAcc;
}

// Sauropod, blocked out in Blender/DinoPlanet/dino_blockout.blend and ported
// here as smooth-blended capsule/ellipsoid primitives. Local space: +Z
// forward (head end), +X right, +Y up, feet resting on y = 0. `phase`
// staggers the walk/graze cycle per instance so every dino isn't in lockstep.
float dinoDE(vec3 p, float dscale, float phase) {
    p /= dscale;

    const float BODY_LEN = 5.2, BODY_WID = 2.6, BODY_HGT = 3.0;
    const float SHOULDER_H = 4.4, HIP_H = 3.6;
    const float NECK_LEN = 6.0, TAIL_LEN = 7.5;
    float bodyCz = SHOULDER_H - BODY_HGT * 0.15;

    float d = sdEllipsoid(p - vec3(0.0, bodyCz, 0.0),
                          vec3(BODY_WID * 0.5, BODY_HGT * 0.5, BODY_LEN * 0.5));

    // Neck + head: slow grazing bob
    float graze    = sin(TIME * 0.35 + phase) * 0.5;
    vec3  neckBase = vec3(0.0, bodyCz + BODY_HGT * 0.25, BODY_LEN * 0.42);
    vec3  prev     = neckBase;
    for (int i = 1; i <= 4; i++) {
        float t   = float(i) / 4.0;
        float fwd = sin(t * 1.5707963) * NECK_LEN * 0.8;
        float up  = (1.0 - cos(t * 1.5707963)) * NECK_LEN * 0.9 + graze * t;
        vec3  cur = neckBase + vec3(0.0, up, fwd);
        float r0  = max(0.55 - 0.10 * float(i - 1), 0.18);
        float r1  = max(0.55 - 0.10 * float(i),      0.16);
        d = dsmin(d, sdCapsule(p, prev, cur, r0, r1), 0.35);
        prev = cur;
    }
    vec3 headPos = prev + vec3(0.0, 0.15 + graze, 0.3);
    d = dsmin(d, sdEllipsoid(p - headPos, vec3(0.30, 0.32, 0.55)), 0.25);

    // Tail: tapering, swaying side to side
    float sway     = sin(TIME * 0.6 + phase + 1.3) * 0.6;
    vec3  tailBase = vec3(0.0, bodyCz - BODY_HGT * 0.05, -BODY_LEN * 0.48);
    prev = tailBase;
    for (int i = 1; i <= 5; i++) {
        float t     = float(i) / 5.0;
        float back  = t * TAIL_LEN;
        float droop = -0.4 * sin(t * 1.8849556);
        vec3  cur   = tailBase + vec3(sway * t * t, droop, -back);
        float r0    = max(0.65 - 0.12 * float(i - 1), 0.04);
        float r1    = max(0.65 - 0.12 * float(i),      0.03);
        d = dsmin(d, sdCapsule(p, prev, cur, r0, r1), 0.30);
        prev = cur;
    }

    // Legs: walking-in-place gait, diagonal pairs in phase
    float wt = TIME * 1.6 + phase;
    float sA = sin(wt);               // front-left / rear-right
    float sB = sin(wt + 3.14159265);  // front-right / rear-left
    float legXf =  BODY_LEN * 0.30, legXr = -BODY_LEN * 0.32;
    float legY  =  BODY_WID * 0.38;

    d = dinoLeg(d, p, sA,  legY, legXf, SHOULDER_H, 0.62);
    d = dinoLeg(d, p, sB, -legY, legXf, SHOULDER_H, 0.62);
    d = dinoLeg(d, p, sB,  legY, legXr, HIP_H,      0.70);
    d = dinoLeg(d, p, sA, -legY, legXr, HIP_H,      0.70);

    return d * dscale;
}

// One tiny T-rex arm: two segments plus a small clawed hand.
float trexArm(float dAcc, vec3 p, float armX, vec3 shoulder) {
    vec3 sh    = vec3(armX, shoulder.y, shoulder.z);
    vec3 elbow = sh + vec3(0.0, -0.35, 0.20);
    vec3 hand  = elbow + vec3(0.0, -0.28, 0.12);
    dAcc = dsmin(dAcc, sdCapsule(p, sh, elbow, 0.13, 0.10), 0.15);
    dAcc = dsmin(dAcc, sdCapsule(p, elbow, hand, 0.10, 0.07), 0.12);
    dAcc = min(dAcc, sdEllipsoid(p - hand, vec3(0.07, 0.06, 0.10)));
    return dAcc;
}

// One T-rex leg: thigh -> shin -> digitigrade foot, plus 3 forward toes.
// `stride` (an already-phased sine) drives the walk cycle, `lift` raises
// the foot as it swings forward.
float trexLeg(float dAcc, vec3 p, float legX, float hipH, float kneeH, float ankleH,
              float toeH, float stride, float lift) {
    vec3 hip     = vec3(legX, hipH,        0.0);
    vec3 knee    = vec3(legX, kneeH,       0.35 + stride * 0.3);
    vec3 ankle   = vec3(legX, ankleH,      0.20 + stride * 0.6);
    vec3 toeBase = vec3(legX, toeH + lift, 0.75 + stride);

    dAcc = dsmin(dAcc, sdCapsule(p, hip, knee, 0.55, 0.38), 0.4);
    dAcc = dsmin(dAcc, sdCapsule(p, knee, ankle, 0.38, 0.22), 0.35);
    dAcc = dsmin(dAcc, sdCapsule(p, ankle, toeBase, 0.22, 0.16), 0.3);

    for (int i = -1; i <= 1; i++) {
        vec3 toeTip = toeBase + vec3(float(i) * 0.16, -0.03, 0.55);
        dAcc = min(dAcc, sdCapsule(p, toeBase, toeTip, 0.10, 0.03));
    }
    return dAcc;
}

// Bipedal theropod, blocked out in Blender/DinoPlanet/trex_blockout.blend.
// Same local-space convention as dinoDE: +Z forward, +X right, +Y up, feet
// resting on y = 0. Torso pivots over the hips rather than a fixed spine,
// matching the modern horizontal, tail-counterbalanced pose.
float trexDE(vec3 p, float dscale, float phase) {
    p /= dscale;

    const float HIP_H = 3.6;
    const float TORSO_LEN = 4.6, TORSO_WID = 1.7, TORSO_HGT = 2.1;

    vec3  torsoC = vec3(0.0, HIP_H + 0.15, TORSO_LEN * 0.28);
    float d = sdEllipsoid(p - torsoC, vec3(TORSO_WID * 0.5, TORSO_HGT * 0.5, TORSO_LEN * 0.5));

    // Neck + head: short and thick, gentle stalking bob
    float bob        = sin(TIME * 0.9 + phase) * 0.15;
    vec3  chestFront = torsoC + vec3(0.0, TORSO_HGT * 0.12, TORSO_LEN * 0.46);
    vec3  neckMid    = chestFront + vec3(0.0, 0.55 + bob * 0.3, 0.65);
    vec3  neckTop    = neckMid + vec3(0.0, 0.35 + bob, 0.5);
    d = dsmin(d, sdCapsule(p, chestFront, neckMid, 0.62, 0.55), 0.35);
    d = dsmin(d, sdCapsule(p, neckMid, neckTop, 0.55, 0.50), 0.3);

    vec3 headC = neckTop + vec3(0.0, 0.05, 0.55);
    d = dsmin(d, sdEllipsoid(p - headC, vec3(0.42, 0.48, 0.55)), 0.25);
    vec3 snoutC = headC + vec3(0.0, -0.12, 0.85);
    d = dsmin(d, sdEllipsoid(p - snoutC, vec3(0.28, 0.30, 0.62)), 0.2);
    vec3 jawC = snoutC + vec3(0.0, -0.20, 0.05);
    d = dsmin(d, sdEllipsoid(p - jawC, vec3(0.22, 0.16, 0.55)), 0.15);

    // Tail: tapering, swaying, drooping toward the tip
    float sway     = sin(TIME * 0.5 + phase + 2.1) * 0.5;
    vec3  tailBase = vec3(0.0, HIP_H + TORSO_HGT * 0.05, -TORSO_LEN * 0.30);
    vec3  prevT    = tailBase;
    for (int i = 1; i <= 6; i++) {
        float t     = float(i) / 6.0;
        float back  = t * 6.4;
        float droop = -0.55 * pow(t, 1.6);
        vec3  cur   = tailBase + vec3(sway * t * t, droop, -back);
        float r0    = max(0.60 - 0.095 * float(i - 1), 0.03);
        float r1    = max(0.60 - 0.095 * float(i),      0.025);
        d = dsmin(d, sdCapsule(p, prevT, cur, r0, r1), 0.3);
        prevT = cur;
    }

    // Tiny arms — deliberately small next to the hind legs
    float armSide  = TORSO_WID * 0.45;
    vec3  shoulder = torsoC + vec3(0.0, TORSO_HGT * 0.25, TORSO_LEN * 0.30);
    d = trexArm(d, p,  armSide, shoulder);
    d = trexArm(d, p, -armSide, shoulder);

    // Legs: a biped alternates left/right, unlike the sauropod's 4-beat gait
    float wt      = TIME * 1.8 + phase;
    float strideL = sin(wt);
    float strideR = sin(wt + 3.14159265);
    float legSide = TORSO_WID * 0.55;
    d = trexLeg(d, p,  legSide, HIP_H, HIP_H * 0.55, HIP_H * 0.18, 0.16, strideL, max(0.0, strideL) * 0.4);
    d = trexLeg(d, p, -legSide, HIP_H, HIP_H * 0.55, HIP_H * 0.18, 0.16, strideR, max(0.0, strideR) * 0.4);

    return d * dscale;
}

// ---- Terrain (rolling hills) -----------------------------------------------

float terrainHash(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 17.5);
    return fract(p.x * p.y);
}

float terrainNoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(terrainHash(i),               terrainHash(i + vec2(1.0, 0.0)), f.x),
               mix(terrainHash(i + vec2(0.0, 1.0)), terrainHash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Gentle rolling hills. Takes p-space xz (world xz / TREE_SCALE); returns
// height in the same p-space (multiply by TREE_SCALE for world units).
// Kept in sync with the matching terrainHeight() in script.js, which the
// flight camera uses to keep clearance above the actual ground.
float terrainHeight(vec2 p) {
    float h = terrainNoise(p * 0.06) * 1.0;
    h += terrainNoise(p * 0.15 + 11.3) * 0.4;
    return h;
}

// ---- Scene SDF ---------------------------------------------------------

float DE(vec3 p0) {
    vec3  p  = p0 / TREE_SCALE;
    p.y -= terrainHeight(p.xz);

    float tx = floor(p.x * 0.5);
    float tz = floor(p.z * 0.5);
    float h1 = fract(sin(tx * 127.1  + tz * 311.7 ) * 43758.5453);
    float h2 = fract(sin(tx * 269.5  + tz *  83.3 ) * 43758.5453);
    float h3 = fract(sin(tx *  12.9  + tz *  78.23) * 43758.5453);
    float h4 = fract(sin(tx * 173.6  + tz * 153.9 ) * 43758.5453);
    float h5 = fract(sin(tx *  47.3  + tz * 231.7 ) * 43758.5453);

    float hScale   = 0.4 + pow(h4, 1.8) * 2.0;   // mostly young/medium trees, occasional giants
    float trunkR   = (0.016 + h5 * 0.014) * (0.5 + 0.5 * hScale);
    float trunkH   = (0.55 + h1 * 0.20) * hScale;
    float canopyH  = (1.05 + h3 * 0.55) * hScale;
    float canopyR  = (0.16 + h2 * 0.09) * hScale;
    float fullness = clamp(tree_density / 1.5, 0.0, 1.0);   // 0 = bare trunks, 1+ = full canopy

    float dg = p.y;

    p.xz  = mod(p.xz, 2.0) - 1.0;                       // fold into per-tile local space
    p.xz -= (vec2(h2, h3) - 0.5) * 0.7;                 // jitter off the exact grid
    p.xz += (h1 - 0.5) * 0.06 * clamp(p.y, 0.0, 3.0);   // gentle whole-tree lean

    float d = pineTree(p, trunkH, trunkR, canopyH, canopyR * fullness);

    float terrain = min(dg * TREE_SCALE, d * TREE_SCALE);

    // ---- Dinos: at most one per large world cell — sauropod or T-rex, ----
    // ---- each with its own random size around dino_scale.             ----
    float dCellX = floor(p0.x / DINO_CELL);
    float dCellZ = floor(p0.z / DINO_CELL);
    float dh1 = fract(sin(dCellX * 269.5 + dCellZ * 183.3 + 12.9) * 43758.5453);
    float dinoDist = 100000.0;
    if (dh1 < dino_density) {
        float dh2 = fract(sin(dCellX * 127.1 + dCellZ * 311.7 +  45.1) * 43758.5453);
        float dh3 = fract(sin(dCellX *  78.2 + dCellZ *  92.7 +  91.3) * 43758.5453);
        float dh4 = fract(sin(dCellX * 191.3 + dCellZ *  57.9 + 133.7) * 43758.5453);
        float dh5 = fract(sin(dCellX *  61.7 + dCellZ * 213.1 +  27.9) * 43758.5453);
        float dh6 = fract(sin(dCellX * 143.9 + dCellZ *  39.4 + 205.2) * 43758.5453);

        float dscale = dino_scale * (0.82 + dh5 * 0.36);   // ±~18% size variety per instance

        float dinoX = (dCellX + 0.2 + dh2 * 0.6) * DINO_CELL;
        float dinoZ = (dCellZ + 0.2 + dh3 * 0.6) * DINO_CELL;
        float dinoGroundY = terrainHeight(vec2(dinoX, dinoZ) / TREE_SCALE) * TREE_SCALE;
        vec3  dinoPos = vec3(dinoX, dinoGroundY - 0.16 * dscale, dinoZ);
        float heading = dh4 * 6.28318530718;
        float ca = cos(heading), sa = sin(heading);
        vec3  lp = p0 - dinoPos;
        lp.xz = mat2(ca, -sa, sa, ca) * lp.xz;

        float phase = dh2 * 6.28318530718;
        dinoDist  = dh6 < 0.35 ? trexDE(lp, dscale, phase) : dinoDE(lp, dscale, phase);
        gDinoHash = dh2;
    }

    gDinoMix = step(dinoDist, terrain);
    return min(dinoDist, terrain);
}

// ---- Normal (tetrahedron finite differences) ---------------------------

vec3 getNormal(vec3 p) {
    const vec2 k = vec2(1.0, -1.0);
    return normalize(
        k.xyy * DE(p + k.xyy * NORM_EPS) +
        k.yyx * DE(p + k.yyx * NORM_EPS) +
        k.yxy * DE(p + k.yxy * NORM_EPS) +
        k.xxx * DE(p + k.xxx * NORM_EPS)
    );
}

// ---- Shadow (soft penumbra, standard Quilez method) --------------------

float shadow(vec3 ro, vec3 rd, float maxDist) {
    float t = 0.05, s = 1.0;
    for (int i = 0; i < 32; i++) {
        if (t > maxDist || s < 0.01) break;
        float d = DE(ro + rd * t);
        if (d < -0.01) { s = 0.0; break; }
        s = min(s, 8.0 * d / t);
        t += d * 0.8;
    }
    return clamp(s, 0.0, 1.0);
}

// ---- Cloud noise (4-octave value FBM) ----------------------------------

float cloudHash(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 17.5);
    return fract(p.x * p.y);
}

float cloudNoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(cloudHash(i),             cloudHash(i + vec2(1,0)), f.x),
               mix(cloudHash(i + vec2(0,1)), cloudHash(i + vec2(1,1)), f.x), f.y);
}

float cloudFBM(vec2 p) {
    const mat2 m = mat2(1.6, 1.2, -1.2, 1.6);
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * cloudNoise(p);
        p  = m * p;
        a *= 0.5;
    }
    return v;
}

// ---- Sun -----------------------------------------------------------------

// Returns true if ray rd hits a disc centered on dir with angular radius angR.
// Outputs sphere surface normal N and normalised 2D disc position ([-1,1] each axis).
bool sphereDisc(vec3 rd, vec3 dir, float angR, out vec3 N, out vec2 disc) {
    float md = dot(rd, dir);
    if (md < cos(angR)) return false;
    vec3 ref   = abs(dir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 right = normalize(cross(ref, dir));
    vec3 up    = cross(dir, right);
    vec3 perp  = rd - md * dir;
    disc = vec2(dot(perp, right), dot(perp, up)) / sin(angR);
    float zN = sqrt(max(0.0, 1.0 - dot(disc, disc)));
    N = normalize(-(disc.x * right + disc.y * up + zN * dir));
    return true;
}

// A single, ordinary sun at SUN_DIR — the same direction that lights the
// scene, unlike the old decorative gas-giant-and-moons vista.
vec3 addSun(vec3 sky, vec3 rd) {
    float sunR = 0.05;
    float md   = dot(rd, SUN_DIR);
    float sin2 = max(0.0, 1.0 - md * md);

    sky += SUN_COL * exp(-sin2 / (sunR * sunR * 18.0)) * 0.9;
    sky += SUN_COL * exp(-sin2 / (sunR * sunR * 55.0)) * 0.35;

    vec3 N; vec2 disc;
    if (sphereDisc(rd, SUN_DIR, sunR, N, disc)) {
        float r = sqrt(dot(disc, disc));
        sky = mix(vec3(1.0, 0.85, 0.55), vec3(0.95, 0.35, 0.15), r * r);
    }
    return sky;
}

// ---- Distant mountains ----------------------------------------------------

// Cheap skyline: a ridge-height curve as a function of azimuth angle only,
// blended in near the horizon. No raymarch cost — pure sky-dome dressing.
float mountainRidge(vec3 rd) {
    float ang = atan(rd.z, rd.x);
    float h = sin(ang * 3.0) * 0.5 + 0.5;
    h += (sin(ang * 7.3 + 1.7)  * 0.5 + 0.5) * 0.5;
    h += (sin(ang * 17.0 + 4.1) * 0.5 + 0.5) * 0.25;
    return h / 1.75;
}

vec3 addMountains(vec3 sky, vec3 rd) {
    float ridgeY = 0.02 + mountainRidge(rd) * 0.09;
    float m = smoothstep(ridgeY + 0.02, ridgeY - 0.02, rd.y);
    if (m > 0.001) {
        vec3 peakCol = mix(vec3(0.10, 0.09, 0.20), vec3(0.85, 0.55, 0.40),
                            smoothstep(ridgeY - 0.01, ridgeY + 0.01, rd.y));
        sky = mix(sky, peakCol, m);
    }
    return sky;
}

// ---- Sky ---------------------------------------------------------------

vec3 forestSky(vec3 rd, float sunDot) {
    float y   = clamp(rd.y, 0.0, 1.0);
    vec3  sky = mix(vec3(0.95, 0.55, 0.35), vec3(0.05, 0.05, 0.22), pow(y, 0.45));
    sky = mix(sky, vec3(1.0, 0.45, 0.25), exp(-abs(rd.y) * 12.0) * 0.35);

    sky = addMountains(sky, rd);
    sky = addSun(sky, rd);

    if (rd.y > 0.12) {
        float tCloud = max(80.0 - cam_y, 1.0) / rd.y;
        vec2  uv     = rd.xz * tCloud * 0.007 + TIME * vec2(0.005, 0.002);
        float c      = cloudFBM(uv * 1.8) * 0.70 + cloudFBM(uv * 4.2 + vec2(5.3, 2.1)) * 0.30;
        float alpha  = smoothstep(0.22, 0.52, c) * cloud_cover
                     * smoothstep(0.12, 0.40, rd.y);
        float dense  = smoothstep(0.48, 0.90, c);
        vec3  cCol   = mix(vec3(0.98, 0.80, 0.70), vec3(0.28, 0.26, 0.42), dense * 0.6)
                     * (sunDot * 0.2 + 0.8);
        cCol        += SUN_COL * pow(max(sunDot, 0.0), 8.0) * 0.18 * alpha;
        sky          = mix(sky, cCol, alpha);
    }

    return sky;
}

// ---- Main --------------------------------------------------------------

vec4 renderMain() {

    // Camera basis (6-DOF, driven by script.js via setUniform)
    vec3 ro = vec3(cam_x, cam_y, cam_z);
    vec2 sc = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd = normalize(vec3(cam_fx, cam_fy, cam_fz)
                      + vec3(cam_rx, cam_ry, cam_rz) * sc.x
                      + vec3(cam_ux, cam_uy, cam_uz) * sc.y);

    float sunDot = dot(rd, SUN_DIR);
    vec3  bcol   = forestSky(rd, sunDot);

    // ---- Ray march: find nearest surface ----
    float hitT = -1.0;
    float t    = 0.05;
    for (int i = 0; i < 220; i++) {
        if (t > draw_distance) break;
        float d = DE(ro + rd * t);
        if (d < HIT_EPS && d > -HIT_EPS * 0.5) { hitT = t;  break; }
        t += max(abs(d) * 0.75, HIT_EPS * 0.15);
    }

    // ---- No hit: return sky ----
    vec3 scol = bcol;

    if (hitT >= 0.0) {

        // ---- Shade hit point ----
        vec3  p    = ro + rd * hitT;
        vec3  N    = getNormal(p);
        float dHit = DE(p);   // recompute at exact hit point so the material globals reflect it, not getNormal's eps taps
        float dinoMix    = gDinoMix;
        float dinoHue    = gDinoHash;
        float treeCanopy = gTreeCanopy;
        if (dot(N, N) < 0.01) N = -rd;

        float localY   = p.y / TREE_SCALE - terrainHeight(p.xz / TREE_SCALE);  // height above local ground, not sea level
        float topFace  = smoothstep(0.0, 0.7, N.y);
        float isGround = smoothstep(0.12, 0.0, localY) * topFace;

        // Per-tree color: narrow bark/needle palette with natural variation
        // (same tile coords as DE so color is stable per tree)
        float tx_c    = floor(p.x / (TREE_SCALE * 2.0));
        float tz_c    = floor(p.z / (TREE_SCALE * 2.0));
        float treeVar  = fract(sin(tx_c * 127.1 + tz_c * 311.7) * 43758.5453);
        vec3  treeBase = mix(vec3(0.24, 0.17, 0.11), vec3(0.34, 0.24, 0.15), treeVar); // bark
        vec3  treeMid  = mix(vec3(0.05, 0.16, 0.09), vec3(0.04, 0.13, 0.08), treeVar); // shaded needles
        vec3  treeTop  = mix(vec3(0.13, 0.32, 0.17), vec3(0.17, 0.36, 0.19), treeVar); // sunlit needles

        // Material: bark / needles / forest floor, with patchy ground frost.
        // Trunk vs. canopy is picked explicitly (gTreeCanopy) rather than
        // guessed from surface angle, so the cone's sloped sides read as
        // needles, not bark.
        float varSeed   = fract(sin(p.x * 0.173 + p.z * 0.317) * 43758.5);
        float frostPatch = smoothstep(0.55, 0.85, fract(sin(p.x * 0.091 + p.z * 0.133) * 24634.6));
        vec3  groundCol = mix(vec3(0.11, 0.24, 0.11), vec3(0.80, 0.83, 0.86), frostPatch * 0.5);
        vec3  needleCol = mix(treeMid, treeTop, topFace);
        vec3  treeCol   = mix(treeBase, needleCol, treeCanopy);
        vec3 baseCol = mix(treeCol, groundCol, isGround);

        // Snow caps: upper canopy tips catch a patchy dusting of snow
        float capness   = smoothstep(0.3, 0.9, N.y) * (1.0 - isGround);
        float snowPatch = smoothstep(0.35, 0.85, varSeed);
        baseCol = mix(baseCol, vec3(0.90, 0.93, 0.97), capness * snowPatch * 0.6);

        // Dino hide: slate blue-grey back fading to a pale grey-blue underbelly
        // — deliberately cool-toned so they pop against the warm dusk forest.
        vec3  hideBack  = hsv2rgb(vec3(0.58 + dinoHue * 0.05, 0.32, 0.58));
        vec3  hideBelly = vec3(0.80, 0.84, 0.90);
        vec3  hideCol   = mix(hideBelly, hideBack, smoothstep(-0.2, 0.4, N.y));

        // On a bass hit, hides sweep through prismatic colors instead of
        // blue-grey. Each dino's hue offset (dinoHue) keeps a herd from all
        // flashing the same color at once; hue keeps drifting slowly at rest
        // and swings further with the bass envelope on a hit.
        float bassPulse = pow(clamp(syn_BassLevel, 0.0, 1.0), 1.5);
        float prismHue  = fract(dinoHue + TIME * 0.15 + bassPulse * 0.6);
        vec3  prismCol  = hsv2rgb(vec3(prismHue, 0.85, 0.62));
        hideCol = mix(hideCol, prismCol, bassPulse);

        baseCol = mix(baseCol, hideCol, dinoMix);

        // Lighting: ambient + sun + hotspot + specular
        float ndotl   = clamp(dot(N, SUN_DIR), 0.0, 1.0);
        float hotspot = smoothstep(0.55, 1.0, ndotl) * (0.4 + topFace * 0.6);
        vec3  ambient = vec3(0.02, 0.03, 0.06)
                      + vec3(0.02, 0.03, 0.07) * (dot(N, SUN_DIR) * 0.5 + 0.5);
        vec3  sun     = baseCol * SUN_COL * ndotl * 2.8;
        // Warm key-light hotspot/specular are toned down on dinos — otherwise
        // the same golden highlight that lights the canopy tips paints the
        // dino's back too, and the two blend together.
        vec3  hot     = vec3(0.95, 0.55, 0.15) * hotspot * 2.5 * (1.0 - dinoMix * 0.85);
        vec3  spec    = SUN_COL * pow(max(dot(reflect(rd, N), SUN_DIR), 0.0), 10.0) * 0.50 * (1.0 - dinoMix * 0.6);

        // Dinos alone get a cool sky-blue fill light, standing in for bounced
        // twilight sky light. This is what actually keeps them reading blue
        // instead of being washed toward the sun's warm hue on every lit surface.
        float skyFill  = clamp(dot(N, vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5, 0.0, 1.0);
        vec3  dinoFill = vec3(0.25, 0.45, 0.70) * skyFill * 1.6 * dinoMix;

        scol = baseCol * ambient + sun + hot + spec + dinoFill;

        // Shadow — ground gets deeper pools, canopy gets lighter penumbra
        float shad      = shadow(p + N * 0.05, SUN_DIR, 55.0);
        float shadowAmt = localY < 0.15 ? 0.10 : 0.25;
        vec3  shadowCol = baseCol * ambient * shadowAmt + vec3(0.02, 0.02, 0.06);
        scol = mix(shadowCol, scol, shad);

        scol *= 1.0 + syn_BassLevel * bass_reactivity * 0.3;
        scol  = mix(scol, vec3(0.30, 0.26, 0.38), 1.0 - exp(-hitT / (draw_distance * 2.5)));
    }

    // Post-process: gamma, saturation, vignette
    vec3 finalCol = pow(max(scol, vec3(0.0)), vec3(0.72));
    finalCol = mix(vec3(dot(finalCol, vec3(0.299, 0.587, 0.114))), finalCol, 1.45);
    finalCol *= pow(16.0 * _uv.x * _uv.y * (1.0 - _uv.x) * (1.0 - _uv.y), 0.1) * 0.9 + 0.1;

    return vec4(finalCol, 1.0);
}
