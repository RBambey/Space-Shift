// ============================================================
//  FLYING SYNTH — v1.1
//  Created by RBambey
//  Neon synthwave terrain flyover, audio reactive
// ============================================================


// ---- Terrain ----
float canyonPath(float z) {
    return sin(z * 0.06) * 8.0 + sin(z * 0.11 + 1.2) * 4.0 + sin(z * 0.17 - 0.5) * 2.0;
}

float terrain(vec2 xz) {
    // Mountains (0)
    if (terrain_type < 0.5) {
        float h = 0.0;
        h += sin(xz.x * 0.15 + sin(xz.y * 0.12) * 2.0) * 8.0;
        h += sin(xz.x * 0.31 - xz.y * 0.27) * 5.0;
        h += sin(xz.x * 0.53 + xz.y * 0.41) * 2.5;
        h += sin(xz.x * 1.10 - xz.y * 0.87) * 1.0;
        return h;
    }
    // Flat (1)
    if (terrain_type < 1.5) return 0.0;
    // Canyon (2)
    if (terrain_type < 2.5) {
        float px   = canyonPath(xz.y);
        float dist = abs(xz.x - px);
        return 2.0 + smoothstep(8.0, 24.0, dist) * 26.0;
    }
    // Trench Run (3) — straight trench centered on x=0, Death Star surface outside
    float trenchDist = abs(xz.x);

    // Wall protrusions — blocky sections that narrow the trench every ~8 units along z
    float wCell     = floor(xz.y / 8.0);
    float wHash     = fract(sin(wCell * 311.7) * 43758.5453);
    float wallProtr = floor(wHash * 3.0) * 1.2;  // 0, 1.2, or 2.4 units of protrusion
    float effWidth  = 7.0 - wallProtr;
    float inTrench  = 1.0 - smoothstep(effWidth, effWidth + 1.5, trenchDist);

    // Raised floor blocks — varied heights, kept away from trench center
    vec2  fCell      = floor(xz / 4.0);
    float fHash      = fract(sin(dot(fCell, vec2(127.1, 311.7))) * 43758.5453);
    float fHash2     = fract(sin(dot(fCell, vec2(269.5, 183.3))) * 43758.5453);
    float blockH     = (floor(fHash2 * 5.0) + 1.0) * 0.55;  // 0.55, 1.1, 1.65, 2.2, 2.75
    float centerFade = smoothstep(2.0, 4.5, trenchDist);     // fade to zero near center
    float floorBlock = step(0.65, fHash) * blockH * centerFade * inTrench;

    // Outer surface — stepped panel heights for a plated metal look
    vec2  pCell  = floor(xz / 6.0);
    float pHash  = fract(sin(dot(pCell, vec2(127.1, 311.7))) * 43758.5453);
    float panel  = floor(pHash * 4.0) * 0.6;  // 0, 0.6, 1.2, or 1.8 unit steps

    return mix(14.0 + panel, floorBlock, inTrench);
}

// ---- Neon palette ----
vec3 neonPalette(float t) {
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1.0, 1.0, 1.0);
    vec3 d = vec3(0.0, 0.33, 0.67);
    return a + b * cos(2.0 * PI * (c * t + d));
}

