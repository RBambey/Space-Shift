var camX = 0.0;
var camY = 3.0;
var camZ = 0.0;
var camRoll = 0.0;
var camPitch = 0.0;
var camYaw = 0.0;
var rollIdleTime = 0.0;   // how long roll input has been near zero
var pitchIdleTime = 0.0;  // how long pitch input has been near zero
var autoRollActive   = false;
var autoRollProgress = 0.0;  // 0 to 1 through the roll
var autoRollDir      = 1.0;  // +1 or -1
var autoRollDuration = 0.85; // seconds for a full rotation
var prevBang         = 0.0;
var recenterActive   = false;
var prevRecenter     = 0.0;
var skyTimeAcc       = 0.0;
var hyperZ           = 0.0;  // always-forward distance for hyperspace tunnel
var wavePhase        = 0.0;  // shockwave position (0-1 maps near→far)

function terrain(x, z) {
    // Space (0) — placeholder flat
    if (terrain_type < 0.5) return 0.0;

    // Planet (1) — triangle wave mountains, horizon-locked
    if (terrain_type < 1.5) {
        var t1 = Math.max(0.0, triWave(x * 0.04  + z * 0.009) - 0.25) * 7.0;
        var t2 = Math.max(0.0, triWave(x * 0.08  - z * 0.018) - 0.35) * 4.0;
        var t3 = Math.max(0.0, triWave(x * 0.14  + z * 0.060) - 0.50) * 2.0;

        var dx = x - camX;
        var dz = z - camZ;
        var distFromCam = Math.sqrt(dx * dx + dz * dz);
        var rise = smoothstep(8.0, 55.0, distFromCam);

        var floor = Math.sin(x * 0.8 + z * 0.6) * 0.4
                  + Math.sin(x * 1.3 - z * 0.9) * 0.2;

        return (t1 + t2 + t3) * mountain_height * rise + floor;
    }

    // Hyperspace (2) — placeholder flat
    return 0.0;
}

function fract(x) { return x - Math.floor(x); }

function triWave(x) {
    var f = x - Math.floor(x);
    return 1.0 - Math.abs(f * 2.0 - 1.0);
}

function smoothstep(edge0, edge1, x) {
    var t = Math.max(0.0, Math.min(1.0, (x - edge0) / (edge1 - edge0)));
    return t * t * (3.0 - 2.0 * t);
}

function setup() {
    setUniform("cam_x", camX);
    setUniform("cam_y", camY);
    setUniform("cam_z", camZ);
    setUniform("cam_roll_angle", camRoll);
    setUniform("cam_pitch_angle", camPitch);
}

