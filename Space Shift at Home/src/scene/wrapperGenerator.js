// Synesthesia's runtime wraps each scene's main.glsl (which only ever
// defines vec4 renderMain(), never a #version pragma or void main()) with a
// header of injected uniforms and a trailing main(). This reconstructs that
// wrapper well enough to run in WebGL2 GLSL ES 3.00, based on a survey of
// the Space Shift scene corpus plus a direct reading of BlackHole.synScene.

const FIXED_UNIFORMS = [
    'uniform float TIME;',
    'uniform float syn_Time;',
    'uniform vec2  RENDERSIZE;',
    'uniform int   PASSINDEX;',
    'uniform float cam_x, cam_y, cam_z;',
    'uniform float cam_rx, cam_ry, cam_rz;',
    'uniform float cam_ux, cam_uy, cam_uz;',
    'uniform float cam_fx, cam_fy, cam_fz;',
    'uniform float syn_BassLevel;',
    'uniform float syn_BassHits;',
    'uniform float syn_BassTime;',
    'uniform float syn_HighLevel;',
    'uniform float syn_OnBeat;',
    'uniform float syn_BPMSin2;',
    'uniform float syn_BPMSin;',
    'uniform float syn_HighHits;',
    'uniform float syn_HighTime;',
    'uniform float syn_MidHighTime;',
    'uniform float syn_Presence;',
    'uniform sampler2D syn_FinalPass;',
    'uniform sampler2D syn_Spectrum;',
    'uniform sampler2D syn_Media;',
];

const CONTROL_TYPE_TO_GLSL = {
    'slider': 'float',
    'slider smooth': 'float',
    'slider speed': 'float',
    'knob': 'float',
    'knob smooth': 'float',
    'toggle': 'float',
    'toggle smooth': 'float',
    'bang': 'float',
    'bang smooth': 'float',
    'dropdown': 'float',
    'xy smooth': 'vec2',
    'color smooth': 'vec3',
};

function controlUniformDecl(control) {
    const glslType = CONTROL_TYPE_TO_GLSL[control.TYPE];
    if (!glslType) {
        console.warn(`wrapperGenerator: unknown CONTROLS TYPE "${control.TYPE}" for "${control.NAME}", defaulting to float`);
    }
    return `uniform ${glslType || 'float'} ${control.NAME};`;
}

const ARG_COUNT_TO_GLSL = { 1: 'float', 2: 'vec2', 3: 'vec3', 4: 'vec4' };

// Splits a call's argument text on top-level commas only (doesn't descend
// into nested parens), e.g. "a, mix(b, c, d), e" -> ["a", "mix(b, c, d)", "e"].
function splitTopLevelArgs(text) {
    const args = [];
    let depth = 0, start = 0;
    for (let i = 0; i < text.length; i++) {
        const ch = text[i];
        if (ch === '(') depth++;
        else if (ch === ')') depth--;
        else if (ch === ',' && depth === 0) {
            args.push(text.slice(start, i));
            start = i + 1;
        }
    }
    args.push(text.slice(start));
    return args.map(a => a.trim()).filter(a => a.length > 0);
}

