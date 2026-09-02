// A deliberate visual restyle of Warper.synScene's GLSL, scoped only to
// its use as the warp-transition overlay - unlike patches.js (which exists
// purely for behavior-neutral compile fixes), this intentionally changes
// the look: the original scene renders a dense rainbow tunnel of dots; the
// transition wants a sparser, mostly-black tunnel with tight, glowing
// deep-sky-blue points, closer to a Cherenkov-radiation shockwave than a
// disco tunnel. Left as a literal string patch (not a shared PATCHES entry)
// so Warper.synScene itself is untouched for any other use.
const CHERENKOV_BLUE = 'vec3(0.0, 0.7490196, 1.0)';

const FIND_COLOR = 'vec3  col = sin(colA + j * 0.25 + kPhase) * 0.5 + 0.5;';
const REPLACE_COLOR = `vec3  col = ${CHERENKOV_BLUE} * (0.35 + 0.65 * (sin(colA + j * 0.25) * 0.5 + 0.5));`;

// Tighter core (smaller radius, higher cutoff) so points read as sharp
// pinpricks against black instead of overlapping into a solid glow field;
// a wide, dim secondary term adds the soft halo that sells "glowing".
const FIND_V = 'float v   = max(0.3 / (length(o) / 0.08) - 0.01, 0.0);';
const REPLACE_V = `float vCore = max(0.22 / (length(o) / 0.045) - 0.05, 0.0);
            float vGlow = max(0.05 / (length(o) / 0.22) - 0.01, 0.0);
            float v   = vCore + vGlow * 0.4;`;

// warpOverlay.js drives brightness from the transition's intensity envelope
// - not a CONTROLS entry or a script.js setUniform() call, so it has no
// declaration anywhere the wrapper generator would find it. Injected
// directly since this patch is already doing literal text surgery on the
// raw GLSL before it goes through that wrapper.
const FIND_BRIGHTNESS = 'c.xyz *= 1.0 + syn_BassHits * bass_reactivity * 0.5;';
const REPLACE_BRIGHTNESS = 'c.xyz *= (1.0 + syn_BassHits * bass_reactivity * 0.5) * brightness_boost;';
const UNIFORM_DECL = 'uniform float brightness_boost;\n';

export function applyCherenkovStyle(glsl) {
    let patched = UNIFORM_DECL + glsl;
    for (const [find, replace] of [[FIND_COLOR, REPLACE_COLOR], [FIND_V, REPLACE_V], [FIND_BRIGHTNESS, REPLACE_BRIGHTNESS]]) {
        if (!patched.includes(find)) {
            console.warn('applyCherenkovStyle: pattern not found - Warper.synScene source may have changed, patch skipped.');
            continue;
        }
        patched = patched.replace(find, replace);
    }
    return patched;
}
