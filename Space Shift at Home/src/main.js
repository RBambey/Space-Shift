import { createContext, resizeToDisplaySize } from './gl/context.js';
import { createFullscreenQuad } from './gl/fullscreenQuad.js';
import { compileProgram } from './gl/program.js';
import { createCompositor } from './gl/compositor.js';
import { loadScene as fetchSceneFiles } from './scene/sceneLoader.js';
import { generateWrapper } from './scene/wrapperGenerator.js';
import { createPassRunner } from './scene/passRunner.js';
import { createControlsRuntime } from './scene/controlsRuntime.js';
import { createScriptHost } from './scene/scriptHost.js';
import { createKeyboardInput } from './input/keyboard.js';
import { startMicInput, startDesktopAudioInput, createAnalyser, stopAudioInput } from './audio/audioInput.js';
import { createBassAnalyzer, createSpectrumTexture } from './audio/audioAnalysis.js';
import { presetsForScene, applyPreset } from './scene/presets.js';
import { applyScenePatches } from './scene/patches.js';
import { loadSceneImages } from './scene/imageLoader.js';
import { createWarpOverlay } from './scene/warpOverlay.js';

const BUNDLED_PRESETS_PATH = './presets/exported-presets_09.01.26.json';

// The warp effect's own envelope across a transition: ramps up (old scene
// visible, fading toward warp), cruises at full intensity (pure warp,
// nothing else visible - this is when the outgoing scene actually gets
// disposed and the incoming one takes over, hidden from view), then ramps
// back down (warp fading toward the new scene).
const WARP_RAMP_IN = 0.35;
const WARP_HOLD = 0.55;
const WARP_RAMP_OUT = 0.5;
const WARP_TOTAL = WARP_RAMP_IN + WARP_HOLD + WARP_RAMP_OUT;

// `credits` surfaces the *original* authors scenes are based on/adapted
// from, separate from scene.json's own CREDIT field.
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
    {
        id: 'city',
        dir: 'City.synScene',
        label: 'City',
        credits: [
            'Grid marching from "Grid of Cylinders" by iq (Shadertoy)',
        ],
    },
    {
        id: 'flying-70s-retro',
        dir: 'Flying70sRetro.synScene',
        label: 'Flying 70s Retro',
        credits: [],
    },
    {
        id: 'goo',
        dir: 'Goo.synScene',
        label: 'Goo',
        credits: [
            'Original shader by Kamil Kolaczynski / revers (CC-BY-NC-SA 3.0)',
            'Raymarching/lighting by iq',
            'Camera path by Shane, "Subterranean Fly-Through" (Shadertoy)',
            'Wet-stone specular trick by TDM (Shadertoy)',
        ],
    },
    {
        id: 'monster',
        dir: 'Monster.synScene',
        label: 'Monster',
        credits: [
            'Original shader "Lowlands juggernauts" by evvvvil_',
        ],
    },
    {
        id: 'traced-tunnel',
        dir: 'tracedtunnelFlying.synScene',
        label: 'Traced Tunnel',
        credits: [
            'By Shane, based on "Path Racer" by W23 and "Corridor Travel" by NuSan',
            'No live media/webcam feed in this web port - stubbed with a flat gray placeholder',
        ],
    },
    {
        id: 'vein-melter',
        dir: 'vein_melter_dup.synScene',
        label: 'Vein Melter',
        credits: [
            'By cornusammonis',
        ],
    },
];

const VEC_TYPES = new Set(['xy smooth', 'xy', 'color smooth', 'color']);
const FLIGHT_CONTROL_NAMES = new Set(['pitch', 'roll_rate', 'yaw_rate', 'fly_speed', 'barrel_roll', 'recenter']);

function currentSceneEntry() {
    const requested = new URLSearchParams(location.search).get('scene');
    return SCENES.find(s => s.id === requested) || SCENES[0];
}

