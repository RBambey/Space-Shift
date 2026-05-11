// ============================================================
//  FLYING 70S RETRO — v1.1
//  Created by RBambey
//  Retro sci-fi alien terrain flyover, audio reactive
// ============================================================


mat3 rotX(float a) {
    float c = cos(a), s = sin(a);
    return mat3(1.0,0.0,0.0, 0.0,c,-s, 0.0,s,c);
}
mat3 rotY(float a) {
    float c = cos(a), s = sin(a);
    return mat3(c,0.0,s, 0.0,1.0,0.0, -s,0.0,c);
}
mat3 rotZ(float a) {
    float c = cos(a), s = sin(a);
    return mat3(c,-s,0.0, s,c,0.0, 0.0,0.0,1.0);
}

// ---- Helpers ----
float triWave(float x) {
    return 1.0 - abs(fract(x) * 2.0 - 1.0);
}

// ---- Terrain ----
float terrain(vec2 xz) {
    // Space (0) — placeholder flat
    if (terrain_type < 0.5) return 0.0;
    // Planet (1) — triangle wave mountains, horizon-locked
    if (terrain_type < 1.5) {
        float t1 = max(0.0, triWave(xz.x * 0.04  + xz.y * 0.009) - 0.25) * 7.0;
        float t2 = max(0.0, triWave(xz.x * 0.08  - xz.y * 0.018) - 0.35) * 4.0;
        float t3 = max(0.0, triWave(xz.x * 0.14  + xz.y * 0.060) - 0.50) * 2.0;

        float distFromCam = length(xz - vec2(cam_x, cam_z));
        float rise = smoothstep(8.0, 55.0, distFromCam);

        float flr = sin(xz.x * 0.8 + xz.y * 0.6) * 0.4
                  + sin(xz.x * 1.3 - xz.y * 0.9) * 0.2;

        return (t1 + t2 + t3) * mountain_height * rise + flr;
    }
    // Hyperspace (2) — placeholder flat
    return 0.0;
}

// ---- Solid terrain surface with shading ----
vec3 terrainColor(vec3 hit, float dist) {
    // Normal via finite differences
    float eps = 0.4;
    float hL = terrain(hit.xz + vec2(-eps, 0.0));
    float hR = terrain(hit.xz + vec2( eps, 0.0));
    float hD = terrain(hit.xz + vec2(0.0, -eps));
    float hU = terrain(hit.xz + vec2(0.0,  eps));
    vec3 normal = normalize(vec3(hL - hR, 2.0 * eps, hD - hU));

    // Directional light — from upper-right-forward (toward ringed planet)
    vec3  lightDir = normalize(vec3(0.35, 0.85, 0.35));
    float diffuse  = max(0.0, dot(normal, lightDir));

    // Elevation color ramp: dark floor → orange slope → bright peak
    float elev    = clamp(hit.y / (9.0 * mountain_height + 0.001), 0.0, 1.0);
    vec3  floorCol = vec3(0.28, 0.08, 0.02);  // dark red-brown volcanic floor
    vec3  slopeCol = vec3(0.72, 0.28, 0.05);  // warm orange slopes
    vec3  peakCol  = vec3(0.98, 0.62, 0.10);  // bright yellow-orange sunlit peaks
    vec3  baseCol  = elev < 0.5
        ? mix(floorCol, slopeCol, elev * 2.0)
        : mix(slopeCol, peakCol,  (elev - 0.5) * 2.0);

    // Solid lit surface
    float ambient = 0.12;
    vec3  col = baseCol * (ambient + diffuse * (1.0 - ambient));

    return col;
}

