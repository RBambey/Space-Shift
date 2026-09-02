// Most WebGL2 drivers report shader errors as "ERROR: 0:<line>: <message>"
// (the 0 is the source-string index, always 0 here since we compile a single
// concatenated string). We remap <line> back to the original main.glsl line
// number by subtracting the number of lines the wrapper generator prepended.
function remapLog(log, headerLineCount) {
    if (!log) return log;
    return log.replace(/ERROR: (\d+):(\d+):/g, (match, col, line) => {
        const original = Number(line) - headerLineCount;
        return `ERROR: ${col}:${line} [main.glsl:${original}]:`;
    });
}

function compileShader(gl, type, source, headerLineCount) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        const log = gl.getShaderInfoLog(shader);
        gl.deleteShader(shader);
        const label = type === gl.VERTEX_SHADER ? 'vertex' : 'fragment';
        throw new Error(`${label} shader compile failed:\n${remapLog(log, headerLineCount || 0)}`);
    }
    return shader;
}

export function compileProgram(gl, vertexSource, fragmentSource, headerLineCount) {
    const vs = compileShader(gl, gl.VERTEX_SHADER, vertexSource, 0);
    const fs = compileShader(gl, gl.FRAGMENT_SHADER, fragmentSource, headerLineCount || 0);

    const program = gl.createProgram();
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);
    gl.deleteShader(vs);
    gl.deleteShader(fs);

    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
        const log = gl.getProgramInfoLog(program);
        gl.deleteProgram(program);
        throw new Error(`Program link failed:\n${log}`);
    }
    return program;
}

export function getUniformLocations(gl, program, names) {
    const locations = {};
    for (const name of names) {
        locations[name] = gl.getUniformLocation(program, name);
    }
    return locations;
}
