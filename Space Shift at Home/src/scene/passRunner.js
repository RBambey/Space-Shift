import { createBufferTarget, resizeBufferTarget, deleteBufferTarget } from '../gl/framebuffer.js';

// Confirmed from BlackHole.synScene/main.glsl (and identical in
// BlackHoleRedux): PASSINDEX runs 0..N-1 writing to PASSES[i].TARGET in
// declared order, then PASSINDEX == N (one past the last PASSES entry)
// is the final composite. All named-buffer reads in these scenes are
// same-frame (no double-buffering needed for BuffA-D themselves).
//
// syn_FinalPass (the previous frame's fully composited output, used e.g.
// for BlackHoleRedux's motion_blur) is a separate, always-on ping-pong
// pair: the final pass renders into one side while syn_FinalPass reads the
// other side (last frame's result), then that side is blitted to the
// visible canvas and the two sides swap for next frame. Rendering the
// final pass directly onto the same texture it reads as syn_FinalPass
// would itself be a feedback loop, same class of bug as the BuffX case.
export function createPassRunner(gl, program, quad, passConfigs) {
    const targets = passConfigs.map(p => ({
        name: p.TARGET,
        buffer: createBufferTarget(gl, 16, 16, !!p.FLOAT),
    }));
    const finalPingPong = [createBufferTarget(gl, 16, 16), createBufferTarget(gl, 16, 16)];
    let finalReadIndex = 0;

    const passIndexLoc = gl.getUniformLocation(program, 'PASSINDEX');
    const renderSizeLoc = gl.getUniformLocation(program, 'RENDERSIZE');
    const bufferLocs = targets.map(t => gl.getUniformLocation(program, t.name));
    const finalPassLoc = gl.getUniformLocation(program, 'syn_FinalPass');
    const finalPassUnit = targets.length;

    function resize(width, height) {
        for (const t of targets) resizeBufferTarget(gl, t.buffer, width, height);
        for (const t of finalPingPong) resizeBufferTarget(gl, t, width, height);
    }

    function render(canvasWidth, canvasHeight, uploadUniforms) {
        gl.useProgram(program);

        const writeIndex = 1 - finalReadIndex;

        targets.forEach((t, unit) => {
            gl.activeTexture(gl.TEXTURE0 + unit);
            if (bufferLocs[unit]) gl.uniform1i(bufferLocs[unit], unit);
        });
        gl.activeTexture(gl.TEXTURE0 + finalPassUnit);
        gl.bindTexture(gl.TEXTURE_2D, finalPingPong[finalReadIndex].texture);
        if (finalPassLoc) gl.uniform1i(finalPassLoc, finalPassUnit);

        const passCount = targets.length + 1;
        for (let i = 0; i < passCount; i++) {
            const isFinal = i === targets.length;
            const width = isFinal ? canvasWidth : targets[i].buffer.width;
            const height = isFinal ? canvasHeight : targets[i].buffer.height;

            // A buffer being written this pass must never also be bound as a
            // sampler input at the same time (WebGL feedback loop -> the
            // draw silently produces nothing).
            targets.forEach((t, unit) => {
                gl.activeTexture(gl.TEXTURE0 + unit);
                gl.bindTexture(gl.TEXTURE_2D, unit === i ? null : t.buffer.texture);
            });

            gl.bindFramebuffer(gl.FRAMEBUFFER, isFinal ? finalPingPong[writeIndex].framebuffer : targets[i].buffer.framebuffer);
            gl.viewport(0, 0, width, height);

            gl.uniform1i(passIndexLoc, i);
            gl.uniform2f(renderSizeLoc, width, height);
            uploadUniforms(i, width, height);

            quad.draw();
        }

        finalReadIndex = writeIndex;
    }

    // Blits the just-rendered frame onto the visible canvas. Split out from
    // render() so a scene can be rendered off-canvas instead - e.g. during
    // the warp transition, where two scenes' outputs and the warp effect's
    // output all need to be composited together before anything hits the
    // actual canvas.
    function presentToCanvas(canvasWidth, canvasHeight) {
        gl.bindFramebuffer(gl.READ_FRAMEBUFFER, finalPingPong[finalReadIndex].framebuffer);
        gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, null);
        gl.blitFramebuffer(0, 0, canvasWidth, canvasHeight, 0, 0, canvasWidth, canvasHeight, gl.COLOR_BUFFER_BIT, gl.NEAREST);
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    }

    function getOutputTexture() {
        return finalPingPong[finalReadIndex].texture;
    }

    function dispose() {
        for (const t of targets) deleteBufferTarget(gl, t.buffer);
        for (const t of finalPingPong) deleteBufferTarget(gl, t);
    }

    return { resize, render, presentToCanvas, getOutputTexture, dispose };
}
