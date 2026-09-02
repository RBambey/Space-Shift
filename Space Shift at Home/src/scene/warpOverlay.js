import { compileProgram } from '../gl/program.js';
import { loadScene as fetchSceneFiles } from './sceneLoader.js';
import { generateWrapper } from './wrapperGenerator.js';
import { applyCherenkovStyle } from './warpStyle.js';
import { createPassRunner } from './passRunner.js';

// The warp effect used to cover scene transitions is this project's own
// "Warper" scene (RBambey) - a polar-warp tunnel of glinting points -
// recolored/retuned via warpStyle.js into a sparse, mostly-black tunnel of
// glowing deep-sky-blue points (Cherenkov-radiation look) rather than its
// native dense rainbow. Driven with hardcoded uniforms instead of
// script.js's own flight-control logic (script.js is only read here for
// wrapperGenerator's ad-hoc-uniform scan, never executed) - there's no
// interactivity to preserve for a transition effect. Loaded and compiled
// once, lazily, then reused for every subsequent transition.
const WARP_SCENE_DIR = '../Synesthesia/Warper.synScene';
const IDLE_RESET_GAP_SECONDS = 0.25;

export function createWarpOverlay(gl, quad) {
    let state = null;
    let loadingPromise = null;

    async function load() {
        if (state) return state;
        if (!loadingPromise) {
            loadingPromise = (async () => {
                const { glsl: rawGlsl, sceneJson, script } = await fetchSceneFiles(WARP_SCENE_DIR);
                const glsl = applyCherenkovStyle(rawGlsl);
                const wrapper = generateWrapper({ glsl, sceneJson, script });
                const program = compileProgram(gl, quad.vertexSource, wrapper.fragmentSource, wrapper.headerLineCount);
                const passRunner = createPassRunner(gl, program, quad, sceneJson.PASSES || []);
                const locCache = new Map();
                const getLoc = (name) => {
                    if (!locCache.has(name)) locCache.set(name, gl.getUniformLocation(program, name));
                    return locCache.get(name);
                };
                state = { passRunner, getLoc, warpTime: 0, lastCallTime: null };
            })();
        }
        await loadingPromise;
        return state;
    }

    // intensity: 0..1, how "deep" into the warp the transition currently is
    // - ramps travel speed and brightness up going in and back down coming
    // out. A gap since the last render() call (i.e. the previous transition
    // finished) resets the accumulated travel time, matching warp_time's
    // own role in the original scene's script.js.
    function render(width, height, intensity) {
        if (!state) return null;
        state.passRunner.resize(width, height);

        const now = performance.now();
        const idle = state.lastCallTime === null || (now - state.lastCallTime) / 1000 > IDLE_RESET_GAP_SECONDS;
        const dt = idle ? 0 : (now - state.lastCallTime) / 1000;
        if (idle) state.warpTime = 0;
        const flySpeed = 0.5 + intensity * 3.5;
        state.warpTime = (state.warpTime + flySpeed * dt) % 100.0;
        state.lastCallTime = now;

        const brightness = 0.6 + intensity * 0.8;

        state.passRunner.render(width, height, () => {
            gl.uniform1f(state.getLoc('warp_time'), state.warpTime);
            gl.uniform1f(state.getLoc('warp_roll'), 0);
            gl.uniform1f(state.getLoc('warp_pitch'), 0);
            gl.uniform1f(state.getLoc('warp_yaw'), 0);
            gl.uniform1f(state.getLoc('bass_reactivity'), 0);
            gl.uniform1f(state.getLoc('syn_BassLevel'), 0);
            gl.uniform1f(state.getLoc('syn_BassHits'), 0);
            gl.uniform1f(state.getLoc('brightness_boost'), brightness);
        });

        return state.passRunner.getOutputTexture();
    }

    return { load, render };
}