// script.js can push arbitrary ad-hoc uniforms that never appear in
// scene.json CONTROLS at all - either directly via setUniform("Name", ...)
// (e.g. BlackHole's `OFF`, fed from the `base_hue` control), or indirectly
// through local helper functions like BlackHoleRedux's setHSVColor(name, h,
// s, v)/setNormalizedVec3(name, x, y, z), which take the uniform name as
// their first (literal-string) argument and forward computed values to
// setUniform internally. Best-effort scan, not a real JS parser: catches the
// literal-name, plain-argument-list calls this corpus actually uses.
function scanAdHocUniforms(script, knownNames) {
    const found = new Map();
    const re = /(?:setUniform|setHSVColor|setNormalizedVec3)\(\s*["']([A-Za-z_]\w*)["']\s*,\s*([^;]*)\)\s*;/g;
    let match;
    while ((match = re.exec(script))) {
        const name = match[1];
        if (knownNames.has(name)) continue;
        const argCount = splitTopLevelArgs(match[2]).length;
        found.set(name, ARG_COUNT_TO_GLSL[argCount] || 'float');
    }
    return found;
}

export function generateWrapper({ glsl, sceneJson, script }) {
    const controls = sceneJson.CONTROLS || [];
    const passes = sceneJson.PASSES || [];

    const knownNames = new Set(['cam_x', 'cam_y', 'cam_z', 'cam_rx', 'cam_ry', 'cam_rz',
        'cam_ux', 'cam_uy', 'cam_uz', 'cam_fx', 'cam_fy', 'cam_fz',
        'syn_BassLevel', 'syn_BassHits', 'syn_BassTime', 'syn_HighLevel',
        'syn_OnBeat', 'syn_BPMSin2', 'syn_BPMSin', 'syn_HighHits', 'syn_HighTime', 'syn_MidHighTime', 'syn_Presence',
        'syn_FinalPass', 'syn_Time', 'syn_Spectrum', 'syn_Media']);
    for (const c of controls) knownNames.add(c.NAME);

    const controlDecls = controls.map(controlUniformDecl);
    const passDecls = passes.map(p => `uniform sampler2D ${p.TARGET};`);
    // Only declare a sampler for IMAGES entries the scene's GLSL actually
    // references - scene.json can list images (e.g. Vein Melter's image45)
    // that main.glsl never samples.
    const images = sceneJson.IMAGES || [];
    const imageDecls = images
        .filter(img => new RegExp(`\\b${img.NAME}\\b`).test(glsl))
        .map(img => `uniform sampler2D ${img.NAME};`);
    const adHoc = scanAdHocUniforms(script, knownNames);
    const adHocDecls = [...adHoc.entries()].map(([name, type]) => `uniform ${type} ${name};`);

    const headerLines = [
        '#version 300 es',
        'precision highp float;',
        'precision highp int;',
        'precision highp sampler2D;',
        '',
        'const float PI = 3.14159265358979323846;',
        '',
        ...FIXED_UNIFORMS,
        '',
        ...controlDecls,
        '',
        ...passDecls,
        '',
        ...imageDecls,
        '',
        ...adHocDecls,
        '',
        'in vec2 v_uv;',
        'out vec4 fragColor;',
        '',
        'vec2 _uv;',
        'vec2 _uvc;',
        'vec2 _xy;',
        '',
        // Synesthesia engine stdlib helpers - undocumented, reverse-engineered
        // from call sites (no reference source available).
        // _pulse: a windowed pulse peaking at 1.0 when x is within `width` of
        // `center`, used for scanning-flash effects.
        // _isMediaActive/_loadMedia/_textureMedia: always inactive/gray -
        // this web port has no live video/webcam media source.
        // _rotate: standard 2D rotation. _normalizeRGB: takes 0..255 channel
        // values (call sites pass literals like _normalizeRGB(255,255,255)),
        // not an already-normalized vec3. _rgb2hsv/_hsv2rgb: the standard
        // Sam Hocevar one-liners - these two are exact, not approximations.
        'float _pulse(float x, float center, float width) {',
        '    return 1.0 - smoothstep(0.0, max(width, 0.0001), abs(x - center));',
        '}',
        'bool _isMediaActive() { return false; }',
        'vec4 _loadMedia() { return texture(syn_Media, _uv); }',
        'vec3 _textureMedia(vec2 uv) { return texture(syn_Media, uv).xyz; }',
        'vec2 _rotate(vec2 v, float angle) {',
        '    float s = sin(angle), c = cos(angle);',
        '    return vec2(v.x * c - v.y * s, v.x * s + v.y * c);',
        '}',
        'vec3 _normalizeRGB(float r, float g, float b) { return vec3(r, g, b) / 255.0; }',
        // GLSL ES 3.00 doesn\'t implicitly convert int literal arguments to
        // float parameters - call sites like _normalizeRGB(255, 255, 255)
        // need this overload, not just the float one above.
        'vec3 _normalizeRGB(int r, int g, int b) { return vec3(r, g, b) / 255.0; }',
        'float _fbm(vec3 p) {',
        '    float sum = 0.0, amp = 0.5;',
        '    for (int i = 0; i < 5; i++) {',
        '        sum += amp * (sin(p.x) + sin(p.y * 1.3) + sin(p.z * 1.7)) / 3.0;',
        '        p = p.yzx * 2.03 + 1.7;',
        '        amp *= 0.5;',
        '    }',
        '    return sum * 0.5 + 0.5;',
        '}',
        'vec3 _rgb2hsv(vec3 c) {',
        '    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);',
        '    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));',
        '    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));',
        '    float d = q.x - min(q.w, q.y);',
        '    float e = 1.0e-10;',
        '    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);',
        '}',
        'vec3 _hsv2rgb(vec3 c) {',
        '    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);',
        '    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);',
        '    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);',
        '}',
        '',
    ];

    const trailer = [
        '',
        'void main() {',
        '    _uv  = v_uv;',
        '    _uvc = (v_uv - 0.5) * vec2(RENDERSIZE.x / RENDERSIZE.y, 1.0);',
        '    _xy  = v_uv * RENDERSIZE;',
        '    fragColor = renderMain();',
        '}',
        '',
    ];

    const fragmentSource = headerLines.join('\n') + glsl + trailer.join('\n');

    return {
        fragmentSource,
        headerLineCount: headerLines.length,
        controlNames: controls.map(c => c.NAME),
        passTargets: passes.map(p => p.TARGET),
        adHocUniformNames: [...adHoc.keys()],
        imageNames: images.filter(img => new RegExp(`\\b${img.NAME}\\b`).test(glsl)).map(img => img.NAME),
    };
}