// ---- Contour lines on terrain surface ----
vec3 terrainColor(vec3 hit, float dist) {
    float bass     = syn_BassLevel;

    // Bass ripple — a ring that expands outward from the camera
    float distFromCam = length(hit.xz - vec2(cam_x, cam_z));
    float ripple   = sin(distFromCam * 0.6 - syn_BassTime * 7.0);
    ripple         = pow(clamp(ripple * 0.5 + 0.5, 0.0, 1.0), 3.0);
    ripple        *= bass;  // only fires with bass energy

    // Line width grows with bass; ripple adds extra thickness at its wavefront
    float lineW    = 0.04 + bass * 0.04 + ripple * 0.03;

    // Offset by half interval so y=0 (flat floors) never lands on a contour boundary
    float interval = 2.5;
    float wrapped  = fract((hit.y + interval * 0.5) / interval) * interval;
    float d        = min(wrapped, interval - wrapped);

    float lineMask = smoothstep(lineW, lineW * 0.15, d);
    float glow     = smoothstep(lineW * 6.0, 0.0, d);

    // Hue per elevation band — each contour ring has its own color
    float hueT   = fract(floor(hit.y / interval) * 0.17);
    vec3 lineCol = neonPalette(hueT);
    vec3 glowCol = neonPalette(hueT + 0.3) * 0.4;

    float brightness = 1.5 + ripple * 2.0;  // ripple brightens lines as it passes
    float fog        = exp(-dist * 0.018);

    // Anti-aliased grid at floor level — fwidth kills the moiré at grazing angles
    float gridSize = 3.0;
    float gLineW   = 0.04 + bass * 0.03 + ripple * 0.02;
    vec2  coord    = hit.xz / gridSize;
    vec2  fw       = fwidth(coord);
    vec2  gabs     = abs(fract(coord - 0.5) - 0.5);
    vec2  lines    = smoothstep(fw * 1.5, vec2(0.0), gabs - gLineW);
    float gridMask = max(lines.x, lines.y);
    float gridGlow = max(smoothstep(gLineW * 5.0, 0.0, gabs.x),
                         smoothstep(gLineW * 5.0, 0.0, gabs.y));
    float gridFade = 1.0 - smoothstep(0.5, 5.0, hit.y);
    float gridHueT = fract(dot(floor(coord), vec2(0.07, 0.13)));
    vec3  gridCol     = neonPalette(gridHueT) * gridFade;
    vec3  gridGlowCol = neonPalette(gridHueT + 0.3) * 0.4 * gridFade;

    // Contours fade out where grid fades in — complementary blend, no overlap
    float contourFade = 1.0 - gridFade;

    vec3 col = (lineCol * lineMask + glowCol * glow) * contourFade * brightness * fog;
    col     += (gridCol * gridMask + gridGlowCol * gridGlow) * brightness * fog;

    return col;
}

// ---- Synthwave Moon ----
vec3 drawMoon(vec3 rd) {
    if (rd.y < 0.0) return vec3(0.0);  // below horizon

    vec3  moonDir = normalize(vec3(0.0, 0.06, 1.0));  // center sits just above horizon
    float moonR   = moon_scale;

    float cosA = dot(rd, moonDir);
    if (cosA < cos(moonR)) return vec3(0.0);            // outside disc

    // Disc-space axes
    vec3  right  = normalize(cross(vec3(0.0, 1.0, 0.0), moonDir));
    vec3  discUp = normalize(cross(moonDir, right));
    float sinR   = sin(moonR);
    float dy     = dot(rd, discUp) / sinR;  // -1 = bottom, 1 = top

    // Gradient: yellow → orange/red → magenta/purple top to bottom
    float gradT = dy * 0.5 + 0.5;
    vec3 colTop    = vec3(1.00, 0.75, 0.05);
    vec3 colMid    = vec3(1.00, 0.22, 0.18);
    vec3 colBottom = vec3(0.65, 0.05, 0.55);
    vec3 moonCol   = gradT > 0.5
        ? mix(colMid, colTop,    (gradT - 0.5) * 2.0)
        : mix(colBottom, colMid,  gradT * 2.0);

    // Horizontal stripes in the lower portion of the disc
    if (dy < 0.15) {
        float bandPos = (0.15 - dy) / 1.15 * 5.5;
        float band    = smoothstep(0.3, 0.5, fract(bandPos));
        moonCol      *= 1.0 - band * 0.95;
    }

    // Soft disc edge
    float angle = acos(clamp(cosA, -1.0, 1.0));
    float edge  = smoothstep(0.0, 0.03, 1.0 - angle / moonR);

    return moonCol * edge * 2.0;
}