// ---- Ringed Planet ----
vec3 drawPlanet(vec3 rd) {
    vec3  planetDir = normalize(vec3(0.28, 0.22, 1.0));  // upper right of forward
    float planetR   = planet_scale;

    // Ring pole direction — defines ring plane normal, tilted ~25° from vertical
    vec3 poleDir = normalize(vec3(-0.15, 0.85, 0.10));

    float cosA  = dot(rd, planetDir);
    float angle = acos(clamp(cosA, -1.0, 1.0));
    bool  inPlanet = angle < planetR;

    float innerR = planetR * 1.25;
    float outerR = planetR * 2.1;

    // Ring plane intersection
    bool  hasRingBack  = false;
    bool  hasRingFront = false;
    vec3  ringBack  = vec3(0.0);
    vec3  ringFront = vec3(0.0);

    float ringDenom = dot(rd, poleDir);
    if (abs(ringDenom) > 0.001) {
        float ringT   = dot(planetDir, poleDir) / ringDenom;
        if (ringT > 0.0) {
            vec3  ringHit  = rd * ringT;
            float ringDist = length(ringHit - planetDir);

            if (ringDist > innerR && ringDist < outerR) {
                // Ring is in front of the planet body when the hit is "closer" than the planet center
                // i.e., ringT * cosA < 1.0 (projection along rd is less than planet center distance)
                bool isFront = (ringT * cosA < 1.0);

                float t01      = (ringDist - innerR) / (outerR - innerR);
                float band     = fract(t01 * 5.0);
                float bandMask = smoothstep(0.3, 0.5, band) * smoothstep(0.9, 0.7, band);
                vec3  ringCol  = mix(vec3(0.72, 0.32, 0.07), vec3(0.38, 0.14, 0.02), t01);
                ringCol       *= 0.6 + bandMask * 0.4;
                float ringEdge = smoothstep(innerR, innerR * 1.08, ringDist) *
                                 smoothstep(outerR, outerR * 0.94, ringDist);
                vec3 rc = ringCol * ringEdge;

                if (isFront) { hasRingFront = true; ringFront = rc; }
                else          { hasRingBack  = true; ringBack  = rc * 0.65; }
            }
        }
    }

    // Early exit if nothing to draw
    if (!inPlanet && !hasRingFront && !hasRingBack) return vec3(0.0);
    if (rd.y < -0.05) return vec3(0.0);

    // Disc-space axes for body shading
    vec3  right  = normalize(cross(vec3(0.0, 1.0, 0.0), planetDir));
    vec3  discUp = normalize(cross(planetDir, right));
    float sinR   = sin(planetR);
    float dx     = dot(rd, right)  / sinR;
    float dy     = dot(rd, discUp) / sinR;

    vec3 result = vec3(0.0);

    // 1. Back ring (only where planet body is not covering)
    if (hasRingBack && !inPlanet) result = ringBack;

    // 2. Planet body
    if (inPlanet) {
        float r2      = clamp(dx * dx + dy * dy, 0.0, 1.0);
        float limb    = 1.0 - r2 * 0.45;  // limb darkening
        vec3  bodyCol = mix(vec3(0.50, 0.10, 0.02), vec3(0.88, 0.38, 0.07), limb);
        // Subtle horizontal cloud banding
        float stripe = sin(dy * 14.0) * 0.5 + 0.5;
        bodyCol = mix(bodyCol, bodyCol * vec3(0.72, 0.65, 0.50), stripe * 0.22 * (1.0 - r2));
        float edge = smoothstep(0.0, 0.05, 1.0 - angle / planetR);
        result = bodyCol * edge * 2.8;
    }

    // 3. Front ring (composited over planet body)
    if (hasRingFront) result = mix(result, ringFront, 0.88);

    return result;
}

