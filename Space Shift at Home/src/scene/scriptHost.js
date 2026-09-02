// Fixed engine uniforms Synesthesia exposes as bare globals inside
// script.js, same as CONTROLS values - discovered via Flying 70s Retro's
// script.js, which reads `syn_BassLevel` directly (not just from the
// shader). Not CONTROLS entries, so they need their own refresh path:
// pushAudioUniforms() writes the current values into uniformQueue before
// step() calls refresh(), and these read back out of it here. Names with
// no real implementation (no beat/BPM tracking, see audioAnalysis.js) just
// default to 0, matching the same uniform's default on the GLSL side.
const AUDIO_GLOBAL_NAMES = [
    'syn_BassLevel', 'syn_BassHits', 'syn_BassTime', 'syn_HighLevel',
    'syn_OnBeat', 'syn_BPMSin2', 'syn_BPMSin', 'syn_HighHits',
    'syn_HighTime', 'syn_MidHighTime', 'syn_Presence',
];

// Runs a scene's script.js in a namespaced sandbox. CONTROLS[].NAME values
// (and the audio globals above) must be readable as bare globals inside
// setup()/update(dt) - and stay LIVE across frames, not frozen at load time
// - so we declare them as `var`s in the generated function's scope and
// refresh them immediately before each update() call. setup/update
// (function declarations in that same scope) close over those same
// bindings, so they always see the current value.
export function createScriptHost(script, controlNames, controlsRuntime, uniformQueue) {
    const varNames = controlNames.filter(n => /^[A-Za-z_]\w*$/.test(n));
    const audioNames = AUDIO_GLOBAL_NAMES.filter(n => !varNames.includes(n));

    const preamble = [
        `var ${[...varNames, ...audioNames].join(', ')};`,
        'function __refresh() {',
        ...varNames.map(n => `    ${n} = __controls.get(${JSON.stringify(n)});`),
        ...audioNames.map(n => `    ${n} = __audio.has(${JSON.stringify(n)}) ? __audio.get(${JSON.stringify(n)})[0] : 0;`),
        '}',
        '__refresh();',
        '',
    ].join('\n');

    const trailer = [
        '',
        'return {',
        '    setup: (typeof setup === "function") ? setup : function(){},',
        '    update: (typeof update === "function") ? update : function(){},',
        '    refresh: __refresh,',
        '};',
    ].join('\n');

    const factory = new Function('setUniform', 'setControl', '__controls', '__audio', preamble + script + trailer);

    function setUniform(name, ...args) {
        uniformQueue.set(name, args);
    }
    function setControl(name, value) {
        controlsRuntime.set(name, value);
    }

    const sceneApi = factory(setUniform, setControl, controlsRuntime, uniformQueue);
    return sceneApi;
}
