"""
Space Shift - wormhole blockout v2: a twisted, ridged funnel with a mirror
sphere plugging its throat. Replaces the earlier floating-streaks concept -
the funnel's own ridge geometry now does the "tunnel" work, and the sphere
reflects the funnel walls around it directly instead of a separate object.

The funnel is built vertex-by-vertex (not primitive+modifier) so the twist
is baked into real geometry via ridges that visibly spiral - a smooth cone
twisted with no surface detail wouldn't look any different twisted or not.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender --background --python wormhole_blockout.py -- <output.blend> <output.png>
"""
import bpy
import bmesh
import sys
import math
import random

argv = sys.argv
argv = argv[argv.index("--") + 1:] if "--" in argv else []
OUT_BLEND = argv[0] if argv else "/tmp/wormhole_blockout.blend"
OUT_PNG = argv[1] if len(argv) > 1 else "/tmp/wormhole_blockout.png"

random.seed(11)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

collection = bpy.data.collections.new("Wormhole_Blockout")
scene.collection.children.link(collection)

def link(obj):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    collection.objects.link(obj)
    return obj

def make_emission_material(name, rgb, strength):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    emission = nt.nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (*rgb, 1.0)
    emission.inputs["Strength"].default_value = strength
    output = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    return mat

# ------------------------------------------------------------------
# World: same fixed starfield as before (F1 Voronoi, tight threshold ->
# pinpoint stars against a dark void) - gives the funnel interior and the
# sphere something real to catch light/reflections from.
# ------------------------------------------------------------------
world = bpy.data.worlds.new("WarpVoid")
scene.world = world
world.use_nodes = True
wnt = world.node_tree
wnt.nodes.clear()

tex_coord = wnt.nodes.new("ShaderNodeTexCoord")
voronoi = wnt.nodes.new("ShaderNodeTexVoronoi")
voronoi.inputs["Scale"].default_value = 60.0
voronoi.inputs["Randomness"].default_value = 1.0
voronoi.feature = 'F1'
ramp = wnt.nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.0
ramp.color_ramp.elements[0].color = (1.0, 1.0, 1.0, 1.0)
ramp.color_ramp.elements[1].position = 0.03
ramp.color_ramp.elements[1].color = (0.0, 0.0, 0.0, 1.0)
star_boost = wnt.nodes.new("ShaderNodeMixRGB")
star_boost.blend_type = 'MULTIPLY'
star_boost.inputs[0].default_value = 1.0
star_boost.inputs[2].default_value = (8.0, 8.0, 9.0, 1.0)
void_color = wnt.nodes.new("ShaderNodeMixRGB")
void_color.blend_type = 'ADD'
void_color.inputs[0].default_value = 1.0
void_color.inputs[1].default_value = (0.02, 0.01, 0.05, 1.0)
background = wnt.nodes.new("ShaderNodeBackground")
world_output = wnt.nodes.new("ShaderNodeOutputWorld")

wnt.links.new(tex_coord.outputs["Generated"], voronoi.inputs["Vector"])
wnt.links.new(voronoi.outputs["Distance"], ramp.inputs["Fac"])
wnt.links.new(ramp.outputs["Color"], star_boost.inputs[1])
wnt.links.new(star_boost.outputs["Color"], void_color.inputs[2])
wnt.links.new(void_color.outputs["Color"], background.inputs["Color"])
background.inputs["Strength"].default_value = 1.0
wnt.links.new(background.outputs["Background"], world_output.inputs["Surface"])

# ------------------------------------------------------------------
# Twisted, ridged funnel - built directly as a vertex grid so the twist
# shows up as real spiraling geometry, not just an invisible deformation
# on a smooth cone.
#
# Axis is Y: mouth (wide) at y=0 near the camera, throat (narrow) at
# y=FUNNEL_LENGTH where the sphere plugs it.
# ------------------------------------------------------------------
MOUTH_RADIUS = 6.0
THROAT_RADIUS = 0.9
FUNNEL_LENGTH = 26.0
LENGTH_STEPS = 100
ANGULAR_STEPS = 64
TOTAL_TWIST = math.radians(360 * 5)     # 5 full rotations along the length
RIDGE_COUNT = 10                        # number of spiraling ridges around the circumference
RIDGE_DEPTH = 0.3                       # as a fraction of local radius
BEND_AMOUNT = 10.0                      # lateral drift of the tunnel's centerline by the throat
BEND_EXPONENT = 1.6                     # >1 = stays straight near the mouth, curves increasingly toward the throat

