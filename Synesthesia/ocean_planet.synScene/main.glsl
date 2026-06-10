// ============================================================
//  OCEAN SUNSET — v1.0
//  Created by RBambey
//  Ocean shader based on "Seascape" by Alexander Alekseev (TDM)
//  https://www.shadertoy.com/view/Ms2SD1
//  Flying controls from FlyingSynth by RBambey
// ============================================================

// ---- Ocean globals (set each frame in renderMain before use) ----
float g_seaHeight;
float g_seaChoppy;
float g_seaFreq;
float g_seaTime;
float sky_time;
vec3  g_sunDir2;   // second sun — set each frame before any sky/ocean calls
vec3  g_sunCol2;
mat2  octave_m = mat2(1.6, 1.2, -1.2, 1.6);

const int   NUM_STEPS    = 8;
const int   ITER_GEOMETRY = 3;
const int   ITER_FRAGMENT = 5;
const vec3  SEA_BASE     = vec3(0.02, 0.07, 0.18);
const vec3  SEA_WATER_COLOR = vec3(0.38, 0.22, 0.08);

// ---- Noise ----
float hash(vec2 p) {
    float h = dot(p, vec2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

float noise(in vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return -1.0 + 2.0 * mix(
        mix(hash(i + vec2(0.0,0.0)), hash(i + vec2(1.0,0.0)), u.x),
        mix(hash(i + vec2(0.0,1.0)), hash(i + vec2(1.0,1.0)), u.x),
        u.y);
}

// ---- Ocean wave octave ----
float sea_octave(vec2 uv, float choppy) {
    uv += noise(uv);
    vec2 wv  = 1.0 - abs(sin(uv));
    vec2 swv = abs(cos(uv));
    wv = mix(wv, swv, wv);
    return pow(1.0 - pow(wv.x * wv.y, 0.65), choppy);
}

// ---- Bass ripple — expanding ring from camera position ----
// Returns a 0..1 amplitude boost at world XZ position xz.
// The ring travels outward driven by syn_BassTime so it naturally
// follows bass energy rather than spiking all waves at once.
float bassRippleAt(vec2 xz) {
    float dist = length(xz - vec2(cam_x, cam_z));
    float ring = sin(dist * 0.4 - syn_BassTime * 7.0);
    ring = pow(clamp(ring * 0.5 + 0.5, 0.0, 1.0), 3.0);
    return ring * syn_BassLevel;
}

// ---- Height map (coarse — geometry pass) ----
float map(vec3 p) {
    float freq   = g_seaFreq;
    float amp    = g_seaHeight + bassRippleAt(p.xz) * wave_height * 2.5;
    float choppy = g_seaChoppy;
    vec2  uv = p.xz; uv.x *= 0.75;
    float d, h = 0.0;
    for (int i = 0; i < ITER_GEOMETRY; i++) {
        d  = sea_octave((uv + g_seaTime) * freq, choppy);
        d += sea_octave((uv - g_seaTime) * freq, choppy);
        h += d * amp;
        uv *= octave_m; freq *= 1.9; amp *= 0.22;
        choppy = mix(choppy, 1.0, 0.2);
    }
    return p.y - h;
}

// ---- Height map (detailed — shading pass) ----
float map_detailed(vec3 p) {
    float freq   = g_seaFreq;
    float amp    = g_seaHeight + bassRippleAt(p.xz) * wave_height * 2.5;
    float choppy = g_seaChoppy;
    vec2  uv = p.xz; uv.x *= 0.75;
    float d, h = 0.0;
    for (int i = 0; i < ITER_FRAGMENT; i++) {
        d  = sea_octave((uv + g_seaTime) * freq, choppy);
        d += sea_octave((uv - g_seaTime) * freq, choppy);
        h += d * amp;
        uv *= octave_m; freq *= 1.9; amp *= 0.22;
        choppy = mix(choppy, 1.0, 0.2);
    }
    return p.y - h;
}

// ---- Surface normal (finite differences) ----
vec3 getNormal(vec3 p, float eps) {
    vec3 n;
    n.y = map_detailed(p);
    n.x = map_detailed(vec3(p.x + eps, p.y, p.z)) - n.y;
    n.z = map_detailed(vec3(p.x, p.y, p.z + eps)) - n.y;
    n.y = eps;
    return normalize(n);
}

// ---- Ray-ocean intersection (8-step bisection) ----
float heightMapTracing(vec3 ori, vec3 dir, out vec3 p) {
    float tm   = 0.0;
    float tx   = 1000.0;
    float hx   = map(ori + dir * tx);
    if (hx > 0.0) { p = ori + dir * tx; return tx; }
    float hm   = map(ori + dir * tm);
    float tmid = 0.0;
    for (int i = 0; i < NUM_STEPS; i++) {
        tmid = mix(tm, tx, hm / (hm - hx));
        p    = ori + dir * tmid;
        float hmid = map(p);
        if (hmid < 0.0) { tx = tmid; hx = hmid; }
        else             { tm = tmid; hm = hmid; }
    }
    return tmid;
}

// ---- Lighting helpers ----
float diffuse(vec3 n, vec3 l, float p) {
    return pow(dot(n, l) * 0.4 + 0.6, p);
}
float specular(vec3 n, vec3 l, vec3 e, float s) {
    float nrm = (s + 8.0) / (PI * 8.0);
    return pow(max(dot(reflect(e, n), l), 0.0), s) * nrm;
}

// ---- Sky — blends dawn / midday / dusk / night automatically ----
// Helper: blend three values at t=0, t=0.5, t=1
vec3 blend3(vec3 a, vec3 b, vec3 c, float t) {
    return mix(mix(a, b, clamp(t * 2.0, 0.0, 1.0)),
                    c, clamp(t * 2.0 - 1.0, 0.0, 1.0));
}

// ---- Creature silhouette SDFs ----
float sdSeg2(vec2 p, vec2 a, vec2 b, float r) {
    vec2 pa = p-a, ba = b-a;
    return length(pa - ba*clamp(dot(pa,ba)/dot(ba,ba),0.0,1.0)) - r;
}

float sdTri(vec2 p, vec2 a, vec2 b, vec2 c) {
    vec2 e0=b-a,e1=c-b,e2=a-c,v0=p-a,v1=p-b,v2=p-c;
    vec2 pq0=v0-e0*clamp(dot(v0,e0)/dot(e0,e0),0.0,1.0);
    vec2 pq1=v1-e1*clamp(dot(v1,e1)/dot(e1,e1),0.0,1.0);
    vec2 pq2=v2-e2*clamp(dot(v2,e2)/dot(e2,e2),0.0,1.0);
    float s=sign(e0.x*e2.y-e0.y*e2.x);
    vec2 d=min(min(vec2(dot(pq0,pq0),s*(v0.x*e0.y-v0.y*e0.x)),
                   vec2(dot(pq1,pq1),s*(v1.x*e1.y-v1.y*e1.x))),
                   vec2(dot(pq2,pq2),s*(v2.x*e2.y-v2.y*e2.x)));
    return -sqrt(d.x)*sign(d.y);
}

// Pterodactyl silhouette — bottom-up view, body along +x, wings spread ±y
float creatureSDF(vec2 p, float flap) {
    float fa   = sin(flap);
    float span = 0.88 - 0.15*abs(fa);  // wingspan compresses at flap extremes
    float wy   = fa * 0.10;            // wing root shifts with flap

    float lw = sdTri(p, vec2(0.10+wy, 0.0), vec2(-0.10+wy, span), vec2(-0.22, 0.0));
    float rw = sdTri(p, vec2(0.10+wy, 0.0), vec2(-0.10+wy,-span), vec2(-0.22, 0.0));
    float bd = sdSeg2(p, vec2(-0.22, 0.0), vec2(0.28, 0.0), 0.068);
    float cr = sdSeg2(p, vec2(0.28, 0.0), vec2(0.80, 0.15), 0.024);  // forward head crest

    // Swooshing tail — 5 tapered segments; sine wave propagates root→tip
    float tw = flap * 0.55;  // tail wags at 55% of flap speed
    vec2 t0 = vec2(-0.22, 0.0);
    vec2 t1 = vec2(-0.65, sin(tw + 1.1) * 0.13);
    vec2 t2 = vec2(-1.08, sin(tw + 2.2) * 0.26);
    vec2 t3 = vec2(-1.51, sin(tw + 3.3) * 0.39);
    vec2 t4 = vec2(-1.94, sin(tw + 4.4) * 0.52);
    vec2 t5 = vec2(-2.37, sin(tw + 5.5) * 0.62);
    float ta = min(min(min(sdSeg2(p, t0, t1, 0.048),
                           sdSeg2(p, t1, t2, 0.034)),
                       min(sdSeg2(p, t2, t3, 0.022),
                           sdSeg2(p, t3, t4, 0.013))),
                   sdSeg2(p, t4, t5, 0.008));

    return min(min(min(lw, rw), min(bd, cr)), ta);
}

vec3 skyColor(vec3 rd, vec3 sunDir, vec3 sunCol) {
    float y = clamp(rd.y, 0.0, 1.0);

    // Smooth day/night transition: either sun can hold back the darkness
    float dayFactor = smoothstep(-0.30, 0.20, max(sunDir.y, g_sunDir2.y));

    // Per-time zenith / mid / horizon colours (day arc)
    vec3 zenith  = blend3(vec3(0.30, 0.28, 0.55),   // dawn  — soft lavender
                          vec3(0.10, 0.32, 0.78),   // midday — rich blue
                          vec3(0.05, 0.02, 0.18),   // dusk  — deep indigo
                          sky_time);
    vec3 mid     = blend3(vec3(0.90, 0.42, 0.38),   // dawn  — coral pink
                          vec3(0.18, 0.42, 0.82),   // midday — deep sky blue
                          vec3(0.55, 0.12, 0.08),   // dusk  — rich red
                          sky_time);
    vec3 horizon = blend3(vec3(1.00, 0.72, 0.55),   // dawn  — peach gold
                          vec3(0.38, 0.60, 0.78),   // midday — clear blue (not washed)
                          vec3(1.00, 0.55, 0.10),   // dusk  — amber
                          sky_time);
    vec3 haze    = blend3(vec3(1.00, 0.60, 0.45),   // dawn
                          vec3(0.45, 0.65, 0.88),   // midday — sky-blue haze
                          vec3(1.00, 0.45, 0.10),   // dusk
                          sky_time);

    // Blend toward moonlit night sky — large overhead moon prevents total darkness
    zenith  = mix(vec3(0.04, 0.06, 0.14), zenith,  dayFactor);
    mid     = mix(vec3(0.03, 0.05, 0.11), mid,     dayFactor);
    horizon = mix(vec3(0.04, 0.06, 0.14), horizon, dayFactor);
    haze    = mix(vec3(0.01, 0.02, 0.04), haze,    dayFactor);

    float hBlend = pow(1.0 - y, 2.5);
    vec3 sky = mix(mix(zenith, mid, pow(1.0 - y, 1.2)), horizon, hBlend);

    // Horizon haze
    sky += haze * exp(-abs(rd.y) * 5.0) * 0.22;

    // Sun disc + glow — clamp sunH so exponent stays positive when below horizon
    float sunH     = clamp(sunDir.y, 0.0, 1.0);
    float discEdge = mix(0.9988, 0.9995, sunH);
    float sunDot   = dot(rd, sunDir);
    float sunDisc  = smoothstep(discEdge, discEdge + 0.0006, sunDot);
    float sunGlow  = pow(max(sunDot, 0.0), mix(32.0, 128.0, sunH)) * 0.55;
    sky += sunCol * sunDisc * mix(2.5, 4.0, sunH);
    sky += sunCol * sunGlow;

    // Second sun: smaller disc (tighter edge), more focused glow, same red colour
    float sun2H    = clamp(g_sunDir2.y, 0.0, 1.0);
    float sunDot2  = dot(rd, g_sunDir2);
    float sunDisc2 = smoothstep(0.9997, 1.0, sunDot2);
    float sunGlow2 = pow(max(sunDot2, 0.0), mix(64.0, 256.0, sun2H)) * 0.6;
    sky += g_sunCol2 * sunDisc2 * mix(1.5, 2.5, sun2H);
    sky += g_sunCol2 * sunGlow2;

    // 8 dim moons — each with its own orbit speed, tilt, and disc size
    float moonVis  = 1.0 - dayFactor * 0.95;  // fade out during daylight
    vec3  moonBase = vec3(0.65, 0.70, 0.88);   // cool silver-blue
    for (int m = 0; m < 8; m++) {
        float fm     = float(m);
        float mPhase = fm * 0.7854;                         // evenly spaced starting phases
        float mSpeed = 0.2 + mod(fm * 1.6180, 0.5);        // 0.2x–0.7x sun speed
        float mTiltX = (mod(fm * 0.6180, 1.0) - 0.5) * 0.8; // x-tilt varies orbit plane
        float mZSign = mod(fm, 2.0) < 1.0 ? 1.0 : -1.0;   // alternate fore/aft arc direction
        float mDisc  = 0.9997 + mod(fm * 0.1618, 1.0) * 0.00027; // disc edge — size variety
        float mBrite = 0.08   + mod(fm * 0.3820, 1.0) * 0.18;    // 0.08–0.26 brightness

        float mCycle = mod(TIME * sun_speed * PI * 2.0 * mSpeed + mPhase, PI * 2.0);
        vec3  mDir   = normalize(vec3(mTiltX, sin(mCycle), mZSign * cos(mCycle)));

        float mH     = clamp(mDir.y, 0.0, 1.0);
        float mDot   = dot(rd, mDir);
        float mDisc2 = smoothstep(mDisc, mDisc + 0.00008, mDot);
        float mGlow  = pow(max(mDot, 0.0), mix(128.0, 512.0, mH)) * 0.4;
        sky += moonBase * (mDisc2 + mGlow * 0.6) * moonVis * mBrite;
    }

    // Large stationary overhead moon — fixed position, always illuminating
    vec3  bigMoonDir  = normalize(vec3(0.0, 1.0, 0.2));
    vec3  bigMoonCol  = vec3(0.82, 0.88, 1.0);
    float bigMoonDot  = dot(rd, bigMoonDir);
    float bigMoonDisc = smoothstep(0.9990, 0.9993, bigMoonDot);
    float bigMoonGlow = pow(max(bigMoonDot, 0.0), 24.0) * 0.5;   // tight corona
    float bigMoonAmb  = pow(max(bigMoonDot, 0.0),  4.0) * 0.06;  // wide ambient halo
    float bigMoonVis  = mix(0.12, 1.0, 1.0 - dayFactor);         // faint in daytime, full at night
    sky += bigMoonCol * (bigMoonDisc * 0.85 + bigMoonGlow + bigMoonAmb) * bigMoonVis;

    // Meteor shower — tiled 16×12 grid (192 meteors), 3×3 neighbour check = 9 iters/pixel
    float bothDown = (1.0 - smoothstep(-0.20, 0.06, sunDir.y)) *
                     (1.0 - smoothstep(-0.20, 0.06, g_sunDir2.y));
    if (bothDown > 0.001) {
        vec3  meteorDir = normalize(vec3(0.5, -1.0, 0.15));
        float tailLen   = 0.12;

        float azFrac = (atan(rd.x, rd.z) / PI + 1.0) * 0.5;
        float elFrac = clamp(rd.y, 0.0, 1.0);
        const float GAZ = 16.0;
        const float GEL = 12.0;
        vec2 gBase = floor(vec2(azFrac * GAZ, elFrac * GEL));

        float meteorResult = 0.0;
        for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            vec2 cId = gBase + vec2(float(dx), float(dy));
            cId.x = mod(cId.x, GAZ);
            cId.y = clamp(cId.y, 0.0, GEL - 1.0);

            float h1 = fract(sin(dot(cId, vec2(127.1, 311.7))) * 43758.5);
            float h2 = fract(sin(dot(cId, vec2(269.5, 183.3))) * 12345.7);
            float h3 = fract(sin(dot(cId, vec2(419.2, 371.9))) * 98765.4);
            float h4 = fract(sin(dot(cId, vec2(531.4, 487.2))) * 23456.8);

            // Base direction from cell position + per-cell hash offset
            float az_m  = ((cId.x + h1) / GAZ * 2.0 - 1.0) * PI;
            float el_m  = (cId.y + h2) / GEL;
            float cosEl = sqrt(max(0.0, 1.0 - el_m * el_m));
            vec3  base  = vec3(sin(az_m) * cosEl, el_m, cos(az_m) * cosEl);

            float period = 4.0 + h4 * 10.0;
            float cycle  = fract(TIME / period + h3);
            float t      = clamp(cycle / 0.25, 0.0, 1.0);
            float vis    = step(cycle, 0.25);
            float fade   = smoothstep(0.0, 0.2, t) * smoothstep(1.0, 0.7, t);

            float travel = t * 0.35;
            vec3  head   = base + meteorDir * travel;
            vec3  tail   = base + meteorDir * max(0.0, travel - tailLen);
            vec3  seg    = head - tail;
            float proj   = clamp(dot(rd - tail, seg) / dot(seg, seg), 0.0, 1.0);
            float dist   = length(rd - (tail + seg * proj));
            meteorResult += exp(-dist * dist * 80000.0) * proj * fade * vis;
        }}

        sky += vec3(0.88, 0.94, 1.0) * meteorResult * bothDown * 0.9;
    }

    // Flying creature silhouettes — visible only when a sun is up
    if (dayFactor > 0.01) {
        float az = atan(rd.x, rd.z);
        float el = rd.y;
        float silResult = 0.0;

        for (int i = 0; i < 8; i++) {
            float fi = float(i);
            float h1 = fract(sin(fi * 172.3) * 43758.5);  // elevation
            float h2 = fract(sin(fi * 259.7) * 12345.6);  // start phase
            float h3 = fract(sin(fi * 347.1) * 98765.4);  // flap phase
            float h4 = fract(sin(fi * 431.9) * 23456.7);  // speed
            float h5 = fract(sin(fi * 523.3) * 76543.2);  // size
            float h6 = fract(sin(fi * 617.9) * 54321.1);  // flight angle

            float speed    = 0.10 + h4 * 0.14;
            float elev     = 0.10  + h1 * 0.42;
            float flyAngle = (h6 * 2.0 - 1.0) * 0.3;
            float flyAz    = mod((h2 * 2.0 - 1.0) * PI + TIME * speed + PI, 2.0*PI) - PI;
            float flyEl    = elev + sin(TIME * 0.12 + h3 * 6.28) * 0.03;

            // Angular offset of this ray from the creature, in creature-local frame
            float dAz = mod((az - flyAz) + PI, 2.0*PI) - PI;
            float dEl = el - flyEl;
            float cf = cos(flyAngle), sf = sin(flyAngle);
            vec2 luv = vec2(cf*dAz + sf*dEl, -sf*dAz + cf*dEl)
                       / (0.040 + h5 * 0.022);

            if (dot(luv, luv) > 9.0) continue;  // cull if > 3 creature-widths away (tail extends to ~2.5)

            float sdf = creatureSDF(luv, TIME * (1.8 + h3 * 2.2) + h2 * PI * 2.0);
            silResult = max(silResult, smoothstep(0.12, -0.02, sdf));
        }

        // Dark silhouette — retain faint sky colour so it reads as atmosphere, not a hole
        sky = mix(sky, sky * 0.04 + vec3(0.01, 0.01, 0.015), silResult * dayFactor);
    }

    return sky;
}

