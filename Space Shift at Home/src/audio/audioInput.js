// Mic or desktop/tab audio capture behind an explicit user action - browsers
// won't grant getUserMedia/getDisplayMedia permission without one, so this
// is only ever called from a button click, never on page load.
// Browsers apply voice-call processing to mic tracks by default (echo
// cancellation, noise suppression, auto gain control). Noise suppression in
// particular tends to treat low-frequency content as rumble and suppress
// it - actively working against a bass analyzer - so all three are
// explicitly disabled to get the rawest signal the browser will give us.
const RAW_AUDIO_CONSTRAINTS = {
    echoCancellation: false,
    noiseSuppression: false,
    autoGainControl: false,
};

export async function startMicInput() {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: RAW_AUDIO_CONSTRAINTS, video: false });
    return stream;
}

export async function startDesktopAudioInput() {
    // video is required by spec to get a shareable-audio prompt on most
    // browsers even though we never use the video track.
    const stream = await navigator.mediaDevices.getDisplayMedia({ audio: RAW_AUDIO_CONSTRAINTS, video: true });
    for (const track of stream.getVideoTracks()) track.stop();
    return stream;
}

export function createAnalyser(stream) {
    const audioContext = new (window.AudioContext || window.webkitAudioContext)();
    const source = audioContext.createMediaStreamSource(stream);
    const analyser = audioContext.createAnalyser();
    analyser.fftSize = 2048;
    analyser.smoothingTimeConstant = 0; // we do our own attack/release smoothing
    source.connect(analyser);
    return { audioContext, analyser, stream };
}

export function stopAudioInput(handle) {
    if (!handle) return;
    for (const track of handle.stream.getTracks()) track.stop();
    handle.audioContext.close();
}