def path_center(t):
    return (BEND_AMOUNT * t ** BEND_EXPONENT, t * FUNNEL_LENGTH, 0.0)

def path_tangent(t):
    dx = BEND_AMOUNT * BEND_EXPONENT * (t ** (BEND_EXPONENT - 1.0)) if t > 0 else 0.0
    dy = FUNNEL_LENGTH
    length = math.hypot(dx, dy)
    return (dx / length, dy / length)

# Emission has no lighting response, so a geometric ridge alone doesn't show
# up as shading - the same sine phase used to bump the radius is also baked
# into per-vertex color brightness below, so the ridges read as visible
# spiraling light/dark bands instead of disappearing into flat color.
#
# Each ring is built in its own frame (N, B) that follows the bending
# centerline rather than raw world X/Z, so cross-sections stay circular
# (not stretched into ellipses) as the tunnel curves.
verts = []
ridge_shade = []
for i in range(LENGTH_STEPS + 1):
    t = i / LENGTH_STEPS
    cx, cy, cz = path_center(t)
    tx, ty = path_tangent(t)
    # N: tangent rotated 90 degrees within the XY (bend) plane. B: fixed Z -
    # the bend never pulls the path out of the XY plane, so the binormal
    # needs no rotation of its own.
    nx, ny = ty, -tx
    # Funnel profile: an exponent <1 on (1-t) keeps the tube close to
    # MOUTH_RADIUS through most of its length, narrowing sharply only near
    # the very end - needed so the tube stays wide (and see-through) through
    # the middle stretch where the bend is doing most of its work; a
    # fast-narrowing profile there self-occludes the throat from any single
    # straight camera sightline once the bend is pronounced (confirmed
    # numerically, not just by eye).
    radius = THROAT_RADIUS + (MOUTH_RADIUS - THROAT_RADIUS) * (1.0 - t) ** 0.4
    twist = t * TOTAL_TWIST

    ring = []
    for j in range(ANGULAR_STEPS):
        a = (j / ANGULAR_STEPS) * math.tau
        bump = math.sin(a * RIDGE_COUNT) * (0.6 + 0.4 * t)
        ridge = 1.0 + RIDGE_DEPTH * bump
        r = radius * ridge
        ca, sa = math.cos(a + twist), math.sin(a + twist)
        x = cx + r * ca * nx
        y = cy + r * ca * ny
        z = cz + r * sa
        ring.append((x, y, z))
        ridge_shade.append(0.55 + 0.45 * bump)
    verts.extend(ring)

faces = []
for i in range(LENGTH_STEPS):
    for j in range(ANGULAR_STEPS):
        j2 = (j + 1) % ANGULAR_STEPS
        a0 = i * ANGULAR_STEPS + j
        a1 = i * ANGULAR_STEPS + j2
        b0 = (i + 1) * ANGULAR_STEPS + j
        b1 = (i + 1) * ANGULAR_STEPS + j2
        faces.append((a0, a1, b1, b0))

mesh = bpy.data.meshes.new("FunnelMesh")
mesh.from_pydata(verts, [], faces)
mesh.update()
funnel = bpy.data.objects.new("TwistedFunnel", mesh)
link(funnel)
bpy.context.view_layer.objects.active = funnel
funnel.select_set(True)
bpy.ops.object.shade_smooth()

