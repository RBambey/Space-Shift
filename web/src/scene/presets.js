// Synesthesia's exported preset format stores every control's value
// normalized to 0..1 of that control's own MIN..MAX range (confirmed by
// cross-checking several untouched sliders in a real export against their
// scene.json DEFAULTs - e.g. min_height's exported 0.125 * (20-0) == 2.5,
// exactly its DEFAULT). Denormalizing needs the live scene's own MIN/MAX,
// since the preset file doesn't carry them.
export function denormalize(control, normalizedValues) {
    if (Array.isArray(control.MIN)) {
        return control.MIN.map((min, i) => min + normalizedValues[i] * (control.MAX[i] - min));
    }
    return control.MIN + normalizedValues[0] * (control.MAX - control.MIN);
}

// Pulls out the named presets for one scene (matched by scene.json TITLE,
// which is exactly the key Synesthesia's export uses) from a parsed
// exported-presets JSON, e.g. { "Black Hole Rocks": {...preset...} }.
export function presetsForScene(exportedJson, sceneTitle) {
    return (exportedJson && exportedJson[sceneTitle]) || {};
}

// Applies one preset's sceneControlPreset entries into controlsRuntime,
// skipping live flight-input controls (pitch/roll/yaw/fly_speed/bangs) -
// those are transient pilot input the preset just happened to capture at
// export time, not scene-tuning parameters, and keyboard.js already owns
// their state every frame. Returns {name: value} for the ones actually
// applied, so the UI can sync its sliders to match.
export function applyPreset(preset, controls, controlsRuntime, skipNames) {
    const byName = new Map(controls.map(c => [c.NAME, c]));
    const applied = {};

    for (const entry of (preset && preset.sceneControlPreset) || []) {
        if (skipNames.has(entry.ID)) continue;
        const control = byName.get(entry.ID);
        if (!control) continue;

        const value = denormalize(control, entry.VALUES);
        if (Array.isArray(control.MIN)) {
            const keys = control.MIN.length === 3 ? ['x', 'y', 'z'] : ['x', 'y'];
            const obj = {};
            keys.forEach((k, i) => { obj[k] = value[i]; });
            controlsRuntime.set(entry.ID, obj);
            applied[entry.ID] = obj;
        } else {
            controlsRuntime.set(entry.ID, value);
            applied[entry.ID] = value;
        }
    }

    return applied;
}
