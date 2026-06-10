// Wireframe — Canyon flight physics  v2.0
// Camera module copied from Ocean Planet (RBambey).

var cam = (function(opts) {
    opts = opts || {};

    var camX  = opts.startX != null ? opts.startX : 0.0;
    var camY  = opts.startY != null ? opts.startY : 5.0;
    var camZ  = opts.startZ != null ? opts.startZ : 0.0;
    var snapX = opts.snapXOnRecenter || false;

    var camRight = [1, 0, 0];
    var camUp    = [0, 1, 0];
    var camFwd   = [0, 0, 1];

    var rollIdleTime     = 0.0;
    var pitchIdleTime    = 0.0;
    var autoRollActive   = false;
    var autoRollProgress = 0.0;
    var autoRollDir      = 1.0;
    var autoRollDuration = 0.85;
    var prevBang         = 0.0;
    var recenterActive   = false;
    var prevRecenter     = 0.0;

    function normalize3(v) {
        var len = Math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
        if (len < 1e-8) return [v[0], v[1], v[2]];
        return [v[0]/len, v[1]/len, v[2]/len];
    }

    function cross3(a, b) {
        return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];
    }

    function dot3(a, b) {
        return a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
    }

    function rotateAround(v, axis, angle) {
        var c = Math.cos(angle), s = Math.sin(angle);
        var d = dot3(axis, v);
        var cr = cross3(axis, v);
        return [v[0]*c+cr[0]*s+axis[0]*d*(1-c),
                v[1]*c+cr[1]*s+axis[1]*d*(1-c),
                v[2]*c+cr[2]*s+axis[2]*d*(1-c)];
    }

    function reorthogonalize() {
        camFwd   = normalize3(camFwd);
        camRight = normalize3(cross3(camUp, camFwd));
        var rLen = camRight[0]*camRight[0] + camRight[1]*camRight[1] + camRight[2]*camRight[2];
        if (rLen < 0.01) camRight = normalize3(cross3([0, 0, 1], camFwd));
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
        setUniform("cam_x",  camX);  setUniform("cam_y",  camY);  setUniform("cam_z",  camZ);
        setUniform("cam_rx", camRight[0]); setUniform("cam_ry", camRight[1]); setUniform("cam_rz", camRight[2]);
        setUniform("cam_ux", camUp[0]);    setUniform("cam_uy", camUp[1]);    setUniform("cam_uz", camUp[2]);
        setUniform("cam_fx", camFwd[0]);   setUniform("cam_fy", camFwd[1]);   setUniform("cam_fz", camFwd[2]);
    }

    function setup() { pushUniforms(); }

    function update(dt, controls, callbacks) {
        controls  = controls  || {};
        callbacks = callbacks || {};

        var pitch       = controls.pitch       || 0.0;
        var roll_rate   = controls.roll_rate   || 0.0;
        var yaw_rate    = controls.yaw_rate    || 0.0;
        var barrel_roll = controls.barrel_roll || 0.0;
        var fly_speed   = controls.fly_speed   || 0.0;
        var recenter    = controls.recenter    || 0.0;

        // Pitch
        if (Math.abs(pitch) < 0.05) { pitchIdleTime += dt; } else { pitchIdleTime = 0.0; }
        if (!recenterActive) {
            applyPitch(pitch * Math.PI * 1.5 * dt);
            if      (camFwd[1] >  0.985) { camFwd[1] =  0.985; reorthogonalize(); }
            else if (camFwd[1] < -0.985) { camFwd[1] = -0.985; reorthogonalize(); }
        }
        if (!recenterActive && pitchIdleTime > 1.5) {
            camFwd[1] += (0.0 - camFwd[1]) * 0.5 * dt;
            reorthogonalize();
        }

        // Recenter
        if (recenter > 0.5 && prevRecenter < 0.5) recenterActive = true;
        prevRecenter = recenter;
        if (recenterActive) {
            var pull    = 3.0 * dt;
            var targetY = callbacks.recenterY ? callbacks.recenterY(camX, camZ) : null;
            camFwd[1] += (0.0 - camFwd[1]) * pull;
            camUp[0]  += (0.0 - camUp[0])  * pull;
            camUp[1]  += (1.0 - camUp[1])  * pull;
            camUp[2]  += (0.0 - camUp[2])  * pull;
            reorthogonalize();
            if (snapX)           camX += (0.0 - camX) * pull;
            if (targetY != null) camY += (targetY - camY) * pull;
            var doneOri = Math.abs(camFwd[1]) < 0.01 && Math.abs(camUp[1] - 1.0) < 0.01;
            var doneX   = !snapX || Math.abs(camX) < 0.1;
            var doneY   = targetY == null || Math.abs(camY - targetY) < 0.1;
            if (doneOri && doneX && doneY) recenterActive = false;
        }

        // Banking yaw + direct yaw
        if (!recenterActive) {
            var rollAngle = Math.atan2(-camRight[1], camUp[1]);
            applyWorldYaw(Math.sin(rollAngle) * 0.45 * dt + yaw_rate * Math.PI * dt);
        }

        // Roll
        if (Math.abs(roll_rate) < 0.05) { rollIdleTime += dt; } else { rollIdleTime = 0.0; }
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
            if (autoRollProgress >= 1.0) autoRollActive = false;
        }
        if (!autoRollActive && !recenterActive) applyRoll(roll_rate * Math.PI * 1.5 * dt);
        if (!autoRollActive && !recenterActive && rollIdleTime > 1.5) {
            camUp[0] += (0.0 - camUp[0]) * 0.5 * dt;
            camUp[1] += (1.0 - camUp[1]) * 0.5 * dt;
            camUp[2] += (0.0 - camUp[2]) * 0.5 * dt;
            reorthogonalize();
        }

        // Forward movement
        camFwd = normalize3(camFwd);
        camX += camFwd[0] * fly_speed * dt;
        camY += camFwd[1] * fly_speed * dt;
        camZ += camFwd[2] * fly_speed * dt;

        var altMin = callbacks.altMin ? callbacks.altMin(camX, camZ) : -Infinity;
        var altMax = callbacks.altMax ? callbacks.altMax(camX, camZ) :  Infinity;
        camY = Math.max(altMin, Math.min(camY, altMax));

        // X wall collision with sliding — mirrors altMin/altMax pattern.
        // Stop penetration, then project camFwd off the wall so we slide along it.
        var wallL = callbacks.wallLeft  ? callbacks.wallLeft(camX,  camZ) : -Infinity;
        var wallR = callbacks.wallRight ? callbacks.wallRight(camX,  camZ) :  Infinity;
        if (camX < wallL) {
            camX = wallL;
            if (camFwd[0] < 0) { camFwd[0] = 0; camFwd = normalize3(camFwd); reorthogonalize(); }
        }
        if (camX > wallR) {
            camX = wallR;
            if (camFwd[0] > 0) { camFwd[0] = 0; camFwd = normalize3(camFwd); reorthogonalize(); }
        }

        pushUniforms();
        if (callbacks.afterUpdate) callbacks.afterUpdate();
    }

    function getPos() { return { x: camX, y: camY, z: camZ }; }

    return { setup: setup, update: update, getPos: getPos, pushUniforms: pushUniforms };
})({ startY: 5.0 });

