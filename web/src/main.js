import { createContext, resizeToDisplaySize } from './gl/context.js';
import { createFullscreenQuad } from './gl/fullscreenQuad.js';
import { compileProgram } from './gl/program.js';
import { loadScene as fetchSceneFiles } from './scene/sceneLoader.js';
import { generateWrapper } from './scene/wrapperGenerator.js';
import { createPassRunner } from './scene/passRunner.js';
import { createControlsRuntime } from './scene/controlsRuntime.js';
import { createScriptHost } from './scene/scriptHost.js';
import { createKeyboardInput } from './input/keyboard.js';
import { startMicInput, startDesktopAudioInput, createAnalyser, stopAudioInput } from './audio/audioInput.js';
import { createBassAnalyzer } from './audio/audioAnalysis.js';
import { presetsForScene, applyPreset } from './scene/presets.js';
import { applyScenePatches } from './scene/patches.js';

const BUNDLED_PRESETS_PATH = './presets/exported-presets_09.01.26.json';

// A dropdown picks the active scene for now (full page reload on change) -
// the eventual warp-transition feature will replace this with a live,
// in-page switch. `credits` surfaces the *original* authors scenes are
// based on/adapted from, separate from scene.json's own CREDIT field.
const SCENES = [
    {
        id: 'black-hole-redux',
        dir: 'BlackHoleRedux.synScene',
        label: 'Black Hole Redux',
        credits: [
            'Based on "Retro 70s Gas Giant" by mrange',
            'Black hole visual "Singularity" by @XorDev (Shadertoy)',
        ],
    },
    {
        id: 'flying-synth',
        dir: 'FlyingSynth.synScene',
        label: 'Flying Synth',
        credits: [],
    },
    {
        id: 'ocean-planet',
        dir: 'ocean_planet.synScene',
        label: 'Ocean Planet',
        credits: [
            'Ocean shader based on "Seascape" by Alexander Alekseev (TDM)',
        ],
    },
    {
        id: 'remnant-planet',
        dir: 'RemnantPlanet.synScene',
        label: 'Remnant Planet',
        credits: [
            'Fractal by David Hoskins (CC-BY-NC-SA 3.0)',
        ],
    },
    {
        id: 'forest-planet',
        dir: 'ForestPlanet.synScene',
        label: 'Forest Planet',
        credits: [],
    },
    {
        id: 'dino-planet',
        dir: 'DinoPlanet.synScene',
        label: 'Dino Planet',
        credits: [],
    },
];

const VEC_TYPES = new Set(['xy smooth', 'xy', 'color smooth', 'color']);
const FLIGHT_CONTROL_NAMES = new Set(['pitch', 'roll_rate', 'yaw_rate', 'fly_speed', 'barrel_roll', 'recenter']);

function currentSceneEntry() {
    const requested = new URLSearchParams(location.search).get('scene');
    return SCENES.find(s => s.id === requested) || SCENES[0];
}

