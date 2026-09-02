export function createContext(canvas) {
    const gl = canvas.getContext('webgl2', { antialias: false, alpha: false });
    if (!gl) throw new Error('WebGL2 is not available in this browser.');
    // Needed to render into RGBA16F color attachments (feedback-buffer scenes
    // like Vein Melter declare FLOAT passes) - WebGL2 exposes the float
    // texture format either way, but attaching one to a framebuffer as a
    // render target specifically requires this extension.
    gl.getExtension('EXT_color_buffer_float');
    return gl;
}

// `scale` renders the WebGL drawing buffer smaller than the canvas's CSS
// display size (which stays full-viewport) - the browser upscales it on
// composite. Internal resolution drives cost everywhere (raymarch steps,
// blur taps, buffer sizes), so this is the highest-leverage performance knob.
export function resizeToDisplaySize(canvas, scale = 1) {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const width = Math.max(1, Math.round(canvas.clientWidth * dpr * scale));
    const height = Math.max(1, Math.round(canvas.clientHeight * dpr * scale));
    if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
        return true;
    }
    return false;
}
