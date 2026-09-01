// Synesthesia's runtime wraps each scene's main.glsl (which only ever
// defines vec4 renderMain(), never a #version pragma or void main()) with a
// header of injected uniforms and a trailing main(). This reconstructs that
// wrapper well enough to run in WebGL2 GLSL ES 3.00, based on a survey of
// the Space Shift scene corpus plus a direct reading of BlackHole.synScene.

const FIXED_UNIFORMS = [
    'uniform float TIME;',
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
    'uniform sampler2D syn_FinalPass;',
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
        'syn_BassLevel', 'syn_BassHits', 'syn_BassTime', 'syn_HighLevel', 'syn_FinalPass']);
    for (const c of controls) knownNames.add(c.NAME);

    const controlDecls = controls.map(controlUniformDecl);
    const passDecls = passes.map(p => `uniform sampler2D ${p.TARGET};`);
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
        ...adHocDecls,
        '',
        'in vec2 v_uv;',
        'out vec4 fragColor;',
        '',
        'vec2 _uv;',
        'vec2 _uvc;',
        'vec2 _xy;',
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
    };
}
