// Camera position
var camX = 0.0;
var camY = 4.0;
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

// --- Math helpers ---

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

// Rebuild right and up from fwd, keeping vectors orthonormal
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

// Positive angle = nose up
function applyPitch(angle) {
  camFwd = rotateAround(camFwd, camRight, -angle);
  camUp  = rotateAround(camUp,  camRight, -angle);
}

// Positive angle = bank right
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

// --- Utility ---

function fract(x) {
  return x - Math.floor(x);
}

function clamp(x, min, max) {
  return Math.min(Math.max(x, min), max);
}

function mix(a, b, t) {
  return a * (1.0 - t) + b * t;
}

function setHSVColor(uniformName, hue, sat, val) {
  const px = Math.abs(fract(hue + 1  ) * 6 - 3);
  const py = Math.abs(fract(hue + 2/3) * 6 - 3);
  const pz = Math.abs(fract(hue + 1/3) * 6 - 3);
  setUniform(
    uniformName,
    val * mix(1, clamp(px - 1, 0, 1), sat),
    val * mix(1, clamp(py - 1, 0, 1), sat),
    val * mix(1, clamp(pz - 1, 0, 1), sat)
  );
}

function setNormalizedVec3(uniformName, x, y, z) {
  const il = 1 / Math.sqrt(x*x + y*y + z*z);
  setUniform(uniformName, x*il, y*il, z*il);
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

// --- Init ---

function setup() {
  pushUniforms();
}

// --- Per-frame ---

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
    var targetY = min_height + 2.0;

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
  camX += camFwd[0] * fly_speed * dt;
  camY += camFwd[1] * fly_speed * dt;
  camZ += camFwd[2] * fly_speed * dt;

  // Clamp between floor and ceiling
  camY = Math.max(min_height, Math.min(camY, max_height));

  pushUniforms();

  // --- Color uniforms (from Entombed Silicon Dreams) ---

  const OFF = base_hue;
  setUniform("OFF", OFF);
  setHSVColor("BY", 0.05+OFF, 0.7, 0.8);
  setHSVColor("BG", 0.95+OFF, 0.6, 0.3);
  setHSVColor("BW", 0.55+OFF, 0.2, 2.0);
  setHSVColor("BF", 0.82+OFF, 0.6, 2.0);
  setHSVColor("FC", 1.0-color_burn_hue, color_burn_saturation, color_burn_intensity);
  setNormalizedVec3("RN", ring_direction.x, 1, ring_direction.y);
  setNormalizedVec3("LD", 1, light_direction.y, light_direction.x);
  setUniform("GG", gas_giant_position.x, gas_giant_position.y, 1000, 400);
}
