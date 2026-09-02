const SMOOTH_TYPES = new Set(['slider smooth', 'knob smooth', 'toggle smooth', 'bang smooth', 'xy smooth', 'color smooth']);
const VEC_KEYS = { 'xy smooth': ['x', 'y'], 'xy': ['x', 'y'], 'color smooth': ['x', 'y', 'z'], 'color': ['x', 'y', 'z'] };

// Exact Synesthesia smoothing curve is undocumented; this is a reasonable
// frame-rate-independent exponential approximation using PARAMS as the
// smoothing time-constant. Tune by eye against the native app if needed.
//
// Vector-typed controls (xy/color) are DEFAULT'd as JS arrays in scene.json,
// but script.js reads them as objects with named fields (e.g. bh_position.x/
// .y in BlackHoleRedux) - so vector entries are stored/exposed as {x,y[,z]}
// rather than arrays, with each component smoothed independently.
export function createControlsRuntime(controls) {
    const state = new Map();
    for (const c of controls) {
        const smooth = SMOOTH_TYPES.has(c.TYPE);
        const vecKeys = VEC_KEYS[c.TYPE] || null;
        const initial = vecKeys ? toVec(c.DEFAULT, vecKeys) : c.DEFAULT;
        state.set(c.NAME, {
            type: c.TYPE,
            smooth,
            vecKeys,
            tau: Math.max(c.PARAMS || 0.1, 0.001),
            raw: initial,
            value: vecKeys ? { ...initial } : initial,
        });
    }

    function toVec(arr, keys) {
        const obj = {};
        keys.forEach((k, i) => { obj[k] = arr[i]; });
        return obj;
    }

    return {
        get(name) {
            const entry = state.get(name);
            return entry ? entry.value : 0;
        },
        set(name, value) {
            const entry = state.get(name);
            if (!entry) return;
            if (entry.vecKeys) {
                entry.raw = { ...value };
                if (!entry.smooth) entry.value = { ...value };
            } else {
                entry.raw = value;
                if (!entry.smooth) entry.value = value;
            }
        },
        names() {
            return [...state.keys()];
        },
        typeOf(name) {
            const entry = state.get(name);
            return entry ? entry.type : null;
        },
        update(dt) {
            for (const entry of state.values()) {
                if (!entry.smooth) continue;
                const alpha = 1 - Math.exp(-dt / entry.tau);
                if (entry.vecKeys) {
                    for (const k of entry.vecKeys) {
                        entry.value[k] += (entry.raw[k] - entry.value[k]) * alpha;
                    }
                } else {
                    entry.value += (entry.raw - entry.value) * alpha;
                }
            }
        },
    };
}
