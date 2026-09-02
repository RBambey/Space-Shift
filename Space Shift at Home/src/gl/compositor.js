import { compileProgram } from './program.js';

// Blends two already-rendered scene textures straight onto the canvas.
// Used only during a scene transition, where the outgoing scene, the warp
// overlay, and the incoming scene each render to their own offscreen
// texture first (via passRunner.render(), skipping presentToCanvas) so
// they can be cross-faded here instead of each fighting over the canvas.
const FRAGMENT_SOURCE = `#version 300 es
precision highp float;
uniform sampler2D texA;
uniform sampler2D texB;
uniform float mixFactor;
in vec2 v_uv;
out vec4 fragColor;
void main() {
    vec4 a = texture(texA, v_uv);
    vec4 b = texture(texB, v_uv);
    fragColor = mix(a, b, mixFactor);
}
`;

export function createCompositor(gl, quad) {
    const program = compileProgram(gl, quad.vertexSource, FRAGMENT_SOURCE, 0);
    const texALoc = gl.getUniformLocation(program, 'texA');
    const texBLoc = gl.getUniformLocation(program, 'texB');
    const mixLoc = gl.getUniformLocation(program, 'mixFactor');

    function blendToCanvas(texA, texB, mixFactor, width, height) {
        gl.useProgram(program);
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        gl.viewport(0, 0, width, height);

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, texA);
        gl.uniform1i(texALoc, 0);

        gl.activeTexture(gl.TEXTURE1);
        gl.bindTexture(gl.TEXTURE_2D, texB);
        gl.uniform1i(texBLoc, 1);

        gl.uniform1f(mixLoc, mixFactor);

        quad.draw();
    }

    return { blendToCanvas };
}
