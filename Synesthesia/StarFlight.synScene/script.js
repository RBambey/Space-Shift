// Star Flight — Flight physics
// Adapted from Flying Synth by RBambey
// No terrain — open space in all directions.

var camX = 0.0;
var camY = 0.0;
var camZ = 0.0;
var camRoll  = 0.0;
var camPitch = 0.0;
var camYaw   = 0.0;

var rollIdleTime  = 0.0;
var pitchIdleTime = 0.0;

var autoRollActive   = false;
var autoRollProgress = 0.0;
var autoRollDir      = 1.0;
var autoRollDuration = 0.85;
var prevBang         = 0.0;

var recenterActive = false;
var prevRecenter   = 0.0;

function setup() {
    setUniform("cam_x",         camX);
    setUniform("cam_y",         camY);
    setUniform("cam_z",         camZ);
    setUniform("cam_roll",      camRoll);
    setUniform("cam_pitch",     camPitch);
    setUniform("cam_yaw",       camYaw);
}

function update(dt) {
    var pitchRate = -pitch_roll.y * Math.PI * 1.5;
    var rollRate  =  pitch_roll.x * Math.PI * 1.5;

    // Track pitch idle time
    if (Math.abs(pitch_roll.y) < 0.05) {
        pitchIdleTime += dt;
    } else {
        pitchIdleTime = 0.0;
    }

    if (!recenterActive) {
        camPitch += pitchRate * dt;
        camPitch = Math.max(-Math.PI * 0.45, Math.min(Math.PI * 0.45, camPitch));
    }

    // After 1.5 s of no pitch input, gently pull back to level
    if (!recenterActive && pitchIdleTime > 1.5) {
        camPitch += (0.0 - camPitch) * 0.5 * dt;
    }

    // Recenter — resets orientation only (position makes no sense to reset in open space)
    if (recenter > 0.5 && prevRecenter < 0.5) {
        recenterActive = true;
    }
    prevRecenter = recenter;

    if (recenterActive) {
        var pull = 3.0 * dt;
        camRoll  += (0.0 - camRoll)  * pull;
        camPitch += (0.0 - camPitch) * pull;
        camYaw   += (0.0 - camYaw)   * pull;
        if (Math.abs(camRoll) < 0.01 && Math.abs(camPitch) < 0.01 && Math.abs(camYaw) < 0.01) {
            camRoll = 0.0; camPitch = 0.0; camYaw = 0.0;
            recenterActive = false;
        }
    }

    // Banking induces a natural yaw turn
    if (!recenterActive) {
        camYaw += Math.sin(camRoll) * 0.45 * dt;
    }

    // Track roll idle time
    if (Math.abs(pitch_roll.x) < 0.05) {
        rollIdleTime += dt;
    } else {
        rollIdleTime = 0.0;
    }

    // Barrel roll — fires on bang rising edge
    if (barrel_roll > 0.5 && prevBang < 0.5 && !autoRollActive) {
        autoRollActive   = true;
        autoRollProgress = 0.0;
        autoRollDir      = Math.random() > 0.5 ? 1.0 : -1.0;
    }
    prevBang = barrel_roll;

    if (autoRollActive) {
        var angVel = (Math.PI * Math.PI / autoRollDuration) * Math.sin(autoRollProgress * Math.PI);
        camRoll += angVel * autoRollDir * dt;
        autoRollProgress += dt / autoRollDuration;
        if (autoRollProgress >= 1.0) {
            autoRollActive = false;
        }
    }

    // Apply roll input (suppressed during auto-roll or recenter)
    if (!autoRollActive && !recenterActive) {
        camRoll += rollRate * dt;
    }

    // After 1.5 s of no roll input, drift back to nearest full rotation
    if (!autoRollActive && !recenterActive && rollIdleTime > 1.5) {
        var twoPi   = Math.PI * 2.0;
        var nearest = Math.round(camRoll / twoPi) * twoPi;
        camRoll += (nearest - camRoll) * 0.5 * dt;
    }

    // Compute forward vector from orientation (roll + pitch + yaw)
    var cr = Math.cos(camRoll),  sr = Math.sin(camRoll);
    var cp = Math.cos(camPitch), sp = Math.sin(camPitch);
    var cy = Math.cos(camYaw),   sy = Math.sin(camYaw);

    // Forward in camera space (before yaw), then apply yaw rotation
    var fx =  sp * sr;
    var fy =  sp * cr;
    var fz =  cp;

    var fwdX =  fx * cy + fz * sy;
    var fwdY =  fy;
    var fwdZ = -fx * sy + fz * cy;

    // Always maintain a minimum crawl so the scene stays alive at speed=0
    var speed = Math.max(1.5, fly_speed);
    camX += fwdX * speed * dt;
    camY += fwdY * speed * dt;
    camZ += fwdZ * speed * dt;

    setUniform("cam_x",     camX);
    setUniform("cam_y",     camY);
    setUniform("cam_z",     camZ);
    setUniform("cam_roll",  camRoll);
    setUniform("cam_pitch", camPitch);
    setUniform("cam_yaw",   camYaw);
}
