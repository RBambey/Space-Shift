// Black Hole Redux reads syn_BassLevel/syn_BassHits; Flying Synth also reads
// syn_HighLevel (star twinkle) and syn_BassTime (seconds since the last bass
// hit, driving its outward-expanding terrain ripple). Real beat/BPM tracking
// is out of scope (per the plan) - bass "hits" are just a rising-edge onset
// flag against a slow rolling average, decaying back to 0 over ~150ms.
export function createBassAnalyzer(analyser, sampleRate) {
    const bins = new Uint8Array(analyser.frequencyBinCount);
    const binHz = sampleRate / analyser.fftSize;
    const bassLo = Math.max(1, Math.floor(20 / binHz));
    const bassHi = Math.max(bassLo + 1, Math.floor(250 / binHz));
    const highLo = Math.max(bassHi, Math.floor(2000 / binHz));
    const highHi = Math.min(bins.length, Math.max(highLo + 1, Math.floor(8000 / binHz)));

    let level = 0;
    let highLevel = 0;
    const attack = 0.6;
    const release = 0.12;

    let rollingAvg = 0;
    let hits = 0;
    let bassTime = 0;

    function bandAverage(lo, hi) {
        let sum = 0;
        for (let i = lo; i < hi; i++) sum += bins[i];
        return (sum / (hi - lo)) / 255;
    }

    function update(dt) {
        analyser.getByteFrequencyData(bins);

        const rawBass = bandAverage(bassLo, bassHi);
        const bassRate = rawBass > level ? attack : release;
        level += (rawBass - level) * (1 - Math.exp(-dt / bassRate));

        const rawHigh = bandAverage(highLo, highHi);
        const highRate = rawHigh > highLevel ? attack : release;
        highLevel += (rawHigh - highLevel) * (1 - Math.exp(-dt / highRate));

        rollingAvg += (rawBass - rollingAvg) * (1 - Math.exp(-dt / 1.5));
        if (rawBass > rollingAvg * 1.35 && rawBass > 0.15) {
            hits = 1;
            bassTime = 0;
        } else {
            hits -= hits * (1 - Math.exp(-dt / 0.15));
            bassTime += dt;
        }

        return { level, hits, highLevel, bassTime };
    }

    return { update };
}

// syn_Spectrum (City's antenna FFT read via textureLod(...).y) - a 1-row
// texture of the current frequency spectrum, replicated across R/G/B so a
// scene reading any single channel gets the same data regardless of which
// channel Synesthesia's own convention happens to use internally (unknown
// without their source). Linearly downsampled from the raw FFT bins - not
// verified to match Synesthesia's own log-scaling, if any, but close enough
// for antenna-style level meters.
const SPECTRUM_WIDTH = 128;

export function createSpectrumTexture(gl, getAnalyserNode) {
    const row = new Uint8Array(SPECTRUM_WIDTH * 4);
    let bins = null;

    const texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, SPECTRUM_WIDTH, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, row);

    function update() {
        const analyser = getAnalyserNode();
        if (!analyser) return;
        if (!bins || bins.length !== analyser.frequencyBinCount) {
            bins = new Uint8Array(analyser.frequencyBinCount);
        }
        analyser.getByteFrequencyData(bins);

        const step = bins.length / SPECTRUM_WIDTH;
        for (let x = 0; x < SPECTRUM_WIDTH; x++) {
            const v = bins[Math.floor(x * step)];
            row[x * 4] = v; row[x * 4 + 1] = v; row[x * 4 + 2] = v; row[x * 4 + 3] = 255;
        }
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, SPECTRUM_WIDTH, 1, gl.RGBA, gl.UNSIGNED_BYTE, row);
    }

    return { texture, update };
}