function update(dt) {
    var pitchRate = -pitch_roll.y * Math.PI * 1.5;
    var rollRate  =  pitch_roll.x * Math.PI * 1.5;

    // Track how long pitch input has been idle
    if (Math.abs(pitch_roll.y) < 0.05) {
        pitchIdleTime += dt;
    } else {
        pitchIdleTime = 0.0;
    }

    if (!recenterActive) {
        camPitch += pitchRate * dt;
        camPitch = Math.max(-Math.PI * 0.45, Math.min(Math.PI * 0.45, camPitch));
    }

    // After 1.5 seconds of no pitch input, pull back to level
    if (!recenterActive && pitchIdleTime > 1.5) {
        var returnStrength = 0.5;
        camPitch += (0.0 - camPitch) * returnStrength * dt;
    }

    // Recenter — smoothly pulls orientation and x position back to neutral
    if (recenter > 0.5 && prevRecenter < 0.5) {
        recenterActive = true;
    }
    prevRecenter = recenter;

    if (recenterActive) {
        var pull      = 3.0 * dt;
        var targetY   = terrain(camX, camZ) + 4.0;
        camRoll  += (0.0     - camRoll)  * pull;
        camPitch += (0.0     - camPitch) * pull;
        camYaw   += (0.0     - camYaw)   * pull;
        camX     += (0.0     - camX)     * pull;
        camY     += (targetY - camY)     * pull;
        if (Math.abs(camRoll) < 0.01 && Math.abs(camPitch) < 0.01 &&
            Math.abs(camYaw)  < 0.01 && Math.abs(camX)     < 0.1 &&
            Math.abs(camY - targetY) < 0.1) {
            camRoll = 0.0; camPitch = 0.0; camYaw = 0.0;
            recenterActive = false;
        }
    }

    // Banking causes a gradual turn in the direction of roll
    if (!recenterActive) {
        camYaw += Math.sin(camRoll) * 0.45 * dt;
    }

    var speed = fly_speed;

    // Track how long roll input has been idle
    if (Math.abs(pitch_roll.x) < 0.05) {
        rollIdleTime += dt;
    } else {
        rollIdleTime = 0.0;
    }

    // Triggered barrel roll — fires on bang rising edge
    if (barrel_roll > 0.5 && prevBang < 0.5 && !autoRollActive) {
        autoRollActive   = true;
        autoRollProgress = 0.0;
        autoRollDir      = Math.random() > 0.5 ? 1.0 : -1.0;
    }
    prevBang = barrel_roll;

    if (autoRollActive) {
        // Sine easing: slow at start and end, fast in the middle
        // Integrates to exactly 2*PI over the duration
        var angVel = (Math.PI * Math.PI / autoRollDuration) * Math.sin(autoRollProgress * Math.PI);
        camRoll += angVel * autoRollDir * dt;
        autoRollProgress += dt / autoRollDuration;
        if (autoRollProgress >= 1.0) {
            autoRollActive = false;
        }
    }

    // Accumulate roll from input (suppressed during auto-roll or recenter)
    if (!autoRollActive && !recenterActive) {
        camRoll += rollRate * dt;
    }

    // After 1.5 seconds of no roll input, start pulling back to level
    if (!autoRollActive && !recenterActive && rollIdleTime > 1.5) {
        var twoPi = Math.PI * 2.0;
        var nearest = Math.round(camRoll / twoPi) * twoPi;
        var returnStrength = .5;
        camRoll += (nearest - camRoll) * returnStrength * dt;
    }

    var cr = Math.cos(camRoll),  sr = Math.sin(camRoll);
    var cp = Math.cos(camPitch), sp = Math.sin(camPitch);
    var cy = Math.cos(camYaw),   sy = Math.sin(camYaw);

    var fx =  sp * sr;
    var fy =  sp * cr;
    var fz =  cp;

    var fwdX =  fx * cy + fz * sy;
    var fwdY =  fy;
    var fwdZ = -fx * sy + fz * cy;

    camX += fwdX * speed * dt;
    camY += fwdY * speed * dt;
    camZ += fwdZ * speed * dt;

    var groundHeight = terrain(camX, camZ);
    camY = Math.max(groundHeight + 1.0, Math.min(camY, 20.0));

    setUniform("cam_x", camX);
    setUniform("cam_y", camY);
    setUniform("cam_z", camZ);
    setUniform("cam_roll_angle", camRoll);
    setUniform("cam_pitch_angle", camPitch);
    setUniform("cam_yaw_angle", camYaw);

    hyperZ += speed * dt;
    setUniform("hyper_z", hyperZ);

    wavePhase += syn_BassLevel * 1.5 * dt;  // bass drives wave forward
    setUniform("wave_phase", wavePhase);

    // Sky auto-cycle — 2-minute cosine loop (night → sunset → day → sunset → night)
    if (sky_auto > 0.5) {
        skyTimeAcc += dt;
        var autoSkyTime = Math.cos(skyTimeAcc / 120.0 * Math.PI * 2.0) * 0.5 + 0.5;
        setUniform("sky_time_eff", autoSkyTime);
    } else {
        skyTimeAcc = 0.0;  // reset so next auto-enable starts fresh
        setUniform("sky_time_eff", sky_time);  // pass knob value through to shader
    }
}
