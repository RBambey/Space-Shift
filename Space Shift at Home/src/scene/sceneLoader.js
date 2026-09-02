export async function loadScene(sceneDir) {
    const [glsl, sceneJson, script] = await Promise.all([
        fetch(`${sceneDir}/main.glsl`).then(r => r.text()),
        fetch(`${sceneDir}/scene.json`).then(r => r.json()),
        fetch(`${sceneDir}/script.js`).then(r => r.text()),
    ]);
    return { glsl, sceneJson, script };
}