// ---- Horizon Mountains (sky element — fixed like moon/stars) ----
vec3 drawMountains(vec3 rd, vec3 bgSky) {
    if (terrain_type < 0.5 || terrain_type > 1.5) return bgSky;

    // Azimuth in camera space (yaw not in camera matrix → fixed like moon/stars)
    float az = atan(rd.x, rd.z);

    // Three triWave layers — large sweeping + medium + small sharp peaks
    float m1 = max(0.0, triWave(az * 0.95) - 0.32) * 0.20;
    float m2 = max(0.0, triWave(az * 1.90) - 0.48) * 0.11;
    float m3 = max(0.0, triWave(az * 3.80) - 0.64) * 0.05;
    float bassBoost = 1.0 + syn_BassLevel * 0.6;
    float profile   = (m1 + m2 + m3) * mountain_height * bassBoost;

    // Early out — give glow room to fully fade before clipping
    if (rd.y > profile + 0.06) return bgSky;

    // Solid silhouette — replaces sky behind it
    float body = smoothstep(profile + 0.006, profile - 0.012, rd.y);

    // Subtle lighter edge at the peak skyline (additive glow over the result)
    float hasPeak = smoothstep(0.0, 0.04, profile);   // wider — fades gently into valleys
    float edgeGlow = exp(-abs(rd.y - profile) * 55.0) * 0.5 * hasPeak;

    vec3 silCol = vec3(0.08, 0.09, 0.18);   // dark blue-indigo silhouette
    vec3 rimCol = vec3(0.20, 0.22, 0.38);   // lighter blue-gray rim at peaks

    vec3 result = mix(bgSky, silCol, body);  // body occludes sky
    result += rimCol * edgeGlow;             // rim glow adds on top
    return result;
}

// ---- Sky ----
vec3 skyColor(vec3 rd) {
    float t = sky_time_eff;  // 0 = day, 0.5 = sunset, 1 = night

    // Three sky palettes
    vec3 dayHorizon    = vec3(0.98, 0.88, 0.55);  // warm creamy yellow
    vec3 dayZenith     = vec3(0.30, 0.58, 0.95);  // warm blue
    vec3 sunsetHorizon = vec3(1.00, 0.48, 0.12);  // deep orange-red
    vec3 sunsetZenith  = vec3(0.28, 0.08, 0.32);  // dark purple
    vec3 nightHorizon  = vec3(0.00, 0.10, 0.13);  // dark teal (unchanged)
    vec3 nightZenith   = vec3(0.01, 0.01, 0.03);  // near-black (unchanged)

    vec3 horizonCol, zenithCol;
    if (t < 0.5) {
        float s = t * 2.0;
        horizonCol = mix(dayHorizon,    sunsetHorizon, s);
        zenithCol  = mix(dayZenith,     sunsetZenith,  s);
    } else {
        float s = (t - 0.5) * 2.0;
        horizonCol = mix(sunsetHorizon, nightHorizon, s);
        zenithCol  = mix(sunsetZenith,  nightZenith,  s);
    }

    float h   = clamp(rd.y * 2.5, 0.0, 1.0);
    vec3  sky = mix(horizonCol, zenithCol, h * h);

    // Horizon glow — golden day, blazing sunset, teal night
    float glow      = exp(-abs(rd.y) * 10.0);
    vec3 dayGlow    = vec3(1.00, 0.72, 0.25);
    vec3 sunsetGlow = vec3(1.00, 0.38, 0.05);
    vec3 nightGlow  = vec3(0.00, 0.18, 0.22);
    vec3  glowCol;
    float glowStr;
    if (t < 0.5) {
        float s = t * 2.0;
        glowCol = mix(dayGlow,    sunsetGlow, s);
        glowStr = mix(0.6, 1.0, s);
    } else {
        float s = (t - 0.5) * 2.0;
        glowCol = mix(sunsetGlow, nightGlow,  s);
        glowStr = mix(1.0, 0.35, s);
    }
    sky += glowCol * glow * glowStr;

    // Stars — fade in from mid-sunset to full night
    if (show_stars > 0.5) {
        vec3  absRd    = normalize(rd);
        vec2  starUV   = vec2(atan(absRd.x, absRd.z), asin(clamp(absRd.y, -1.0, 1.0)));
        starUV        *= 120.0;
        vec2  starCell = floor(starUV);
        float starHash = fract(sin(dot(starCell, vec2(127.1, 311.7))) * 43758.5453);
        float starR    = 0.04 + starHash * 0.04;              // vary radius per star
        float starDist = length(fract(starUV) - 0.5);        // distance from cell center
        float starMask = step(0.96, starHash) * smoothstep(starR, 0.0, starDist);
        starMask      *= clamp(rd.y * 3.0, 0.0, 1.0);
        starMask      *= (0.5 + 0.5 * syn_HighLevel) * smoothstep(0.35, 0.7, t);
        vec3  starCol  = mix(vec3(1.0, 0.88, 0.45), vec3(1.0, 1.0, 0.85), fract(starHash * 3.7));
        sky += starMask * starCol * 1.3;
    }

    return sky;
}