async function main() {
    const canvas = document.getElementById('gl-canvas');
    const gl = createContext(canvas);
    const quad = createFullscreenQuad(gl);
    const compositor = createCompositor(gl, quad);
    const warpOverlay = createWarpOverlay(gl, quad);

    // Scene-agnostic singletons - created once, now genuinely persist across
    // every scene switch since there's no more page reload backing it.
    const audioState = setupAudioUI();
    const sensitivity = setupSensitivityUI();
    const perf = setupPerfUI(canvas);
    const waveform = setupWaveformUI(() => audioState.getAnalyserNode());
    const spectrum = createSpectrumTexture(gl, () => audioState.getAnalyserNode());
    // No live video/webcam feed in this web port - scenes that read
    // syn_Media (Synesthesia's currently-selected media source) get a flat
    // gray placeholder instead so they still compile and run.
    const mediaPlaceholder = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, mediaPlaceholder);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([128, 128, 128, 255]));
    const presetsUI = initPresetsUI();
    setupMenuToggle();

    let current = null;      // active scene runtime
    let transition = null;   // { from, to, elapsed } while a warp is playing
    let switching = false;   // guards against overlapping switchScene() calls
    let latestAudio = { bassLevel: 0, bassHits: 0, bassTime: 0, highLevel: 0 };

    const sceneSelect = setupSceneSelectUI(id => switchScene(SCENES.find(s => s.id === id) || SCENES[0]));

    async function createSceneRuntime(entry) {
        const { glsl: rawGlsl, sceneJson, script } = await fetchSceneFiles(`../Synesthesia/${entry.dir}`);
        const glsl = applyScenePatches(rawGlsl, sceneJson.TITLE);
        const wrapper = generateWrapper({ glsl, sceneJson, script });
        const program = compileProgram(gl, quad.vertexSource, wrapper.fragmentSource, wrapper.headerLineCount);
        const images = await loadSceneImages(gl, `../Synesthesia/${entry.dir}`, sceneJson.IMAGES);

        const controlsRuntime = createControlsRuntime(sceneJson.CONTROLS || []);
        const uniformQueue = new Map();
        const sceneApi = createScriptHost(script, wrapper.controlNames, controlsRuntime, uniformQueue);
        const keyboard = createKeyboardInput(controlsRuntime, sceneJson.CONTROLS || []);
        const passRunner = createPassRunner(gl, program, quad, sceneJson.PASSES || []);

        const locCache = new Map();
        function getLoc(name) {
            if (!locCache.has(name)) locCache.set(name, gl.getUniformLocation(program, name));
            return locCache.get(name);
        }

        sceneApi.setup();
        const startTime = performance.now();

        return {
            entry, sceneJson, wrapper, controlsRuntime,

            step(dt) {
                keyboard.update(dt);
                controlsRuntime.update(dt);
                pushAudioUniforms(uniformQueue);
                sceneApi.refresh();
                sceneApi.update(dt);
            },

            renderToTexture(width, height, now) {
                passRunner.resize(width, height);
                passRunner.render(width, height, () => {
                    gl.uniform1f(getLoc('TIME'), (now - startTime) / 1000);
                    gl.uniform1f(getLoc('syn_Time'), (now - startTime) / 1000);
                    const spectrumLoc = getLoc('syn_Spectrum');
                    if (spectrumLoc) {
                        gl.activeTexture(gl.TEXTURE8);
                        gl.bindTexture(gl.TEXTURE_2D, spectrum.texture);
                        gl.uniform1i(spectrumLoc, 8);
                    }
                    const mediaLoc = getLoc('syn_Media');
                    if (mediaLoc) {
                        gl.activeTexture(gl.TEXTURE9);
                        gl.bindTexture(gl.TEXTURE_2D, mediaPlaceholder);
                        gl.uniform1i(mediaLoc, 9);
                    }
                    let imageUnit = 10;
                    for (const [name, texture] of images) {
                        const loc = getLoc(name);
                        if (!loc) continue;
                        gl.activeTexture(gl.TEXTURE0 + imageUnit);
                        gl.bindTexture(gl.TEXTURE_2D, texture);
                        gl.uniform1i(loc, imageUnit);
                        imageUnit++;
                    }
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
                return passRunner.getOutputTexture();
            },

            presentToCanvas(width, height) {
                passRunner.presentToCanvas(width, height);
            },

            dispose() {
                passRunner.dispose();
                gl.deleteProgram(program);
                keyboard.dispose();
                for (const texture of images.values()) gl.deleteTexture(texture);
            },
        };
    }

    function pushAudioUniforms(uniformQueue) {
        uniformQueue.set('syn_BassLevel', [latestAudio.bassLevel]);
        uniformQueue.set('syn_BassHits', [latestAudio.bassHits]);
        uniformQueue.set('syn_BassTime', [latestAudio.bassTime]);
        uniformQueue.set('syn_HighLevel', [latestAudio.highLevel]);
    }

    function applySceneUI(runtime) {
        document.title = `Space Shift — ${runtime.sceneJson.TITLE} (web)`;
        document.getElementById('scene-title').textContent = runtime.sceneJson.TITLE;
        setupCreditsUI(runtime.sceneJson, runtime.entry);
        const controlPanel = buildControlPanel(runtime.sceneJson.CONTROLS || [], runtime.controlsRuntime);
        presetsUI.loadForScene(runtime.sceneJson, runtime.controlsRuntime, controlPanel);
        sceneSelect.setValue(runtime.entry.id);

        const url = new URL(location.href);
        url.searchParams.set('scene', runtime.entry.id);
        history.replaceState(null, '', url);
    }

    // `switching` stays true for the *entire* switch, load through the last
    // frame of the visual transition - not just the async load. Otherwise a
    // second dropdown change during the ~1.4s transition would start a
    // third scene load and silently orphan the in-flight transition.to
    // (never disposed - a leaked program/passRunner) since `current` hasn't
    // been swapped to it yet. `frame()` clears the flag when a transition
    // actually finishes; only the two non-transition exits (first load,
    // error) clear it here.
    async function switchScene(entry) {
        if (switching || (current && current.entry.id === entry.id)) return;
        switching = true;
        sceneSelect.setDisabled(true);
        try {
            const [incoming] = await Promise.all([createSceneRuntime(entry), warpOverlay.load()]);
            applySceneUI(incoming);
            if (!current) {
                // First-ever load: nothing to transition from, nothing to wait on.
                current = incoming;
                switching = false;
                sceneSelect.setDisabled(false);
            } else {
                transition = { from: current, to: incoming, elapsed: 0 };
            }
        } catch (err) {
            console.error(err);
            document.getElementById('error-banner').textContent = err.message;
            document.getElementById('error-banner').style.display = 'block';
            if (current) sceneSelect.setValue(current.entry.id);
            switching = false;
            sceneSelect.setDisabled(false);
        }
    }

    function pickRandomOtherScene() {
        const choices = current ? SCENES.filter(s => s.id !== current.entry.id) : SCENES;
        return choices[Math.floor(Math.random() * choices.length)];
    }

    window.addEventListener('keydown', (e) => {
        if (e.code !== 'Space' || e.repeat) return;
        e.preventDefault();
        switchScene(pickRandomOtherScene());
    });

    let lastFrame = performance.now();

    // A scene's script.js runs almost entirely inside this loop (step() ->
    // sceneApi.update()), and a bug in ITS code (e.g. Flying 70s Retro
    // referencing syn_BassLevel as a bare global before that was supported)
    // throws with no compile-time warning. Left uncaught, that exception
    // aborts this rAF callback before it reaches its own
    // requestAnimationFrame(frame) call at the bottom - the loop simply
    // stops forever, with the canvas frozen and the scene dropdown stuck
    // disabled (switching never resets to false) and no visible error.
    // Catching here can't undo a broken scene, but at least surfaces the
    // error and un-sticks the UI instead of hard-freezing silently.
    function frame(now) {
        try {
            renderFrame(now);
        } catch (err) {
            console.error(err);
            document.getElementById('error-banner').textContent = err.message;
            document.getElementById('error-banner').style.display = 'block';
            transition = null;
            switching = false;
            sceneSelect.setDisabled(false);
        }
        requestAnimationFrame(frame);
    }

    function renderFrame(now) {
        const dt = Math.min((now - lastFrame) / 1000, 1 / 15);
        lastFrame = now;

        resizeToDisplaySize(canvas, perf.getScale());
        perf.tick(dt);

        const { level: rawLevel, hits: rawHits, highLevel: rawHigh, bassTime } = audioState.update(dt);
        spectrum.update();
        const gain = sensitivity.getValue();
        latestAudio = {
            bassLevel: Math.min(1, rawLevel * gain),
            bassHits: Math.min(1, rawHits * gain),
            bassTime,
            highLevel: Math.min(1, rawHigh * gain),
        };
        window.__audioDebug = { ...latestAudio, raw: rawLevel, sensitivity: gain };
        waveform.draw();

        window.__sceneDebug = { switching, hasTransition: !!transition, elapsed: transition ? transition.elapsed : null, dt };

        const width = canvas.width, height = canvas.height;

        if (!transition) {
            if (current) {
                current.step(dt);
                current.renderToTexture(width, height, now);
                current.presentToCanvas(width, height);
            }
        } else {
            transition.elapsed += dt;
            const t = transition.elapsed;

            transition.from.step(dt);
            transition.to.step(dt);
            const fromTex = transition.from.renderToTexture(width, height, now);
            const toTex = transition.to.renderToTexture(width, height, now);

            let intensity, mixFactor, texA, texB;
            if (t < WARP_RAMP_IN) {
                intensity = t / WARP_RAMP_IN;
                texA = fromTex; texB = warpOverlay.render(width, height, intensity);
                mixFactor = intensity;
            } else if (t < WARP_RAMP_IN + WARP_HOLD) {
                intensity = 1;
                const warpTex = warpOverlay.render(width, height, intensity);
                texA = warpTex; texB = warpTex;
                mixFactor = 0;
            } else if (t < WARP_TOTAL) {
                const rt = (t - WARP_RAMP_IN - WARP_HOLD) / WARP_RAMP_OUT;
                intensity = 1 - rt;
                texA = warpOverlay.render(width, height, intensity); texB = toTex;
                mixFactor = rt;
            } else {
                texA = toTex; texB = toTex; mixFactor = 0;
            }
            compositor.blendToCanvas(texA, texB, mixFactor, width, height);

            if (t >= WARP_TOTAL) {
                transition.from.dispose();
                current = transition.to;
                transition = null;
                switching = false;
                sceneSelect.setDisabled(false);
            }
        }
    }

    await switchScene(currentSceneEntry());
    requestAnimationFrame(frame);
}

function buildControlPanel(controls, controlsRuntime) {
    const panel = document.getElementById('control-panel');
    for (const row of panel.querySelectorAll('.control-row')) row.remove();
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

// Loads the bundled exported-presets JSON once and lets the user load a
// different exported file at any time; `loadForScene` re-filters/applies
// against whichever scene is currently active. Listeners are attached once
// here rather than per scene-switch, since the <select>/<input> elements
// themselves persist across switches now.
function initPresetsUI() {
    const select = document.getElementById('preset-select');
    const fileInput = document.getElementById('preset-file-input');
    const statusEl = document.getElementById('presets-status');

    let bundledJson = null;
    let bundledLoadFailed = false;
    let sceneJson = null;
    let controlsRuntime = null;
    let controlPanel = null;
    let presetsByName = {};

    function applyByName(name) {
        const preset = presetsByName[name];
        if (!preset || !controlsRuntime) return;
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

    select.addEventListener('change', () => applyByName(select.value));

    fileInput.addEventListener('change', async () => {
        const file = fileInput.files[0];
        if (!file) return;
        try {
            bundledJson = JSON.parse(await file.text());
            populate(presetsForScene(bundledJson, sceneJson.TITLE), file.name);
        } catch (err) {
            statusEl.textContent = `couldn't read ${file.name}: ${err.message}`;
        }
    });

    return {
        async loadForScene(newSceneJson, newControlsRuntime, newControlPanel) {
            sceneJson = newSceneJson;
            controlsRuntime = newControlsRuntime;
            controlPanel = newControlPanel;

            if (bundledJson === null && !bundledLoadFailed) {
                try {
                    const res = await fetch(BUNDLED_PRESETS_PATH);
                    bundledJson = res.ok ? await res.json() : {};
                    if (!res.ok) bundledLoadFailed = true;
                } catch {
                    bundledJson = {};
                    bundledLoadFailed = true;
                }
            }
            populate(presetsForScene(bundledJson || {}, sceneJson.TITLE), 'bundled export');
        },
    };
}

// Scene switching is now a live, in-page swap covered by the warp
// transition rather than a page reload - the dropdown just requests a
// switch through the callback; main() owns the actual transition.
function setupSceneSelectUI(onSelect) {
    const select = document.getElementById('scene-select');
    select.innerHTML = '';
    for (const entry of SCENES) {
        const opt = document.createElement('option');
        opt.value = entry.id;
        opt.textContent = entry.label;
        select.appendChild(opt);
    }

    select.addEventListener('change', () => onSelect(select.value));

    return {
        setValue(id) { select.value = id; },
        setDisabled(disabled) { select.disabled = disabled; },
    };
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

    // Now that scene switching no longer reloads the page at all, this only
    // matters for a real page refresh - mic permission survives silently
    // once granted, so it can resume itself with no prompt. Desktop/tab
    // capture can't: getDisplayMedia requires a fresh user gesture every
    // time by browser design, no way around that, so it just asks for one
    // more click instead of failing silently.
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

function setupMenuToggle() {
    const button = document.getElementById('menu-toggle');
    const panel = document.getElementById('menu-panel');
    button.addEventListener('click', () => {
        panel.hidden = !panel.hidden;
    });
}

main().catch(err => {
    console.error(err);
    document.getElementById('error-banner').textContent = err.message;
    document.getElementById('error-banner').style.display = 'block';
});
