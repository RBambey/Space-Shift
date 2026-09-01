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
