// Warper — 2D camera physics
// Accumulates roll angle, pitch offset, and yaw offset.
// Pushes warp_roll (radians), warp_pitch (units), warp_yaw (units) to the shader.
// fly_speed is read directly by the shader — no position tracking needed.

var warpRoll  = 0.0;
var warpPitch = 0.0;
var warpYaw   = 0.0;

var rollIdleTime  = 0.0;
var pitchIdleTime = 0.0;
var yawIdleTime   = 0.0;

var autoRollActive   = false;
var autoRollProgress = 0.0;
var autoRollDir      = 1.0;
var autoRollDuration = 0.85;
var prevBang         = 0.0;

var recenterActive = false;
var prevRecenter   = 0.0;

function setup() {
    setUniform("warp_roll",  0.0);
    setUniform("warp_pitch", 0.0);
    setUniform("warp_yaw",   0.0);
}

function update(dt) {
    var pr   = pitch       || 0.0;
    var rr   = roll_rate   || 0.0;
    var yr   = yaw_rate    || 0.0;
    var bang = barrel_roll || 0.0;
    var rc   = recenter    || 0.0;

    // ---- Recenter ----
    if (rc > 0.5 && prevRecenter < 0.5) recenterActive = true;
    prevRecenter = rc;

    if (recenterActive) {
        var pull = 4.0 * dt;
        warpRoll  += (0.0 - warpRoll)  * pull;
        warpPitch += (0.0 - warpPitch) * pull;
        warpYaw   += (0.0 - warpYaw)   * pull;
        if (Math.abs(warpRoll)  < 0.005 &&
            Math.abs(warpPitch) < 0.005 &&
            Math.abs(warpYaw)   < 0.005) {
            warpRoll = warpPitch = warpYaw = 0.0;
            recenterActive = false;
        }
    } else {

        // ---- Pitch ----
        pitchIdleTime = Math.abs(pr) < 0.05 ? pitchIdleTime + dt : 0.0;
        warpPitch += pr * 1.2 * dt;
        warpPitch = Math.max(-1.0, Math.min(1.0, warpPitch));
        if (pitchIdleTime > 1.5) warpPitch += (0.0 - warpPitch) * 0.5 * dt;

        // ---- Yaw ----
        yawIdleTime = Math.abs(yr) < 0.05 ? yawIdleTime + dt : 0.0;
        warpYaw += yr * 1.2 * dt;
        warpYaw = Math.max(-1.0, Math.min(1.0, warpYaw));
        if (yawIdleTime > 1.5) warpYaw += (0.0 - warpYaw) * 0.5 * dt;

        // ---- Roll ----
        rollIdleTime = Math.abs(rr) < 0.05 ? rollIdleTime + dt : 0.0;

        // Barrel roll trigger
        if (bang > 0.5 && prevBang < 0.5 && !autoRollActive) {
            autoRollActive   = true;
            autoRollProgress = 0.0;
            autoRollDir      = Math.random() > 0.5 ? 1.0 : -1.0;
        }
        prevBang = bang;

        if (autoRollActive) {
            var angVel = (Math.PI * Math.PI / autoRollDuration)
                       * Math.sin(autoRollProgress * Math.PI);
            warpRoll += angVel * autoRollDir * dt;
            autoRollProgress += dt / autoRollDuration;
            if (autoRollProgress >= 1.0) autoRollActive = false;
        }

        if (!autoRollActive) {
            warpRoll += rr * Math.PI * 1.5 * dt;
            if (rollIdleTime > 1.5) warpRoll += (0.0 - warpRoll) * 0.5 * dt;
        }
    }

    setUniform("warp_roll",  warpRoll);
    setUniform("warp_pitch", warpPitch);
    setUniform("warp_yaw",   warpYaw);
}
