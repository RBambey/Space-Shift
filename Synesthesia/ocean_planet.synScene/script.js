// Camera position
var camX = 0.0;
var camY = 5.0;
var camZ = 0.0;

// Camera basis vectors in world space (orthonormal)
var camRight = [1, 0, 0];
var camUp    = [0, 1, 0];
var camFwd   = [0, 0, 1];

var rollIdleTime  = 0.0;
var pitchIdleTime = 0.0;
var autoRollActive   = false;
var autoRollProgress = 0.0;
var autoRollDir      = 1.0;
var autoRollDuration = 0.85;
var prevBang         = 0.0;
var recenterActive   = false;
var prevRecenter     = 0.0;

// ---- Math helpers ----

function normalize3(v) {
    var len = Math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
    if (len < 1e-8) return [v[0], v[1], v[2]];
    return [v[0]/len, v[1]/len, v[2]/len];
}

function cross3(a, b) {
    return [
        a[1]*b[2] - a[2]*b[1],
        a[2]*b[0] - a[0]*b[2],
        a[0]*b[1] - a[1]*b[0]
    ];
}

function dot3(a, b) {
    return a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
}

// Rodrigues' rotation: rotate v around unit axis by angle
function rotateAround(v, axis, angle) {
    var c = Math.cos(angle), s = Math.sin(angle);
    var d = dot3(axis, v);
    var cr = cross3(axis, v);
    return [
        v[0]*c + cr[0]*s + axis[0]*d*(1-c),
        v[1]*c + cr[1]*s + axis[1]*d*(1-c),
        v[2]*c + cr[2]*s + axis[2]*d*(1-c)
    ];
}

// Rebuild right and up from fwd, using current up as a reference.
// fwd is authoritative; right and up are recomputed to stay orthonormal.
function reorthogonalize() {
    camFwd   = normalize3(camFwd);
    camRight = normalize3(cross3(camUp, camFwd));
    // Degenerate if fwd is nearly parallel to up — fall back to world Z
    var rLen = camRight[0]*camRight[0] + camRight[1]*camRight[1] + camRight[2]*camRight[2];
    if (rLen < 0.01) {
        camRight = normalize3(cross3([0, 0, 1], camFwd));
    }
    camRight = normalize3(camRight);
    camUp    = normalize3(cross3(camFwd, camRight));
}

// Positive angle = nose up
function applyPitch(angle) {
    camFwd = rotateAround(camFwd, camRight, -angle);
    camUp  = rotateAround(camUp,  camRight, -angle);
}

// Positive angle = bank right (right wing down)
function applyRoll(angle) {
    camRight = rotateAround(camRight, camFwd, -angle);
    camUp    = rotateAround(camUp,    camFwd, -angle);
}

// Rotate all three basis vectors around world up [0,1,0]
function applyWorldYaw(angle) {
    var wu = [0, 1, 0];
    camFwd   = rotateAround(camFwd,   wu, angle);
    camRight = rotateAround(camRight, wu, angle);
    camUp    = rotateAround(camUp,    wu, angle);
}

function pushUniforms() {
    setUniform("cam_x",  camX);
    setUniform("cam_y",  camY);
    setUniform("cam_z",  camZ);
    setUniform("cam_rx", camRight[0]);
    setUniform("cam_ry", camRight[1]);
    setUniform("cam_rz", camRight[2]);
    setUniform("cam_ux", camUp[0]);
    setUniform("cam_uy", camUp[1]);
    setUniform("cam_uz", camUp[2]);
    setUniform("cam_fx", camFwd[0]);
    setUniform("cam_fy", camFwd[1]);
    setUniform("cam_fz", camFwd[2]);
}

function setup() {
    pushUniforms();
}

function update(dt) {

    // ---- Pitch ----
    if (Math.abs(pitch) < 0.05) {
        pitchIdleTime += dt;
    } else {
        pitchIdleTime = 0.0;
    }

    if (!recenterActive) {
        applyPitch(pitch * Math.PI * 1.5 * dt);
        // Clamp to ±80° — prevent looking straight up/down
        if (camFwd[1] > 0.985) {
            camFwd[1] = 0.985;
            reorthogonalize();
        } else if (camFwd[1] < -0.985) {
            camFwd[1] = -0.985;
            reorthogonalize();
        }
    }

    // After 1.5 s idle pitch, pull nose back to level
    if (!recenterActive && pitchIdleTime > 1.5) {
        camFwd[1] += (0.0 - camFwd[1]) * 0.5 * dt;
        reorthogonalize();
    }

    // ---- Recenter ----
    if (recenter > 0.5 && prevRecenter < 0.5) {
        recenterActive = true;
    }
    prevRecenter = recenter;

    if (recenterActive) {
        var pull    = 3.0 * dt;
        var targetY = 5.0;

        // Level pitch and roll, return to cruise altitude
        camFwd[1] += (0.0 - camFwd[1]) * pull;
        camUp[0]  += (0.0 - camUp[0])  * pull;
        camUp[1]  += (1.0 - camUp[1])  * pull;
        camUp[2]  += (0.0 - camUp[2])  * pull;
        reorthogonalize();

        camY += (targetY - camY) * pull;

        if (Math.abs(camFwd[1]) < 0.01 && Math.abs(camUp[1] - 1.0) < 0.01 &&
            Math.abs(camY - targetY) < 0.1) {
            recenterActive = false;
        }
    }

    // ---- Banking yaw + direct yaw ----
    if (!recenterActive) {
        // Derive roll angle from basis so banking works at any orientation
        var rollAngle = Math.atan2(-camRight[1], camUp[1]);
        var yawDelta  = Math.sin(rollAngle) * 0.45 * dt + yaw_rate * Math.PI * dt;
        applyWorldYaw(yawDelta);
    }

    // ---- Roll ----
    if (Math.abs(roll_rate) < 0.05) {
        rollIdleTime += dt;
    } else {
        rollIdleTime = 0.0;
    }

    // Barrel roll on bang rising edge
    if (barrel_roll > 0.5 && prevBang < 0.5 && !autoRollActive) {
        autoRollActive   = true;
        autoRollProgress = 0.0;
        autoRollDir      = Math.random() > 0.5 ? 1.0 : -1.0;
    }
    prevBang = barrel_roll;

    if (autoRollActive) {
        // Sine-eased: integrates to exactly 2π over autoRollDuration
        var angVel = (Math.PI * Math.PI / autoRollDuration) * Math.sin(autoRollProgress * Math.PI);
        applyRoll(angVel * autoRollDir * dt);
        autoRollProgress += dt / autoRollDuration;
        if (autoRollProgress >= 1.0) {
            autoRollActive = false;
        }
    }

    if (!autoRollActive && !recenterActive) {
        applyRoll(roll_rate * Math.PI * 1.5 * dt);
    }

    // After 1.5 s idle roll, gently return to wings-level
    if (!autoRollActive && !recenterActive && rollIdleTime > 1.5) {
        camUp[0] += (0.0 - camUp[0]) * 0.5 * dt;
        camUp[1] += (1.0 - camUp[1]) * 0.5 * dt;
        camUp[2] += (0.0 - camUp[2]) * 0.5 * dt;
        reorthogonalize();
    }

    // ---- Forward movement ----
    camFwd = normalize3(camFwd);
    var speed = fly_speed;
    camX += camFwd[0] * speed * dt;
    camY += camFwd[1] * speed * dt;
    camZ += camFwd[2] * speed * dt;

    // Keep above ocean
    camY = Math.max(2.0, Math.min(camY, 40.0));

    pushUniforms();
}
