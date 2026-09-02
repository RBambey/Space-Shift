// A raw keyboard axis is just -1/0/1 the instant a key is pressed - jerky
// compared to an analog stick. This ramps toward the held direction along a
// smoothstep ease (slow-in, so a light tap gives fine control, full
// deflection only after holding briefly) and eases back to 0 on release,
// always staying within the scene's declared -1..1 range rather than
// overshooting it.
function createAxisRamp(rampUpSeconds, rampDownTau) {
    let value = 0;
    let heldTime = 0;

    return function update(dt, target) {
        if (target !== 0) {
            heldTime = Math.min(heldTime + dt, rampUpSeconds);
            const t = heldTime / rampUpSeconds;
            const eased = t * t * (3 - 2 * t);
            value = target * eased;
        } else {
            heldTime = 0;
            value += (0 - value) * (1 - Math.exp(-dt / rampDownTau));
        }
        return value;
    };
}

// Keyboard -> the same named controls a joystick/OSC input would drive.
// Writes directly into controlsRuntime; the scene's own script.js (run via
// scriptHost) does all the actual camera math, exactly as it would with any
// other input source.
export function createKeyboardInput(controlsRuntime, controls) {
    const flySpeedControl = controls.find(c => c.NAME === 'fly_speed');
    const speedMin = flySpeedControl ? flySpeedControl.MIN : 1;
    const speedMax = flySpeedControl ? flySpeedControl.MAX : 50;

    const held = new Set();
    let flySpeed = flySpeedControl ? flySpeedControl.DEFAULT : (speedMin + speedMax) / 2;
    let barrelRollPulse = false;
    let recenterPulse = false;

    const pitchRamp = createAxisRamp(0.3, 0.15);
    const yawRamp = createAxisRamp(0.3, 0.15);
    const rollRamp = createAxisRamp(0.3, 0.15);
    const PITCH_SENSITIVITY = 0.5;

    function onKeyDown(e) {
        if (e.repeat) return;
        held.add(e.code);
        if (e.code === 'KeyF') barrelRollPulse = true;
        if (e.code === 'KeyR') recenterPulse = true;
    }
    function onKeyUp(e) {
        held.delete(e.code);
    }
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);

    function axis(negCodes, posCodes) {
        const neg = negCodes.some(c => held.has(c));
        const pos = posCodes.some(c => held.has(c));
        return (pos ? 1 : 0) - (neg ? 1 : 0);
    }

    function update(dt) {
        const pitchTarget = axis(['KeyW', 'ArrowUp'], ['KeyS', 'ArrowDown']); // inverted
        const yawTarget = axis(['ArrowLeft'], ['ArrowRight']);
        const rollTarget = axis(['KeyA'], ['KeyD']);

        const pitch = pitchRamp(dt, pitchTarget) * PITCH_SENSITIVITY;
        const yawRate = yawRamp(dt, yawTarget);
        const rollRate = rollRamp(dt, rollTarget);

        const speedRate = (speedMax - speedMin) * 0.6;
        if (held.has('ShiftLeft') || held.has('ShiftRight')) flySpeed += speedRate * dt;
        if (held.has('ControlLeft') || held.has('ControlRight')) flySpeed -= speedRate * dt;
        flySpeed = Math.min(speedMax, Math.max(speedMin, flySpeed));

        controlsRuntime.set('pitch', pitch);
        controlsRuntime.set('yaw_rate', yawRate);
        controlsRuntime.set('roll_rate', rollRate);
        controlsRuntime.set('fly_speed', flySpeed);
        controlsRuntime.set('barrel_roll', barrelRollPulse ? 1 : 0);
        controlsRuntime.set('recenter', recenterPulse ? 1 : 0);

        barrelRollPulse = false;
        recenterPulse = false;
    }

    function dispose() {
        window.removeEventListener('keydown', onKeyDown);
        window.removeEventListener('keyup', onKeyUp);
    }

    return { update, dispose };
}
