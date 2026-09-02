// One FBO+texture per named PASSES target. Black Hole's passes are read via
// texelFetch at explicit LOD 0 only, so plain non-mipmapped RGBA8 textures
// are sufficient - no mip generation, no filtering mode matters.
//
// A scene can mark a pass "FLOAT": true (e.g. Vein Melter's reaction-
// diffusion sim, which accumulates values well outside 0..1) - those get
// RGBA16F/HALF_FLOAT instead, matching what an 8-bit clamp would otherwise
// silently corrupt.
export function createBufferTarget(gl, width, height, float = false) {
    const internalFormat = float ? gl.RGBA16F : gl.RGBA8;
    const type = float ? gl.HALF_FLOAT : gl.UNSIGNED_BYTE;

    const texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texImage2D(gl.TEXTURE_2D, 0, internalFormat, width, height, 0, gl.RGBA, type, null);

    const framebuffer = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
    const status = gl.checkFramebufferStatus(gl.FRAMEBUFFER);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    if (status !== gl.FRAMEBUFFER_COMPLETE) {
        throw new Error(`Framebuffer incomplete: 0x${status.toString(16)}`);
    }

    return { texture, framebuffer, width, height, float };
}

export function resizeBufferTarget(gl, target, width, height) {
    if (target.width === width && target.height === height) return;
    const internalFormat = target.float ? gl.RGBA16F : gl.RGBA8;
    const type = target.float ? gl.HALF_FLOAT : gl.UNSIGNED_BYTE;
    gl.bindTexture(gl.TEXTURE_2D, target.texture);
    gl.texImage2D(gl.TEXTURE_2D, 0, internalFormat, width, height, 0, gl.RGBA, type, null);
    target.width = width;
    target.height = height;
}

export function deleteBufferTarget(gl, target) {
    gl.deleteTexture(target.texture);
    gl.deleteFramebuffer(target.framebuffer);
}
