// Runs a scene's script.js in a namespaced sandbox. CONTROLS[].NAME values
// must be readable as bare globals inside setup()/update(dt) - and stay
// LIVE across frames, not frozen at load time - so we declare them as
// `var`s in the generated function's scope and refresh them from
// controlsRuntime immediately before each update() call. setup/update
// (function declarations in that same scope) close over those same
// bindings, so they always see the current value.
export function createScriptHost(script, controlNames, controlsRuntime, uniformQueue) {
    const varNames = controlNames.filter(n => /^[A-Za-z_]\w*$/.test(n));

    const preamble = [
        `var ${varNames.join(', ')};`,
        'function __refresh() {',
        ...varNames.map(n => `    ${n} = __controls.get(${JSON.stringify(n)});`),
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

    const factory = new Function('setUniform', 'setControl', '__controls', preamble + script + trailer);

    function setUniform(name, ...args) {
        uniformQueue.set(name, args);
    }
    function setControl(name, value) {
        controlsRuntime.set(name, value);
    }

    const sceneApi = factory(setUniform, setControl, controlsRuntime);
    return sceneApi;
}