// ---- Sky ----
vec3 skyColor(vec3 rd) {
    float t = sky_time;

    vec3 duskHorizon  = vec3(1.0,  0.35, 0.55);
    vec3 duskZenith   = vec3(0.10, 0.00, 0.25);
    vec3 dawnHorizon  = vec3(0.45, 0.0,  0.60);
    vec3 dawnZenith   = vec3(0.15, 0.0,  0.30);
    vec3 blackHorizon = vec3(0.0,  0.0,  0.0);
    vec3 blackZenith  = vec3(0.0,  0.0,  0.0);

    vec3 horizon;
    vec3 zenith;
    if (t < 0.5) {
        float s = t * 2.0;
        horizon = mix(duskHorizon, blackHorizon, s);
        zenith  = mix(duskZenith,  blackZenith,  s);
    } else {
        float s = (t - 0.5) * 2.0;
        horizon = mix(blackHorizon, dawnHorizon, s);
        zenith  = mix(blackZenith,  dawnZenith,  s);
    }

    float h = clamp(rd.y * 2.0, 0.0, 1.0);
    vec3 sky = mix(horizon, zenith, h * h);

    float glowBand = exp(-abs(rd.y) * 8.0);
    vec3 duskGlow  = vec3(1.0,  0.2,  0.5);
    vec3 dawnGlow  = vec3(0.55, 0.0,  0.70);
    vec3 blackGlow = vec3(0.0,  0.0,  0.0);
    vec3 glow;
    if (t < 0.5) {
        glow = mix(duskGlow, blackGlow, t * 2.0);
    } else {
        glow = mix(blackGlow, dawnGlow, (t - 0.5) * 2.0);
    }

    sky += glow * glowBand * 0.6;

    // Stars — toggle on/off, world-space so they rotate with camera
    if (show_stars > 0.5) {
        vec3 absRd     = normalize(rd);
        vec2 starUV    = vec2(atan(absRd.x, absRd.z), asin(clamp(absRd.y, -1.0, 1.0)));
        starUV        *= 80.0;
        float starHash = fract(sin(dot(floor(starUV), vec2(127.1, 311.7))) * 43758.5453);
        float starMask = smoothstep(0.97, 1.0, starHash) * clamp(rd.y * 4.0, 0.0, 1.0);
        starMask      *= 0.4 + 0.6 * syn_HighLevel;
        sky += starMask * neonPalette(starHash + TIME * 0.03) * 0.8;
    }

    return sky;
}

vec4 renderMain() {

    vec3 ro = vec3(cam_x, cam_y, cam_z);

    mat3 camRot = mat3(
        cam_rx, cam_ry, cam_rz,
        cam_ux, cam_uy, cam_uz,
        cam_fx, cam_fy, cam_fz
    );

    vec2 uv  = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    vec3 rd  = normalize(camRot * vec3(uv.x, uv.y, 1.0));

    vec3  sky      = skyColor(rd);
    if (show_moon > 0.5) sky += drawMoon(rd);
    vec4  col      = vec4(sky, 1.0);
    float t        = 0.0;
    vec3  hit      = vec3(0.0);
    bool  found    = false;
    float stepSize = 0.0;
    float tLo      = 0.0;
    float tHi      = 0.0;
    float tMid     = 0.0;
    vec3  midHit   = vec3(0.0);
    float h        = 0.0;

    t = 0.1;

    for (int i = 0; i < 120; i++) {
        hit = ro + rd * t;
        h   = hit.y - terrain(hit.xz);

        if (h < 0.0) {
            tLo = t - stepSize;
            tHi = t;
            for (int j = 0; j < 8; j++) {
                tMid   = (tLo + tHi) * 0.5;
                midHit = ro + rd * tMid;
                if (midHit.y < terrain(midHit.xz)) {
                    tHi = tMid;
                } else {
                    tLo = tMid;
                }
            }
            t   = (tLo + tHi) * 0.5;
            hit = ro + rd * t;
            found = true;
            break;
        }

        stepSize = max(0.1, h * 0.5);
        t += stepSize;
        if (t > draw_distance) break;
    }

    if (found) {
        vec3 terrCol    = terrainColor(hit, t);
        vec3 horizonFog = skyColor(normalize(vec3(rd.x, 0.0, rd.z)));
        float fog       = clamp(t / draw_distance, 0.0, 1.0);
        fog             = fog * fog;
        col = mix(vec4(terrCol, 1.0), vec4(horizonFog, 1.0), fog);
    }

    return col;
}