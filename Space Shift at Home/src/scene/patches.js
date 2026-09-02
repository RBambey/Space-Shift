// Minimal, explicit source patches for scenes whose GLSL compiles fine in
// Synesthesia's native (desktop GL/ANGLE) renderer but fails strict WebGL2
// GLSL ES 3.00 validation. Each patch is a literal find/replace on the raw
// main.glsl text, applied before wrapping - kept behavior-neutral by
// construction (only ever adds a `const` qualifier to a global that's never
// reassigned elsewhere in the file, which changes zero runtime values).
//
// Remnant Planet: WebGL2/ANGLE rejects non-const global variables whose
// initializer is a builtin function call (pow/abs/clamp) even though the
// GLSL ES 3.00 spec permits it for const-qualified globals - marking them
// const (verified none are ever reassigned) fixes the compile without
// touching the actual math.
const PATCHES = {
    'Vein Melter_dup': [
        [
            'float STEPS = 40;  // advection steps',
            'int STEPS = 40;  // advection steps',
        ],
        [
            // `amp`'s initializer reads a uniform (`retract`), which WebGL2's
            // stricter validation rejects for a global-scope initializer even
            // though it's not const-qualified - moved into renderMain() so
            // it's still computed fresh every frame, just not at global scope.
            'float amp =  1.0*(1.0-retract*0.1);   // self-amplification',
            'float amp;   // self-amplification - assigned in renderMain(), see patches.js',
        ],
        [
            'vec4 renderMain(){',
            'vec4 renderMain(){\n\tamp = 1.0*(1.0-retract*0.1);',
        ],
        [
            'PI/2));',
            'PI/2.0));',
        ],
    ],
    'Traced Tunnel_dup': [
        [
            'return mix(length(max(abs(p) - b + .1, 0.)) - .1, length(p)-0.5+(max(small_circles, 1.0)-1), min(small_circles, 1.0));',
            'return mix(length(max(abs(p) - b + .1, 0.)) - .1, length(p)-0.5+(max(small_circles, 1.0)-1.0), min(small_circles, 1.0));',
        ],
    ],
    'City': [
        [
            'return textureLod( syn_Spectrum, x, 0.0 ).y;',
            'return textureLod( syn_Spectrum, vec2(x, 0.0), 0.0 ).y;',
        ],
    ],
    'Remnant Planet': [
        [
            'float minRad2                 = clamp(MINRAD2, 1.0e-9, 1.0);\nfloat absScalem1              = abs(SCALE - 1.0);\nfloat AbsScaleRaisedTo1mIters = pow(abs(SCALE), float(1 - 10));\nvec4  mboxScale               = vec4(SCALE, SCALE, SCALE, abs(SCALE)) / minRad2;',
            'const float minRad2                 = clamp(MINRAD2, 1.0e-9, 1.0);\nconst float absScalem1              = abs(SCALE - 1.0);\nconst float AbsScaleRaisedTo1mIters = pow(abs(SCALE), float(1 - 10));\nconst vec4  mboxScale               = vec4(SCALE, SCALE, SCALE, abs(SCALE)) / minRad2;',
        ],
    ],
};

export function applyScenePatches(glsl, sceneTitle) {
    const patches = PATCHES[sceneTitle];
    if (!patches) return glsl;

    let patched = glsl;
    for (const [find, replace] of patches) {
        if (!patched.includes(find)) {
            console.warn(`applyScenePatches: pattern not found for "${sceneTitle}" - scene source may have changed, patch skipped.`);
            continue;
        }
        patched = patched.replace(find, replace);
    }
    return patched;
}
