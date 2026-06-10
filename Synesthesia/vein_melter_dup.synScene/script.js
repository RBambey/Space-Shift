// Vein Melter Dup — Wormhole Tunnel Flying
// Accumulates roll angle, pitch offset, and yaw offset.
// Pushes warp_roll (radians), warp_pitch (units), warp_yaw (units) to the shader.
// fly_speed is read directly by the shader — no position tracking needed.

var warpRoll  = 0.0;
var warpPitch = 0.0;
var warpYaw   = 0.0;
var warpTime  = 0.0;  // smooth integrated travel time — avoids TIME * speed jump/precision issues
var beatAccum = 0.0;  // beat_time for simulation heartbeat (used in renderPassA)

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
    setUniform("warp_time",  0.0);
    setUniform("beat_time",  0.0);
}

function update(dt) {
    var pr   = pitch       || 0.0;
    var rr   = roll_rate   || 0.0;
    var yr   = yaw_rate    || 0.0;
    var bang = barrel_roll || 0.0;
    var rc   = recenter    || 0.0;

    // ---- Travel time (integrated — smooth speed ramp, no TIME precision issues) ----
    warpTime = (warpTime + (fly_speed || 0.0) * dt) % 100.0;
    setUniform("warp_time", warpTime);

    // ---- beat_time for simulation heartbeat ----
    beatAccum = (beatAccum + dt * 0.5) % 1000.0;
    setUniform("beat_time", beatAccum);

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
        warpPitch += pr * 3.0 * dt;
        warpPitch = Math.max(-1.0, Math.min(1.0, warpPitch));
        if (pitchIdleTime > 0.6) warpPitch += (0.0 - warpPitch) * 2.5 * dt;

        // ---- Yaw ----
        yawIdleTime = Math.abs(yr) < 0.05 ? yawIdleTime + dt : 0.0;
        warpYaw += yr * 3.0 * dt;
        warpYaw = Math.max(-1.0, Math.min(1.0, warpYaw));
        if (yawIdleTime > 0.6) warpYaw += (0.0 - warpYaw) * 2.5 * dt;

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
            warpRoll -= rr * Math.PI * 1.5 * dt;
            // No auto-level for roll — view holds at current angle when control is released
        }
    }

    setUniform("warp_roll",  warpRoll);
    setUniform("warp_pitch", warpPitch);
    setUniform("warp_yaw",   warpYaw);
}
