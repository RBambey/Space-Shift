// A single oversized triangle that covers the whole clip-space viewport -
// cheaper than a quad (no diagonal seam, no second draw call for a 4th vertex).
const VERTEX_SOURCE = `#version 300 es
layout(location = 0) in vec2 a_pos;
out vec2 v_uv;
void main() {
    v_uv = (a_pos + 1.0) * 0.5;
    gl_Position = vec4(a_pos, 0.0, 1.0);
}
`;

export function createFullscreenQuad(gl) {
    const vao = gl.createVertexArray();
    const vbo = gl.createBuffer();
    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([
        -1, -1,
         3, -1,
        -1,  3,
    ]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    gl.bindVertexArray(null);

    return {
        vertexSource: VERTEX_SOURCE,
        draw() {
            gl.bindVertexArray(vao);
            gl.drawArrays(gl.TRIANGLES, 0, 3);
        },
    };
}
