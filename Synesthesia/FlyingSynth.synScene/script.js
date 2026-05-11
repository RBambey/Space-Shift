var camX = 0.0;
var camY = 3.0;
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

// ---- Terrain helpers ----

function canyonPath(z) {
    return Math.sin(z * 0.06) * 8.0 + Math.sin(z * 0.11 + 1.2) * 4.0 + Math.sin(z * 0.17 - 0.5) * 2.0;
}

function terrain(x, z) {
    // Mountains (0)
    if (terrain_type < 0.5) {
        var h = 0.0;
        h += Math.sin(x * 0.15 + Math.sin(z * 0.12) * 2.0) * 8.0;
        h += Math.sin(x * 0.31 - z * 0.27) * 5.0;
        h += Math.sin(x * 0.53 + z * 0.41) * 2.5;
        h += Math.sin(x * 1.10 - z * 0.87) * 1.0;
        return h;
    }
    // Flat (1)
    if (terrain_type < 1.5) return 0.0;
    // Canyon (2)
    if (terrain_type < 2.5) {
        var px   = canyonPath(z);
        var dist = Math.abs(x - px);
        return 2.0 + smoothstep(8.0, 24.0, dist) * 26.0;
    }
    // Trench Run (3) — straight trench centered on x=0, Death Star surface outside
    var trenchDist = Math.abs(x);

    // Wall protrusions — blocky sections that narrow the trench every ~8 units along z
    var wCell    = Math.floor(z / 8.0);
    var wHash    = fract(Math.sin(wCell * 311.7) * 43758.5453);
    var wallProtr = Math.floor(wHash * 3.0) * 1.2;
    var effWidth  = 7.0 - wallProtr;
    var inTrench  = 1.0 - smoothstep(effWidth, effWidth + 1.5, trenchDist);

    // Raised floor blocks — varied heights, kept away from trench center
    var fCellX   = Math.floor(x / 4.0);
    var fCellZ   = Math.floor(z / 4.0);
    var fHash    = fract(Math.sin(fCellX * 127.1 + fCellZ * 311.7) * 43758.5453);
    var fHash2   = fract(Math.sin(fCellX * 269.5 + fCellZ * 183.3) * 43758.5453);
    var blockH   = (Math.floor(fHash2 * 5.0) + 1.0) * 0.55;
    var centerFade = smoothstep(2.0, 4.5, trenchDist);
    var floorBlock = (fHash > 0.65 ? blockH : 0.0) * centerFade * inTrench;

    // Outer surface stepped panels
    var pCellX   = Math.floor(x / 6.0);
    var pCellZ   = Math.floor(z / 6.0);
    var pHash    = fract(Math.sin(pCellX * 127.1 + pCellZ * 311.7) * 43758.5453);
    var panel    = Math.floor(pHash * 4.0) * 0.6;

    return inTrench * floorBlock + (1.0 - inTrench) * (14.0 + panel);
}

function fract(x) { return x - Math.floor(x); }

function smoothstep(edge0, edge1, x) {
    var t = Math.max(0.0, Math.min(1.0, (x - edge0) / (edge1 - edge0)));
    return t * t * (3.0 - 2.0 * t);
}

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

// Rebuild right and up from fwd; falls back to world Z if degenerate
function reorthogonalize() {
    camFwd   = normalize3(camFwd);
    camRight = normalize3(cross3(camUp, camFwd));
    var rLen = camRight[0]*camRight[0] + camRight[1]*camRight[1] + camRight[2]*camRight[2];
    if (rLen < 0.01) {
        camRight = normalize3(cross3([0, 0, 1], camFwd));
    }
    camRight = normalize3(camRight);
    camUp    = normalize3(cross3(camFwd, camRight));
}

function applyPitch(angle) {
    camFwd = rotateAround(camFwd, camRight, -angle);
    camUp  = rotateAround(camUp,  camRight, -angle);
}

function applyRoll(angle) {
    camRight = rotateAround(camRight, camFwd, -angle);
    camUp    = rotateAround(camUp,    camFwd, -angle);
}

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

    // ---- Recenter — pulls orientation, x position, and altitude back to neutral ----
    if (recenter > 0.5 && prevRecenter < 0.5) {
        recenterActive = true;
    }
    prevRecenter = recenter;

    if (recenterActive) {
        var pull    = 3.0 * dt;
        var targetY = terrain(camX, camZ) + 4.0;

        camFwd[1] += (0.0 - camFwd[1]) * pull;
        camUp[0]  += (0.0 - camUp[0])  * pull;
        camUp[1]  += (1.0 - camUp[1])  * pull;
        camUp[2]  += (0.0 - camUp[2])  * pull;
        reorthogonalize();

        camX += (0.0     - camX) * pull;
        camY += (targetY - camY) * pull;

        if (Math.abs(camFwd[1]) < 0.01 && Math.abs(camUp[1] - 1.0) < 0.01 &&
            Math.abs(camX) < 0.1 && Math.abs(camY - targetY) < 0.1) {
            recenterActive = false;
        }
    }

    // ---- Banking yaw + direct rudder yaw ----
    if (!recenterActive) {
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

    var groundHeight = terrain(camX, camZ);
    camY = Math.max(groundHeight + 1.0, Math.min(camY, 20.0));

    pushUniforms();
}