// ---- Ocean shading ----
vec3 getSeaColor(vec3 p, vec3 n, vec3 l, vec3 eye, vec3 dist, vec3 sunDir, vec3 sunCol) {
    float fresnel   = 1.0 - max(dot(n, -eye), 0.0);
    fresnel         = pow(fresnel, 3.0) * 0.65;

    vec3 reflected  = skyColor(reflect(eye, n), sunDir, sunCol);
    vec3 refracted  = SEA_BASE + diffuse(n, l, 80.0) * SEA_WATER_COLOR * 0.12;
    vec3 color      = mix(refracted, reflected, fresnel);

    float atten = max(1.0 - dot(dist, dist) * 0.001, 0.0);
    color += SEA_WATER_COLOR * (p.y - g_seaHeight) * 0.18 * atten;

    // Specular glitter tinted to match sun colour
    color += sunCol * specular(n, l, eye, 60.0);
    color += g_sunCol2 * specular(n, g_sunDir2, eye, 60.0) * 0.4;

    return color;
}

// ================================================================
vec4 renderMain() {

    // --- Set ocean parameters for this frame ---
    g_seaHeight     = wave_height;
    g_seaChoppy     = sea_choppiness;
    g_seaFreq       = 0.16;
    g_seaTime       = TIME * sea_speed * 0.8;

    // --- Camera ---
    vec3 ro     = vec3(cam_x, cam_y, cam_z);
    vec3 cRight = vec3(cam_rx, cam_ry, cam_rz);
    vec3 cUp    = vec3(cam_ux, cam_uy, cam_uz);
    vec3 cFwd   = vec3(cam_fx, cam_fy, cam_fz);
    vec2 uv  = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd  = normalize(cFwd + cRight * uv.x + cUp * uv.y);

    // Automatic day/night: sun traces a full arc overhead
    // sunCycle 0 = sunrise (east horizon), PI/2 = zenith, PI = sunset, 3PI/2 = nadir
    float sunAngle = TIME * sun_speed * PI * 2.0 + 0.1;
    float sunCycle = mod(sunAngle, PI * 2.0);
    vec3  sunDir   = normalize(vec3(0.3, sin(sunCycle), cos(sunCycle)));

    // sky_time: 0=dawn, 0.5=midday, 1=dusk — maps the above-horizon arc
    sky_time = clamp(sunCycle / PI, 0.0, 1.0);

    vec3 sunCol = blend3(vec3(1.0, 0.80, 0.65),   // dawn  — soft pink-white
                         vec3(1.0, 0.98, 0.88),   // midday — near white
                         vec3(1.0, 0.75, 0.30),   // dusk  — warm gold
                         sky_time);

    // Second sun: smaller, redder, opposite arc direction, twice the orbital speed.
    // Phase: when sunAngle = PI (main sun at sunset), sunCycle2 = 0 (second sun rising from west).
    // Visible: mornings (both suns up) + first half of night (second sun only).
    float sunCycle2 = mod(sunAngle * 2.0 + PI - 0.1, PI * 2.0);
    g_sunDir2 = normalize(vec3(-0.3, sin(sunCycle2), -cos(sunCycle2)));
    g_sunCol2 = vec3(1.0, 0.20, 0.05);

    // --- Sky layer ---
    vec3 skyCol = skyColor(rd, sunDir, sunCol);

    // --- Ocean trace (only for rays that point downward) ---
    if (rd.y >= -0.001) {
        return vec4(skyCol, 1.0);
    }

    vec3  p;
    float t    = heightMapTracing(ro, rd, p);
    vec3  dist = p - ro;

    float epsNrm = dot(dist, dist) * (0.1 / RENDERSIZE.x);
    vec3  n      = getNormal(p, epsNrm);

    vec3 seaCol = getSeaColor(p, n, sunDir, rd, dist, sunDir, sunCol);

    // Fog: blend toward the horizon sky colour at distance
    vec3  horizonDir = normalize(vec3(rd.x, 0.0, rd.z));
    vec3  fogCol     = skyColor(horizonDir, sunDir, sunCol);
    float fog        = exp(-t * (3.0 / draw_distance));
    vec3  col        = mix(fogCol, seaCol, fog);

    // Gamma correction (match Seascape's 0.75 gamma)
    col = pow(max(col, vec3(0.0)), vec3(0.75));

    return vec4(col, 1.0);
}
