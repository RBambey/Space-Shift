// Loads a scene's IMAGES (scene.json's IMAGES array: {NAME, PATH} pairs
// pointing at bundled jpg/png files) as real GL textures, keyed by NAME so
// they can be bound straight to the matching sampler2D uniform.
export async function loadSceneImages(gl, sceneDir, images) {
    const entries = await Promise.all((images || []).map(async ({ NAME, PATH }) => {
        const bitmap = await createImageBitmap(await (await fetch(`${sceneDir}/${PATH}`)).blob());
        const texture = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, bitmap);
        gl.generateMipmap(gl.TEXTURE_2D);
        bitmap.close();
        return [NAME, texture];
    }));
    return new Map(entries);
}