// Canyon floor height — mirrors floorHeight() in main.glsl exactly.
// Used by altMin/altMax to keep camera above terrain.
function floorHeight(x, z) {
    return Math.sin(x * 0.08 + z * 0.05)         * 2.5
         + Math.sin(x * 0.17 + z * 0.12 + 1.7)   * 1.5
         + Math.cos(x * 0.29 + z * 0.21 + 3.1)   * 0.7;
}

// Canyon path center X — mirrors path() in main.glsl exactly.
// amp = canyon_width/200 keeps turns proportional to width at all settings.
function pathCenter(z) {
    var s   = 0.018;
    var amp = canyon_width / 200.0;
    return (Math.sin(z * s)        * 30.0 +
            Math.sin(z * s * 1.37) * 18.0 +
            Math.sin(z * s * 2.61) *  8.0 +
            Math.sin(z * s * 4.07) *  3.0) * amp;
}

// Canyon half-width — mirrors halfWidth() in main.glsl exactly.
function halfWidthJS(z) {
    return canyon_width * 0.5 *
        (1.0 + 0.12 * Math.sin(z * 0.031) + 0.08 * Math.cos(z * 0.057 + 2.0));
}

// Wall protrusion margin — mirrors wallVar() max amplitude in main.glsl.
// Scales with sqrt(canyon_width/60) exactly as the GLSL does, so the
// collision boundary stays just outside the actual bumpy wall surface.
function wallMargin() {
    return Math.sqrt(canyon_width / 60.0) * 2.65 + 1.0;
}

function setup() {
    cam.setup();
}

function update(dt) {
    cam.update(dt,
        { pitch: pitch, roll_rate: roll_rate, yaw_rate: yaw_rate,
          barrel_roll: barrel_roll, fly_speed: fly_speed, recenter: recenter },
        { recenterY:  function(x, z) { return floorHeight(x, z) + wall_height + 5.0; },
          altMin:     function(x, z) {
              // Inside canyon: hover above floor. Outside: hover above exterior plateau.
              var inCanyon = Math.abs(x - pathCenter(z)) < halfWidthJS(z) - wallMargin();
              return inCanyon ? floorHeight(x, z) + 1.5
                              : floorHeight(x, z) + wall_height + 1.0;
          },
          altMax:     function(x, z) { return floorHeight(x, z) + wall_height + 200.0; } }
    );
}