# Color gradient along the funnel's length (mouth = blue, throat = hot
# magenta/red), via vertex colors read straight by an emission material -
# simplest way to get a rich per-vertex gradient without extra UV work.
color_attr = mesh.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='POINT')
GRADIENT = [
    (0.15, 0.35, 1.0),
    (0.45, 0.25, 1.0),
    (0.85, 0.20, 0.75),
    (1.0, 0.25, 0.35),
]
for i in range(LENGTH_STEPS + 1):
    t = i / LENGTH_STEPS
    seg = t * (len(GRADIENT) - 1)
    idx = min(int(seg), len(GRADIENT) - 2)
    f = seg - idx
    c0, c1 = GRADIENT[idx], GRADIENT[idx + 1]
    base = tuple(c0[k] + (c1[k] - c0[k]) * f for k in range(3))
    for j in range(ANGULAR_STEPS):
        idx_flat = i * ANGULAR_STEPS + j
        shade = ridge_shade[idx_flat]
        col = tuple(base[k] * shade for k in range(3)) + (1.0,)
        color_attr.data[idx_flat].color = col

funnel_mat = bpy.data.materials.new("FunnelGlow")
funnel_mat.use_nodes = True
fnt = funnel_mat.node_tree
fnt.nodes.clear()
attr = fnt.nodes.new("ShaderNodeVertexColor")
attr.layer_name = "Col"
emission = fnt.nodes.new("ShaderNodeEmission")
emission.inputs["Strength"].default_value = 1.3
fout = fnt.nodes.new("ShaderNodeOutputMaterial")
fnt.links.new(attr.outputs["Color"], emission.inputs["Color"])
fnt.links.new(emission.outputs["Emission"], fout.inputs["Surface"])
funnel.data.materials.append(funnel_mat)

# ------------------------------------------------------------------
# Event horizon: a mirror sphere plugging the funnel's throat - sized
# bigger than the throat opening so it visibly blocks/caps the tunnel
# rather than just floating inside it.
# ------------------------------------------------------------------
SPHERE_RADIUS = THROAT_RADIUS * 2.5
sphere_t = 1.0 - (SPHERE_RADIUS * 0.35) / FUNNEL_LENGTH   # pushed further into the tight aperture at the far end
sphere_loc = path_center(sphere_t)
bpy.ops.mesh.primitive_uv_sphere_add(radius=SPHERE_RADIUS, segments=64, ring_count=32, location=sphere_loc)
sphere = bpy.context.active_object
sphere.name = "EventHorizon"
bpy.ops.object.shade_smooth()
mirror_mat = bpy.data.materials.new("Mirror")
mirror_mat.use_nodes = True
bsdf = mirror_mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.18, 0.18, 0.22, 1.0)
bsdf.inputs["Metallic"].default_value = 1.0
bsdf.inputs["Roughness"].default_value = 0.02
sphere.data.materials.append(mirror_mat)
link(sphere)

# ------------------------------------------------------------------
# Camera: at the funnel's mouth looking down its throat at the sphere.
# ------------------------------------------------------------------
bpy.ops.object.camera_add(location=(-1.0, -13.0, 0.3))
camera = bpy.context.active_object
camera.name = "TunnelCam"
# Offset toward the inside of the bend on purpose - dead-center on the
# original axis, a big enough bend puts the sphere behind the tunnel's own
# wall (confirmed by hiding the funnel mesh and seeing the sphere reappear
# untouched). Standing toward the inside of the curve, like at a bend in a
# hallway, keeps the sightline down to the throat clear.
camera.data.lens = 24
track = camera.constraints.new(type='TRACK_TO')
track.target = sphere
track.track_axis = 'TRACK_NEGATIVE_Z'
track.up_axis = 'UP_Y'
link(camera)
scene.camera = camera

# ------------------------------------------------------------------
# Render: Cycles, standard view transform + no denoising (AgX + the AI
# denoiser were both found to wash the mirror sphere's reflection into a
# flat grey in the previous blockout).
# ------------------------------------------------------------------
scene.render.engine = 'CYCLES'
scene.cycles.samples = 256
scene.cycles.use_denoising = False
scene.view_settings.view_transform = 'Standard'
scene.render.resolution_x = 1280
scene.render.resolution_y = 720
scene.render.filepath = OUT_PNG
scene.render.image_settings.file_format = 'PNG'

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print(f"Saved blockout to {OUT_BLEND}")

bpy.ops.render.render(write_still=True)
print(f"Rendered preview to {OUT_PNG}")
