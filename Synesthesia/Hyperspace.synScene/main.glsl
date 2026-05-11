// ============================================================
//  HYPERSPACE — SSF Scene
//  A raymarched hyperspace tunnel with full user controls
// ============================================================

// ---- Uniforms from scene.json controls ----
// travel_speed    : slider speed  — how fast we fly forward
// cam_pitch_roll  : xy smooth     — X=pitch (up/down), Y=roll (rotation)
// cam_yaw         : knob smooth   — pan camera left/right
// base_color      : color smooth  — primary hue
// texture_style   : dropdown      — 0=stars, 1=streaks, 2=grid tunnel
// brightness      : slider smooth — overall brightness multiplier
// color_shift     : slider smooth — hue rotation over time
// speed_rate      : set by script — actual rate of movement 0-1

#define TAU 6.28318530718

float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

float hash3(vec3 p) {
    p = fract(p * vec3(443.8975, 397.2973, 491.1871));
    p += dot(p, p.zyx + 19.19);
    return fract((p.x + p.y) * p.z);
}

float noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash3(i + vec3(0,0,0)), hash3(i + vec3(1,0,0)), f.x),
            mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
        mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
            mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y),
        f.z
    );
}

vec2 rot2(vec2 v, float a) {
    float c = cos(a), s = sin(a);
    return vec2(v.x*c - v.y*s, v.x*s + v.y*c);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// -------- star field (mode 0) --------
vec3 starField(vec3 rd, float t, vec3 col) {
    vec3 color = vec3(0.0);
    for (int i = 0; i < 80; i++) {
        float fi = float(i);
        float zOff   = hash(fi * 13.7) * 30.0;
        float angle  = hash(fi * 7.3) * TAU;
        float radius = 0.3 + hash(fi * 3.1) * 2.5;

        float z = mod(zOff - t * 4.0, 30.0) - 2.0;
        vec2 sp = vec2(cos(angle), sin(angle)) * radius;

        if (z < 0.1) continue;
        vec2 proj = sp / z;

        float dist = length(rd.xy / max(rd.z, 0.001) - proj);
        float streakLen = clamp(4.0 / z, 0.005, 0.3);
        float glow = 0.0008 / (dist * dist + 0.0001);

        float sz = rd.z / max(z * 0.2, 0.001);
        float streak = 0.0002 / (abs(rd.x / max(rd.z,0.001) - sp.x / z) + 0.001);
        streak *= smoothstep(streakLen, 0.0, abs(rd.y / max(rd.z,0.001) - sp.y / z));

        float brightness = (glow + streak * 0.3) * (1.0 / (z * 0.1 + 0.3));
        color += brightness * col;
    }
    return color;
}

// -------- streak warp (mode 1) - radial streaks from center --------
vec3 warpStreaks(vec3 rd, float t, vec3 col) {
    vec3 color = vec3(0.0);

    vec2 rayXY = rd.xy / max(rd.z, 0.001);

    for (int i = 0; i < 80; i++) {
        float fi = float(i);
        float seed = fi * 17.31;

        float angle  = hash(seed) * TAU;
        float radius = 0.05 + hash(seed + 1.0) * 2.2;

        float z = mod(hash(seed + 2.0) * 20.0 - t * 5.0, 20.0) + 0.3;

        vec2 starDir = vec2(cos(angle), sin(angle));
        vec2 starPos = starDir * radius / z;

        vec2 radNorm = normalize(starPos + 0.0001);

        vec2 toRay     = rayXY - starPos;
        float perpDist = abs(toRay.x * radNorm.y - toRay.y * radNorm.x);

        float along      = dot(toRay, -radNorm);
        float audioPulse = speed_rate * (1.0 + syn_BassHits * 2.0 * speed_rate + syn_BassLevel * 0.5 * speed_rate);
        float streakLen  = radius / z * (audioPulse * 0.8) + 0.001;
        float streakT    = clamp(1.0 - (along / max(streakLen, 0.001)), 0.0, 1.0);

        float width      = 0.0002 + streakT * 0.0012;
        float streakBody = width / (perpDist + width * 0.5);
        streakBody      *= smoothstep(width * 8.0, 0.0, perpDist); // hard clamp on lateral spread

        float tipFade    = smoothstep(streakLen, 0.0, along);
        float backFade   = smoothstep(-0.01, 0.02, along);
        float radialFade = streakT * streakT;

        // Circular glow — plain Euclidean distance, no halo to avoid ring artifacts
        float distToStar = length(rayXY - starPos);
        float dotGlow    = 0.0005 / (distToStar * distToStar + 0.0008);

        float depthFade = 1.0 / (z * 0.15 + 0.2);

        color += (streakBody * 0.6 + dotGlow) * tipFade * backFade * radialFade * depthFade * col;
    }
    return color;
}

// -------- grid tunnel (mode 2) - retro wireframe --------
vec3 gridTunnel(vec3 rd, float t, vec3 col) {
    vec3 color = vec3(0.0);

    vec2 rayXY = rd.xy / max(rd.z, 0.001);

    // Number of tunnel rings to draw
    for (int i = 0; i < 12; i++) {
        float fi = float(i);

        // Evenly spaced rings marching away, scrolling toward camera
        float z = mod(fi * 1.5 - mod(t * 2.0, 18.0), 18.0) + 0.5;

        // Project ring onto screen
        float tunnelR = 1.2;
        vec2 p = rayXY * z;

        // Distance from the tunnel cylinder wall
        float ringDist = abs(length(p) - tunnelR);

        // Sharp bright ring line
        float ring = 0.003 / (ringDist + 0.003);

        // Vertical/horizontal spokes radiating from center
        float spokeAngle = atan(p.y, p.x);
        float numSpokes = 8.0;
        float spoke = 0.002 / (abs(mod(spokeAngle, TAU / numSpokes) - (TAU / numSpokes) * 0.5) + 0.004);
        // Only show spokes inside the tunnel wall
        spoke *= smoothstep(tunnelR + 0.3, tunnelR - 0.1, length(p));

        // Depth fade — closer rings brighter
        float depthFade = 1.0 / (z * 0.3 + 0.2);

        color += (ring + spoke * 0.5) * depthFade * col;
    }

    return color;
}

// ============================================================
vec4 renderMain() {

    float t = mod(travel_speed, 1000.0) + syn_BassTime * 0.6;

    vec2 uv = _uvc;

    // cam_pitch_roll.x = roll (rotation), cam_pitch_roll.y = pitch (up/down)
    vec3 rd = normalize(vec3(uv.x + cam_yaw * 0.5, uv.y + cam_pitch_roll.y * 0.5, 1.5));

    // Apply roll — manual control plus subtle audio-reactive roll
    float rollAmt = cam_pitch_roll.x + sin(TIME * 0.3) * 0.1 + syn_BPMSin2 * 0.05;
    rd.xy = rot2(rd.xy, rollAmt);

    vec3 col = base_color;
    float hShift = color_shift * TIME * 0.05;
    float len = length(col);
    vec3 rotCol = vec3(
        dot(col, vec3(cos(hShift), -sin(hShift)*0.5, sin(hShift)*0.5)),
        dot(col, vec3(sin(hShift)*0.5, cos(hShift), -sin(hShift)*0.5)),
        dot(col, vec3(-sin(hShift)*0.5, sin(hShift)*0.5, cos(hShift)))
    );
    rotCol = normalize(rotCol + 0.001) * len;
    col = mix(col, rotCol, 0.6);

    col += syn_OnBeat * base_color * 0.4;

    vec3 finalColor = vec3(0.0);

    if (texture_style < 0.5) {
        finalColor = starField(rd, t, col);
    } else if (texture_style < 1.5) {
        finalColor = warpStreaks(rd, t, col);
    } else {
        finalColor = gridTunnel(rd, t, col);
    }

    float bgDist = length(_uvc);
    vec3 bg = col * 0.03 * (1.0 - bgDist * 0.5);
    finalColor += bg;

// Derive vanishing point by finding what _uvc value produces rd pointing at (0,0,1)
    // rd = normalize(vec3(uv.x + cam_yaw*0.5, uv.y + cam_pitch_roll.y*0.5, 1.5))
    // then rotated by rollAmt — so reverse: unrotate then subtract offsets
    vec2 vanishingPoint = rot2(vec2(0.0, 0.0), -rollAmt) - vec2(cam_yaw * 0.5, cam_pitch_roll.y * 0.5);
    float vanishDist = length(_uvc - vanishingPoint);
    float centerMask = smoothstep(0.0, 0.5, vanishDist);
    finalColor *= centerMask;

    finalColor *= brightness;
    finalColor = finalColor / (finalColor + 0.8);
    finalColor = pow(finalColor, vec3(0.85));

    float vign = 1.0 - smoothstep(0.6, 1.4, bgDist);
    finalColor *= vign;

    return vec4(finalColor, 1.0);
}