// ---- Hyperspace tunnel — 70s warm retro spiral ----
vec3 tunnelPalette(float f) {
    float b = fract(f) * 5.0;
    if (b < 1.0) return vec3(0.96, 0.93, 0.84);  // cream
    if (b < 2.0) return vec3(0.91, 0.78, 0.29);  // yellow-orange
    if (b < 3.0) return vec3(0.91, 0.47, 0.16);  // orange
    if (b < 4.0) return vec3(0.80, 0.23, 0.10);  // red
                 return vec3(0.23, 0.10, 0.03);   // dark brown (natural outline)
}

vec4 renderMain() {

    vec3 ro = vec3(cam_x, cam_y, cam_z);

    float pitch = cam_pitch_angle;
    float roll  = cam_roll_angle;
    float yaw   = cam_yaw_angle;
    mat3 camRot = rotY(-yaw) * rotZ(roll) * rotX(pitch);

    vec2 uv  = (_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);
    float focalLen = 1.0 / tan(radians(fov * 0.5));
    vec3 rd  = normalize(camRot * vec3(uv.x, uv.y, focalLen));

    // ---- Hyperspace tunnel ----
    if (terrain_type > 1.5) {
        // Roll rotates the tunnel
        float cr2 = cos(roll), sr2 = sin(roll);
        vec2 tuv = vec2(cr2 * uv.x - sr2 * uv.y,
                        sr2 * uv.x + cr2 * uv.y);

        // Shift vanishing point with pitch/yaw → curving tunnel
        tuv -= vec2(sin(roll), -sin(pitch)) * 0.35;

        float r     = max(length(tuv), 0.001);
        float a     = atan(tuv.y, tuv.x);  // -PI to PI
        float depth = 1.0 / r;             // large = far into tunnel

        // Stable stripe coordinate — no audio influence, no phase shift
        float s      = depth * 0.4  + (a / 6.283185) * 2.0 + hyper_z * 0.03;
        float sWide  = depth * 0.15 + (a / 6.283185) * 2.0 + hyper_z * 0.03;

        // Shockwave: bass advances a front from near (depth=3) to far (depth=55)
        float waveFront = mix(3.0, 55.0, fract(wave_phase));
        float waveRing  = exp(-pow(depth - waveFront, 2.0) * 0.05);

        // At wavefront blend to wider stripes — no phase change, no backward motion
        vec3 tunnelCol = mix(tunnelPalette(s), tunnelPalette(sWide), waveRing);

        // Warm glow riding the front
        tunnelCol = min(vec3(1.5), tunnelCol + vec3(0.25, 0.10, 0.02) * waveRing);

        // Dark vanishing point at center
        tunnelCol *= smoothstep(0.0, 0.05, r);

        // High level shimmer
        tunnelCol *= 0.85 + 0.15 * syn_HighLevel;

        return vec4(tunnelCol, 1.0);
    }

    // Full sky: base + planet + mountains (mountains composite over planet)
    vec3  sky = skyColor(rd);
    if (show_planet > 0.5) sky += drawPlanet(rd);
    sky = drawMountains(rd, sky);
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
        vec3 terrCol = terrainColor(hit, t);
        // Horizon fog uses base sky only — no mountains or planet, avoids artifacts
        vec3 fogDir     = normalize(vec3(rd.x, 0.0, rd.z));
        vec3 horizonFog = skyColor(fogDir);
        float fog      = clamp(t / draw_distance, 0.0, 1.0);
        fog            = fog * fog;
        col = mix(vec4(terrCol, 1.0), vec4(horizonFog, 1.0), fog);
    }

    return col;
}