async function main() {
    const sceneEntry = currentSceneEntry();
    setupSceneSelectUI(sceneEntry);

    const canvas = document.getElementById('gl-canvas');
    const gl = createContext(canvas);

    const { glsl: rawGlsl, sceneJson, script } = await fetchSceneFiles(`../Synesthesia/${sceneEntry.dir}`);
    const glsl = applyScenePatches(rawGlsl, sceneJson.TITLE);
    const wrapper = generateWrapper({ glsl, sceneJson, script });

    document.title = `Space Shift — ${sceneJson.TITLE} (web)`;
    document.getElementById('scene-title').textContent = sceneJson.TITLE;
    setupCreditsUI(sceneJson, sceneEntry);

    const quad = createFullscreenQuad(gl);
    const program = compileProgram(gl, quad.vertexSource, wrapper.fragmentSource, wrapper.headerLineCount);

    const controlsRuntime = createControlsRuntime(sceneJson.CONTROLS || []);
    const uniformQueue = new Map();
    const sceneApi = createScriptHost(script, wrapper.controlNames, controlsRuntime, uniformQueue);
    const keyboard = createKeyboardInput(controlsRuntime, sceneJson.CONTROLS || []);
    const passRunner = createPassRunner(gl, program, quad, sceneJson.PASSES || []);

    const controlPanel = buildControlPanel(sceneJson.CONTROLS || [], controlsRuntime);
    const audioState = setupAudioUI();
    const sensitivity = setupSensitivityUI();
    const perf = setupPerfUI(canvas);
    const waveform = setupWaveformUI(() => audioState.getAnalyserNode());
    await setupPresetsUI(sceneJson, controlsRuntime, controlPanel);

    const locCache = new Map();
    function getLoc(name) {
        if (!locCache.has(name)) locCache.set(name, gl.getUniformLocation(program, name));
        return locCache.get(name);
    }

    const timeLoc = getLoc('TIME');
    const startTime = performance.now();

    sceneApi.setup();

    let lastFrame = performance.now();

    function frame(now) {
        const dt = Math.min((now - lastFrame) / 1000, 1 / 15);
        lastFrame = now;

        resizeToDisplaySize(canvas, perf.getScale());
        perf.tick(dt);

        keyboard.update(dt);
        controlsRuntime.update(dt);

        const { level: rawLevel, hits: rawHits, highLevel: rawHigh, bassTime } = audioState.update(dt);
        const gain = sensitivity.getValue();
        const bassLevel = Math.min(1, rawLevel * gain);
        const bassHits = Math.min(1, rawHits * gain);
        const highLevel = Math.min(1, rawHigh * gain);
        uniformQueue.set('syn_BassLevel', [bassLevel]);
        uniformQueue.set('syn_BassHits', [bassHits]);
        uniformQueue.set('syn_BassTime', [bassTime]);
        uniformQueue.set('syn_HighLevel', [highLevel]);
        window.__audioDebug = { level: bassLevel, hits: bassHits, highLevel, bassTime, raw: rawLevel, sensitivity: gain };
        waveform.draw();

        sceneApi.refresh();
        sceneApi.update(dt);

        passRunner.resize(canvas.width, canvas.height);
        passRunner.render(canvas.width, canvas.height, () => {
            gl.uniform1f(timeLoc, (now - startTime) / 1000);
            for (const name of wrapper.controlNames) {
                const loc = getLoc(name);
                if (!loc) continue;
                if (VEC_TYPES.has(controlsRuntime.typeOf(name))) {
                    const v = controlsRuntime.get(name);
                    if ('z' in v) gl.uniform3f(loc, v.x, v.y, v.z);
                    else gl.uniform2f(loc, v.x, v.y);
                } else {
                    gl.uniform1f(loc, controlsRuntime.get(name));
                }
            }
            for (const [name, args] of uniformQueue) {
                const loc = getLoc(name);
                if (!loc) continue;
                if (args.length >= 4) gl.uniform4f(loc, args[0], args[1], args[2], args[3]);
                else if (args.length === 3) gl.uniform3f(loc, args[0], args[1], args[2]);
                else if (args.length === 2) gl.uniform2f(loc, args[0], args[1]);
                else gl.uniform1f(loc, args[0]);
            }
        });

        requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
}

function buildControlPanel(controls, controlsRuntime) {
    const panel = document.getElementById('control-panel');
    const inputsByName = new Map();

    for (const c of controls) {
        if (FLIGHT_CONTROL_NAMES.has(c.NAME)) continue;

        const row = document.createElement('div');
        row.className = 'control-row';
        const label = document.createElement('label');
        label.textContent = c.NAME;
        row.appendChild(label);

        if (c.TYPE === 'toggle' || c.TYPE === 'toggle smooth') {
            const input = document.createElement('input');
            input.type = 'checkbox';
            input.checked = c.DEFAULT > 0.5;
            input.addEventListener('input', () => controlsRuntime.set(c.NAME, input.checked ? 1 : 0));
            row.appendChild(input);
            inputsByName.set(c.NAME, { kind: 'toggle', el: input });
        } else if (VEC_TYPES.has(c.TYPE)) {
            const keys = c.MIN.length === 3 ? ['x', 'y', 'z'] : ['x', 'y'];
            const current = {};
            const els = [];
            keys.forEach((k, i) => { current[k] = c.DEFAULT[i]; });
            keys.forEach((k, i) => {
                const input = document.createElement('input');
                input.type = 'range';
                input.min = c.MIN[i];
                input.max = c.MAX[i];
                input.step = (c.MAX[i] - c.MIN[i]) / 500;
                input.value = c.DEFAULT[i];
                input.addEventListener('input', () => {
                    current[k] = parseFloat(input.value);
                    controlsRuntime.set(c.NAME, current);
                });
                row.appendChild(input);
                els.push(input);
            });
            inputsByName.set(c.NAME, { kind: 'vec', keys, current, els });
        } else {
            const input = document.createElement('input');
            input.type = 'range';
            input.min = c.MIN;
            input.max = c.MAX;
            input.step = (c.MAX - c.MIN) / 500;
            input.value = c.DEFAULT;
            input.addEventListener('input', () => controlsRuntime.set(c.NAME, parseFloat(input.value)));
            row.appendChild(input);
            inputsByName.set(c.NAME, { kind: 'scalar', el: input });
        }

        panel.appendChild(row);
    }

    return {
        // Pushes {name: value} (scalar number, or {x,y[,z]} for vec types)
        // into the panel's own UI elements, e.g. after a preset load - the
        // controlsRuntime values were already set directly, this just keeps
        // the sliders visually in sync with them.
        sync(appliedValues) {
            for (const [name, value] of Object.entries(appliedValues)) {
                const entry = inputsByName.get(name);
                if (!entry) continue;
                if (entry.kind === 'toggle') {
                    entry.el.checked = value > 0.5;
                } else if (entry.kind === 'vec') {
                    entry.keys.forEach((k, i) => {
                        entry.current[k] = value[k];
                        entry.els[i].value = value[k];
                    });
                } else {
                    entry.el.value = value;
                }
            }
        },
    };
}

// Loads the bundled exported-presets JSON on startup (best-effort - it's
// fine if it's missing) and lets the user load a different exported file at
// any time. Only presets for the currently-running scene (matched by
// scene.json TITLE, the same key Synesthesia's own export uses) are shown.
async function setupPresetsUI(sceneJson, controlsRuntime, controlPanel) {
    const select = document.getElementById('preset-select');
    const fileInput = document.getElementById('preset-file-input');
    const statusEl = document.getElementById('presets-status');

    let presetsByName = {};

    function applyByName(name) {
        const preset = presetsByName[name];
        if (!preset) return;
        const applied = applyPreset(preset, sceneJson.CONTROLS || [], controlsRuntime, FLIGHT_CONTROL_NAMES);
        controlPanel.sync(applied);
        select.value = name;
        statusEl.textContent = `loaded "${name}"`;
    }

    function populate(presets, sourceLabel) {
        presetsByName = presets;
        select.innerHTML = '<option value="">— presets —</option>';
        const names = Object.keys(presets);
        for (const name of names) {
            const opt = document.createElement('option');
            opt.value = name;
            opt.textContent = name;
            select.appendChild(opt);
        }
        statusEl.textContent = names.length
            ? `${names.length} preset(s) for "${sceneJson.TITLE}" from ${sourceLabel}`
            : `no presets for "${sceneJson.TITLE}" in ${sourceLabel}`;
        // Load by default so the scene doesn't start on raw scene.json
        // defaults whenever a matching preset exists.
        if (names.length) applyByName(names[0]);
    }

    try {
        const res = await fetch(BUNDLED_PRESETS_PATH);
        if (res.ok) {
            populate(presetsForScene(await res.json(), sceneJson.TITLE), 'bundled export');
        } else {
            statusEl.textContent = 'no bundled presets found';
        }
    } catch {
        statusEl.textContent = 'no bundled presets found';
    }

    select.addEventListener('change', () => applyByName(select.value));

    fileInput.addEventListener('change', async () => {
        const file = fileInput.files[0];
        if (!file) return;
        try {
            const json = JSON.parse(await file.text());
            populate(presetsForScene(json, sceneJson.TITLE), file.name);
        } catch (err) {
            statusEl.textContent = `couldn't read ${file.name}: ${err.message}`;
        }
    });
}

// Scene switching is reload-based for now, not a live in-page swap - much
// simpler and more robust than tearing down/rebuilding all the GL state
// (programs, framebuffers, event listeners) by hand, which is real work
// that only pays off once there's an actual warp-transition effect that
// needs the scene to stay live across the switch.
function setupSceneSelectUI(currentEntry) {
    const select = document.getElementById('scene-select');
    select.innerHTML = '';
    for (const entry of SCENES) {
        const opt = document.createElement('option');
        opt.value = entry.id;
        opt.textContent = entry.label;
        select.appendChild(opt);
    }
    select.value = currentEntry.id;

    select.addEventListener('change', () => {
        const url = new URL(location.href);
        url.searchParams.set('scene', select.value);
        location.href = url.toString();
    });
}

function setupCreditsUI(sceneJson, sceneEntry) {
    const panel = document.getElementById('credits-panel');
    panel.innerHTML = '';

    const sceneLine = document.createElement('div');
    sceneLine.textContent = `${sceneJson.TITLE} — ${sceneJson.CREDIT || 'RBambey'}`;
    sceneLine.style.fontWeight = 'bold';
    panel.appendChild(sceneLine);

    for (const line of sceneEntry.credits) {
        const div = document.createElement('div');
        div.textContent = line;
        panel.appendChild(div);
    }
}

function setupSensitivityUI() {
    const slider = document.getElementById('sensitivity-slider');
    const valueEl = document.getElementById('sensitivity-value');
    let value = parseFloat(localStorage.getItem('audioSensitivity')) || 1;
    slider.value = value;
    valueEl.textContent = `${value.toFixed(1)}×`;

    slider.addEventListener('input', () => {
        value = parseFloat(slider.value);
        valueEl.textContent = `${value.toFixed(1)}×`;
        localStorage.setItem('audioSensitivity', value);
    });

    return {
        getValue() {
            return value;
        },
    };
}

function setupPerfUI(canvas) {
    const buttons = [...document.querySelectorAll('#resolution-panel button')];
    const fpsEl = document.getElementById('fps-readout');
    let scale = parseFloat(localStorage.getItem('renderScale')) || 1;

    function setActive() {
        for (const btn of buttons) {
            btn.classList.toggle('active', parseFloat(btn.dataset.scale) === scale);
        }
    }
    setActive();

    for (const btn of buttons) {
        btn.addEventListener('click', () => {
            scale = parseFloat(btn.dataset.scale);
            localStorage.setItem('renderScale', scale);
            setActive();
        });
    }

    let frameCount = 0;
    let accum = 0;

    return {
        getScale() {
            return scale;
        },
        tick(dt) {
            frameCount++;
            accum += dt;
            if (accum >= 0.5) {
                const fps = frameCount / accum;
                fpsEl.textContent = `${fps.toFixed(0)} fps · ${canvas.width}×${canvas.height}`;
                frameCount = 0;
                accum = 0;
            }
        },
    };
}

function setupAudioUI() {
    const statusEl = document.getElementById('audio-status');
    let analyzer = null;
    let handle = null;

    async function enable(kind) {
        if (handle) stopAudioInput(handle);
        try {
            const stream = kind === 'mic' ? await startMicInput() : await startDesktopAudioInput();
            handle = createAnalyser(stream);
            analyzer = createBassAnalyzer(handle.analyser, handle.audioContext.sampleRate);
            statusEl.textContent = `audio: ${kind}`;
            localStorage.setItem('audioSource', kind);
        } catch (err) {
            statusEl.textContent = `audio error: ${err.message}`;
        }
    }

    document.getElementById('audio-mic').addEventListener('click', () => enable('mic'));
    document.getElementById('audio-desktop').addEventListener('click', () => enable('desktop'));
    document.getElementById('audio-none').addEventListener('click', () => {
        if (handle) stopAudioInput(handle);
        handle = null;
        analyzer = null;
        statusEl.textContent = 'audio: none';
        localStorage.removeItem('audioSource');
    });

    // Scene switching is a full page reload, which can't keep a live
    // MediaStream/AudioContext alive - so audio "persisting across scenes"
    // means remembering the choice and reconnecting on load instead. Mic
    // permission survives silently once granted, so it can resume itself
    // with no prompt. Desktop/tab capture can't: getDisplayMedia requires a
    // fresh user gesture every time by browser design, no way around that,
    // so it just asks for one more click instead of failing silently.
    const remembered = localStorage.getItem('audioSource');
    if (remembered === 'mic') {
        enable('mic');
    } else if (remembered === 'desktop') {
        statusEl.textContent = 'audio: click "Desktop audio" to resume';
    }

    return {
        update(dt) {
            return analyzer ? analyzer.update(dt) : { level: 0, hits: 0, highLevel: 0, bassTime: 0 };
        },
        getAnalyserNode() {
            return handle ? handle.analyser : null;
        },
    };
}

function setupWaveformUI(getAnalyserNode) {
    const canvas = document.getElementById('waveform-canvas');
    const ctx = canvas.getContext('2d');
    const toggle = document.getElementById('waveform-toggle');
    const timeDomain = new Uint8Array(2048); // matches the fixed fftSize set in audioInput.js

    let enabled = toggle.checked;
    canvas.style.display = enabled ? 'block' : 'none';
    toggle.addEventListener('change', () => {
        enabled = toggle.checked;
        canvas.style.display = enabled ? 'block' : 'none';
    });

    return {
        draw() {
            if (!enabled) return;

            ctx.fillStyle = '#111';
            ctx.fillRect(0, 0, canvas.width, canvas.height);

            const analyser = getAnalyserNode();
            if (!analyser) {
                ctx.fillStyle = '#555';
                ctx.font = '10px monospace';
                ctx.fillText('no audio source', 6, canvas.height / 2 + 3);
                return;
            }

            analyser.getByteTimeDomainData(timeDomain);
            ctx.strokeStyle = '#4a90d9';
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            const step = timeDomain.length / canvas.width;
            for (let x = 0; x < canvas.width; x++) {
                const sample = timeDomain[Math.floor(x * step)];
                const y = (sample / 255) * canvas.height;
                if (x === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            }
            ctx.stroke();
        },
    };
}

main().catch(err => {
    console.error(err);
    document.getElementById('error-banner').textContent = err.message;
    document.getElementById('error-banner').style.display = 'block';
});
