"""Builds the Vela-07 mech in Blender as an assembled robot.

Run headless (Blender 5.x):
  blender --background --factory-startup --python build_vela_07.py -- blend=<out.blend> glb=<out.glb> [renders=<dir>] [palette=<name>]

palette picks the paint scheme (see PALETTES): vela_07 (default, purple / black / grey) or
vela_08 (blue / orange, saved as art_src/vela_08/vela_08.blend and assets/models/vela_08.glb).

Based on the Meshy "Vela-07" front / side / back concept views. The model faces -Y (Blender
front view), feet at z = 0, about 3 m to the top of the head, in a T-pose.

It is built like a real robot: every moving part is its own object ("<Bone>_Part") with its
origin on its joint, parented to that bone of the "Vela07" armature, so each piece pivots where
it should. Joints are modelled on the pivots: ball joints (shoulders, hips, wrists, ankles),
hinges whose axis matches the way the joint bends (elbows, knees, knuckles, toes), a waist
bearing, a neck column and a hinge for the back plates. Upper arms and thighs fork around the
elbow and knee hinges so forearms and shins swing between the forks, and the shoulder caps sit
above the arms so they can swing forward to aim.

Bones use Godot's SkeletonProfileHumanoid names (Hips, Spine, Chest, LeftUpperArm,
LeftIndexProximal, ...) plus Root and Backpack. The right hand is an arm cannon (no finger bones
on that side); the RightMuzzle bone marks where shots come out, pointing along the barrel.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ARGS = dict(a.split("=", 1) for a in argv if "=" in a)
OUT_BLEND = ARGS.get("blend")
OUT_GLB = ARGS.get("glb")
RENDER_DIR = ARGS.get("renders")

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
scene = bpy.context.scene
COL = scene.collection


# --- Materials -------------------------------------------------------------

def make_mat(name, base, metal=0.5, rough=0.4, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = (*base, 1.0)
    return m


# Paint schemes: the same robot in different colours, picked with palette=<name> (default vela_07).
# The material variables keep Vela-07's names but stand for roles: GREY = light plates,
# VIOLET = main armour, VIOLET_DARK = dark armour, GLOW_PURPLE = main glow (visor, core,
# cannon coils), GLOW_BLUE = secondary glow strips, CRYSTAL = claw tips.
# Each entry is (material name, base colour, metallic, roughness[, emission colour, strength]);
# "face" picks the knight helm faceplate material (GREY or DECAL).
PALETTES = {
    "vela_07": {  # purple / black / grey, from the concept art
        "title": "Vela07", "number": "07", "face": "GREY",
        "GREY": ("armor_grey", (0.5, 0.5, 0.56), 0.3, 0.42),
        "VIOLET": ("armor_violet", (0.13, 0.06, 0.34), 0.55, 0.35),
        "VIOLET_DARK": ("armor_violet_dark", (0.05, 0.03, 0.11), 0.6, 0.4),
        "GLOW_PURPLE": ("glow_purple", (0.5, 0.2, 1.0), 0.0, 0.3, (0.55, 0.15, 1.0), 4.0),
        "GLOW_BLUE": ("glow_blue", (0.15, 0.4, 1.0), 0.0, 0.3, (0.08, 0.35, 1.0), 4.0),
        "CRYSTAL": ("crystal", (0.45, 0.28, 0.95), 0.1, 0.15, (0.45, 0.2, 1.0), 2.0),
        "SCREEN": ("screen_blue", (0.02, 0.06, 0.15), 0.2, 0.2, (0.04, 0.22, 0.6), 2.5),
    },
    "vela_08": {  # blue / orange sibling
        "title": "Vela08", "number": "08", "face": "DECAL",  # white helm face so the orange slit stands out
        "GREY": ("armor_orange", (1.0, 0.17, 0.01), 0.2, 0.4),
        "VIOLET": ("armor_blue", (0.025, 0.13, 0.55), 0.5, 0.35),
        "VIOLET_DARK": ("armor_blue_dark", (0.008, 0.025, 0.09), 0.6, 0.4),
        "GLOW_PURPLE": ("glow_orange", (1.0, 0.2, 0.01), 0.0, 0.3, (1.0, 0.12, 0.0), 1.6),  # stronger clips to yellow
        "GLOW_BLUE": ("glow_cyan", (0.1, 0.6, 1.0), 0.0, 0.3, (0.05, 0.55, 1.0), 4.0),
        "CRYSTAL": ("crystal_orange", (1.0, 0.25, 0.03), 0.1, 0.15, (1.0, 0.15, 0.0), 1.2),
        "SCREEN": ("screen_amber", (0.15, 0.04, 0.005), 0.2, 0.2, (1.0, 0.15, 0.0), 1.0),
    },
}
PALETTE = PALETTES[ARGS.get("palette", "vela_07")]
TITLE = PALETTE["title"]

JOINT = make_mat("joint_black", (0.02, 0.02, 0.025), 0.8, 0.45)
GUNMETAL = make_mat("gunmetal", (0.06, 0.06, 0.075), 0.75, 0.4)
GREY = make_mat(*PALETTE["GREY"])
VIOLET = make_mat(*PALETTE["VIOLET"])
VIOLET_DARK = make_mat(*PALETTE["VIOLET_DARK"])
GLOW_PURPLE = make_mat(*PALETTE["GLOW_PURPLE"])
GLOW_BLUE = make_mat(*PALETTE["GLOW_BLUE"])
CRYSTAL = make_mat(*PALETTE["CRYSTAL"])
SCREEN = make_mat(*PALETTE["SCREEN"])
DECAL = make_mat("decal_white", (0.8, 0.8, 0.86), 0.1, 0.5)
FACE = {"GREY": GREY, "DECAL": DECAL}[PALETTE["face"]]  # knight helm faceplate
# Helm dome: the main armour colour, but matte, so the smooth dome doesn't catch one big
# white highlight under the game's toon specular.
DOME = make_mat(PALETTE["VIOLET"][0] + "_matte", PALETTE["VIOLET"][1], 0.1, 0.85)


# --- Part builders ---------------------------------------------------------
# Pieces are modelled in world (T-pose) coordinates and collected per bone in PARTS;
# each bone's pieces are later joined into one part object pivoting on that bone.

GROUP = ["Chest"]
PARTS = {}


def _finish(name, bm, mat, bevel=0.0, smooth=False):
    if bevel > 0:
        try:
            bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=bevel, offset_type="OFFSET",
                            segments=1, profile=0.5, affect="EDGES", clamp_overlap=True)
        except Exception as e:  # keep building even if one bevel fails
            print("bevel failed on", name, e)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    full = f"{GROUP[0]}:{name}"
    me = bpy.data.meshes.new(full)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    return _link(full, me, mat)


def _link(full, me, mat):
    me.materials.append(mat)
    obj = bpy.data.objects.new(full, me)
    COL.objects.link(obj)
    PARTS.setdefault(GROUP[0], []).append(obj)
    return obj


def hull(name, pts, mat, bevel=0.006, smooth=False):
    """Convex hull of the points. smooth=True shades it as a rounded shell (keeping sharp rims)."""
    seen, uniq = set(), []
    for p in pts:
        key = tuple(round(v, 5) for v in p)
        if key not in seen:
            seen.add(key)
            uniq.append(p)
    bm = bmesh.new()
    for p in uniq:
        bm.verts.new(p)
    res = bmesh.ops.convex_hull(bm, input=bm.verts[:])
    loose = list({g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)})
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.5), verts=bm.verts[:], edges=bm.edges[:])
    obj = _finish(name, bm, mat, bevel, smooth)
    if smooth:
        obj.data.set_sharp_from_angle(angle=math.radians(50))
    return obj


def sym(pts):
    """Points plus their mirror across x = 0."""
    return list(pts) + [(-x, y, z) for x, y, z in pts if abs(x) > 1e-6]


def side(s, pts):
    return [(x * s, y, z) for x, y, z in pts]


def cbox(name, c, size, mat, ch=0.015, bevel=0.0):
    """Box with chamfered edges."""
    cx, cy, cz = c
    hx, hy, hz = (v / 2 for v in size)
    ch = min(ch, hx * 0.9, hy * 0.9, hz * 0.9)
    pts = []
    for ax, ay, az in ((hx, hy - ch, hz - ch), (hx - ch, hy, hz - ch), (hx - ch, hy - ch, hz)):
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    pts.append((cx + sx * ax, cy + sy * ay, cz + sz * az))
    return hull(name, pts, mat, bevel)


def taper(name, c0, wd0, c1, wd1, mat, bevel=0.006):
    """Hull between two horizontal rectangles (centre, (width, depth)): a vertical limb segment."""
    pts = []
    for (cx, cy, cz), (w, d) in ((c0, wd0), (c1, wd1)):
        for sx in (-1, 1):
            for sy in (-1, 1):
                pts.append((cx + sx * w / 2, cy + sy * d / 2, cz))
    return hull(name, pts, mat, bevel)


def xtaper(name, x0, x1, cy, cz, half0, half1, mat, bevel=0.006):
    """Hull between two rectangles across the X axis ((half depth, half height) at x0 and x1):
    a horizontal (T-pose arm) limb segment."""
    pts = []
    for x, (hy, hz) in ((x0, half0), (x1, half1)):
        for sy in (-1, 1):
            for sz in (-1, 1):
                pts.append((x, cy + sy * hy, cz + sz * hz))
    return hull(name, pts, mat, bevel)


def rod(name, p0, p1, r, mat, r1=None, segs=12, smooth=False):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs,
                          radius1=r, radius2=r if r1 is None else max(r1, 0.0005), depth=d.length)
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation((p0 + p1) / 2) @ rot, verts=bm.verts[:])
    return _finish(name, bm, mat, smooth=smooth)


def disc(name, c, axis, r, depth, mat, segs=16):
    c, a = Vector(c), Vector(axis).normalized()
    return rod(name, c - a * depth / 2, c + a * depth / 2, r, mat, segs=segs)


def hinge(name, c, axis, r, length, mat=None, segs=16):
    """Hinge pin centred on a joint, its axis along the direction the joint bends about."""
    return disc(name, c, axis, r, length, mat or JOINT, segs=segs)


def ball(name, c, r, mat=None):
    """Smooth ball joint centred on a pivot."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=r)
    bmesh.ops.translate(bm, vec=Vector(c), verts=bm.verts[:])
    return _finish(name, bm, mat or JOINT, smooth=True)


def ring(name, c, axis, R, r, mat, seg=32, mseg=6):
    bm = bmesh.new()
    rows = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        row = []
        for j in range(mseg):
            b = 2 * math.pi * j / mseg
            rr = R + r * math.cos(b)
            row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), r * math.sin(b))))
        rows.append(row)
    for i in range(seg):
        for j in range(mseg):
            bm.faces.new((rows[i][j], rows[(i + 1) % seg][j],
                          rows[(i + 1) % seg][(j + 1) % mseg], rows[i][(j + 1) % mseg]))
    rot = Vector((0, 0, 1)).rotation_difference(Vector(axis).normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(c) @ rot, verts=bm.verts[:])
    return _finish(name, bm, mat)


def bar(name, p0, p1, w, n, mat, t=0.01):
    """Flat strip from p0 to p1, width w, lying on a surface with normal n."""
    p0, p1, n = Vector(p0), Vector(p1), Vector(n).normalized()
    across = (p1 - p0).cross(n).normalized() * (w / 2)
    pts = []
    for p in (p0, p1):
        for q in (p + across, p - across):
            pts += [q - n * t * 0.4, q + n * t * 0.6]
    return hull(name, pts, mat, bevel=0)


def tri_frame(name, c, n, up, size, w, mat):
    """Downward-pointing triangle outline (the Vela emblem) on a surface."""
    c, n, up = Vector(c), Vector(n).normalized(), Vector(up).normalized()
    right = up.cross(n).normalized()
    a = c - right * size + up * size * 0.6
    b = c + right * size + up * size * 0.6
    d = c - up * size
    for i, (p, q) in enumerate(((a, b), (b, d), (d, a))):
        bar(f"{name}{i}", p, q, w, n, mat, t=0.006)


def text(name, body, c, rot, size, mat):
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = body
    cu.size = size
    cu.extrude = 0.002
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    tmp = bpy.data.objects.new(name + "_tmp", cu)
    COL.objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp)
    bpy.data.curves.remove(cu)
    me.transform(Matrix.LocRotScale(Vector(c), Euler(rot), None))
    full = f"{GROUP[0]}:{name}"
    me.name = full
    return _link(full, me, mat)


R90 = math.radians(90)
SIDE_NAME = {1: "Left", -1: "Right"}
FINGERS = ("Index", "Middle", "Ring", "Little")


# --- Joint layout (T-pose, world space) --------------------------------------
# Every bone starts on its joint. Arms run along X at shoulder height, legs straight down.

SHOULDER_Z = 2.56
PIVOT = {
    "Root": (0, 0, 0),
    "Hips": (0, 0, 1.86),
    "Spine": (0, 0, 2.04),
    "Chest": (0, 0, 2.24),
    "Neck": (0, -0.01, 2.70),
    "Head": (0, -0.02, 2.80),
    "Backpack": (0, 0.31, 2.62),
}
for _s, _S in SIDE_NAME.items():
    PIVOT.update({
        f"{_S}Shoulder": (0.14 * _s, 0, 2.62),
        f"{_S}UpperArm": (0.46 * _s, 0, SHOULDER_Z),
        f"{_S}LowerArm": (0.86 * _s, 0, SHOULDER_Z),
        f"{_S}Hand": (1.30 * _s, 0, SHOULDER_Z),
        f"{_S}UpperLeg": (0.2 * _s, 0, 1.82),
        f"{_S}LowerLeg": (0.27 * _s, 0, 1.30),
        f"{_S}Foot": (0.31 * _s, 0, 0.50),
        f"{_S}Toes": (0.32 * _s, -0.22, 0.11),
    })
FINGER_JOINTS = {}  # bone name -> (head, tail), filled while the left hand is built
MUZZLE = {}         # head / tail of the RightMuzzle bone, filled by build_cannon


def P(bone):
    return Vector(PIVOT[bone])


# --- Torso, head and back ----------------------------------------------------

def build_torso():
    GROUP[0] = "Hips"
    taper("pelvis", (0, 0.0, 1.70), (0.3, 0.24), (0, 0.0, 1.98), (0.4, 0.3), GUNMETAL)
    hull("codpiece", sym([
        (0.11, -0.2, 2.0), (0.11, -0.13, 2.02), (0.0, -0.18, 1.68), (0.0, -0.12, 1.7),
        (0.08, -0.22, 1.84), (0.08, -0.14, 1.84)]), GREY)
    tri_frame("cod_emblem", (0, -0.226, 1.93), (0, -1, 0), (0, 0, 1), 0.03, 0.009, GLOW_PURPLE)
    bar("cod_glow", (-0.03, -0.195, 1.74), (0.03, -0.195, 1.74), 0.015, (0, -1, 0), GLOW_PURPLE)
    for s in (-1, 1):
        # Short front skirts, ending above the hip joints so the thighs swing beneath them.
        hull(f"skirt{s}", side(s, [
            (0.13, -0.17, 2.04), (0.31, -0.13, 2.04), (0.13, -0.12, 2.04), (0.31, -0.09, 2.04),
            (0.19, -0.2, 1.9), (0.32, -0.15, 1.88), (0.19, -0.14, 1.9), (0.32, -0.1, 1.88)]), VIOLET)
        bar(f"skirt_glow{s}", (0.215 * s, -0.188, 2.0), (0.245 * s, -0.196, 1.92), 0.035, (0.1 * s, -1, 0), GLOW_BLUE)
    hull("rear_skirt", sym([(0.19, 0.1, 2.02), (0.19, 0.19, 2.0), (0.15, 0.1, 1.86), (0.15, 0.17, 1.86)]), VIOLET_DARK)

    GROUP[0] = "Spine"
    rod("waist_bearing", (0, 0, 1.97), (0, 0, 2.06), 0.15, JOINT, segs=20)
    cbox("abdomen_lo", (0, 0.0, 2.1), (0.34, 0.24, 0.08), GUNMETAL, ch=0.025, bevel=0.004)
    cbox("abdomen_hi", (0, 0.0, 2.18), (0.38, 0.26, 0.08), JOINT, ch=0.025)
    hull("abdomen_front", sym([(0.15, -0.18, 2.23), (0.0, -0.2, 2.05), (0.15, -0.12, 2.23), (0.0, -0.13, 2.05),
                               (0.11, -0.18, 2.1)]), VIOLET_DARK)
    for s in (-1, 1):
        bar(f"abdomen_glow{s}", (0.125 * s, -0.188, 2.2), (0.095 * s, -0.194, 2.11), 0.022, (0.2 * s, -1, 0), GLOW_BLUE)

    GROUP[0] = "Chest"
    hull("chest", sym([
        (0.24, -0.18, 2.24), (0.24, 0.16, 2.24), (0.0, -0.22, 2.24),
        (0.34, -0.2, 2.45), (0.34, 0.18, 2.45), (0.16, -0.29, 2.45), (0.0, -0.3, 2.45),
        (0.28, -0.15, 2.66), (0.28, 0.16, 2.66), (0.1, -0.22, 2.66),
        (0.16, -0.08, 2.73), (0.16, 0.12, 2.73)]), GUNMETAL, bevel=0.008)
    for s in (-1, 1):
        hull(f"chest_yoke{s}", side(s, [
            (0.1, -0.235, 2.64), (0.3, -0.19, 2.62), (0.12, -0.27, 2.55), (0.33, -0.22, 2.5),
            (0.1, -0.18, 2.67), (0.3, -0.13, 2.65)]), GREY, bevel=0.005)
        hull(f"chest_side{s}", side(s, [
            (0.33, -0.15, 2.26), (0.33, 0.15, 2.26), (0.36, -0.12, 2.3), (0.36, 0.12, 2.3),
            (0.36, -0.14, 2.46), (0.36, 0.14, 2.46), (0.33, -0.18, 2.48), (0.33, 0.16, 2.48)]), GUNMETAL)
        bar(f"chest_glow{s}", (0.2 * s, -0.282, 2.53), (0.28 * s, -0.258, 2.5), 0.018, (0.25 * s, -1, 0.1), GLOW_BLUE)
        bar(f"rib_glow{s}", (0.22 * s, -0.25, 2.33), (0.28 * s, -0.22, 2.31), 0.016, (0.3 * s, -1, -0.3), GLOW_BLUE)
        hull(f"collar_diamond{s}", side(s, [   # small purple diamonds above the core
            (0.05, -0.262, 2.63), (0.08, -0.262, 2.65), (0.11, -0.258, 2.63), (0.08, -0.258, 2.61),
            (0.08, -0.272, 2.63)]), GLOW_PURPLE, bevel=0)
    # Targeting-reticle chest core.
    disc("core_housing", (0, -0.3, 2.45), (0, 1, 0), 0.175, 0.06, JOINT, segs=32)
    disc("core_screen", (0, -0.332, 2.45), (0, 1, 0), 0.135, 0.008, SCREEN, segs=32)
    ring("core_ring_outer", (0, -0.333, 2.45), (0, 1, 0), 0.165, 0.009, GLOW_PURPLE)
    ring("core_ring", (0, -0.338, 2.45), (0, 1, 0), 0.115, 0.016, GLOW_BLUE)
    ring("core_ring_inner", (0, -0.338, 2.45), (0, 1, 0), 0.04, 0.008, GLOW_BLUE)
    for i, (dx, dz) in enumerate(((1, 0), (-1, 0), (0, 1), (0, -1))):
        bar(f"core_tick{i}", (dx * 0.055, -0.338, 2.45 + dz * 0.055), (dx * 0.095, -0.338, 2.45 + dz * 0.095),
            0.012, (0, -1, 0), GLOW_BLUE)
    cbox("collar", (0, 0.0, 2.715), (0.3, 0.24, 0.05), JOINT, ch=0.02)
    # Backpack housing is fixed to the chest; only the wing plates hinge.
    cbox("pack", (0, 0.2, 2.45), (0.42, 0.18, 0.42), GUNMETAL, ch=0.04, bevel=0.005)

    GROUP[0] = "Neck"
    rod("neck", (0, -0.01, 2.68), (0, -0.02, 2.83), 0.055, JOINT, smooth=True)
    ring("neck_ring", (0, -0.015, 2.75), (0, 0, 1), 0.058, 0.01, GREY, seg=20)

    GROUP[0] = "Head"
    # Knight's helm: a rounded dome with a low comb over the top, and in front a faceplate with a
    # beak ridged down the middle (like a bascinet): an upper visor plate, a recessed glowing eye
    # slit, then the lower plate with breathing vents. Visor pivots on the sides. No eyes or mouth.
    hc, rx, ry, rz = Vector((0, -0.03, 2.885)), 0.128, 0.152, 0.155  # dome centre and radii

    def dome_z(y):  # height of the dome's top centre line at y
        return hc.z + rz * math.sqrt(max(0.0, 1 - ((y - hc.y) / ry) ** 2))

    dome = [hc + Vector((rx * math.cos(e) * math.sin(a), -ry * math.cos(e) * math.cos(a), rz * math.sin(e)))
            for a in (math.radians(d) for d in range(0, 360, 15))
            for e in (math.radians(d) for d in (0, 22, 44, 64, 80))]
    dome += [Vector((0.94 * rx * math.sin(math.radians(d)), hc.y - 0.94 * ry * math.cos(math.radians(d)), 2.775))
             for d in range(75, 286, 15)]  # straight skirt down the sides and back (the faceplate covers the front)
    dome.append(hc + Vector((0, 0, rz)))
    hull("dome", dome, DOME, bevel=0, smooth=True)
    comb = []
    for i in range(7):
        y = -0.15 + 0.28 * i / 6
        h = 0.006 + 0.018 * math.sin(math.pi * i / 6)  # tallest over the crown
        comb += [(0.009, y, dome_z(y) - 0.01), (-0.009, y, dome_z(y) - 0.01), (0, y, dome_z(y) + h)]
    hull("comb", comb, GREY, bevel=0.002)

    # Faceplate cross-section: front outline from the beak (x = 0) round to the cheek, scaled
    # by height so it rounds off at the top and tucks in at the chin. Every faceplate piece is
    # cut from this one profile so they line up.
    face_x = (0.0, 0.06, 0.1, 0.126)
    face_y = (-0.268, -0.185, -0.13, -0.085)
    back_y_face = -0.02  # where the plate meets the dome

    def keyed(keys, z):
        for (z0, v0), (z1, v1) in zip(keys, keys[1:]):
            if z <= z1:
                return v0 + (v1 - v0) * max(0.0, (z - z0) / (z1 - z0))
        return keys[-1][1]

    depth = ((2.755, 0.72), (2.79, 0.9), (2.85, 1.0), (2.9, 1.0), (2.94, 0.95), (2.985, 0.78))
    width = ((2.755, 0.74), (2.79, 0.92), (2.85, 1.0), (2.9, 1.0), (2.94, 0.97), (2.985, 0.88))

    def face_pt(i, z, inset=0.0):
        f = keyed(depth, z) * (1 - inset)
        return Vector((face_x[i] * keyed(width, z), back_y_face + (face_y[i] - back_y_face) * f, z))

    def face_rows(zs, inset=0.0):
        pts = []
        for z in zs:
            row = [face_pt(i, z, inset) for i in range(len(face_x))]
            row.append(Vector((row[-1].x, back_y_face, z)))
            pts += sym([tuple(p) for p in row])
        return pts

    hull("visor_plate", face_rows((2.931, 2.958, 2.985)), FACE, bevel=0)
    hull("eye_slit", face_rows((2.9, 2.933), inset=0.07), GLOW_PURPLE, bevel=0)   # recessed between plates
    hull("ventail", face_rows((2.755, 2.775, 2.8, 2.85, 2.902)), FACE, bevel=0)
    for s in (-1, 1):
        for k in range(3):  # breaths: vent slots either side of the beak
            zz = 2.805 + 0.02 * k
            a, b = face_pt(0, zz), face_pt(1, zz)
            d = b - a
            n = Vector((d.y * s, -d.x, 0)).normalized()
            p0, p1 = a + d * 0.3, a + d * 0.85
            bar(f"breath{s}{k}", (p0.x * s, p0.y, zz), (p1.x * s, p1.y, zz), 0.008, n, JOINT)
        # Visor pivots (rosettes) on the sides of the dome.
        disc(f"visor_pivot{s}", (0.118 * s, -0.04, 2.9), (1, 0, 0), 0.035, 0.03, GREY)
        ring(f"pivot_ring{s}", (0.134 * s, -0.04, 2.9), (1, 0, 0), 0.022, 0.006, GLOW_BLUE)

    GROUP[0] = "Backpack"
    hinge("plate_hinge", P("Backpack"), (1, 0, 0), 0.035, 0.34)
    hull("spine_slab", sym([
        (0.12, 0.22, 2.74), (0.12, 0.32, 2.74), (0.14, 0.33, 2.2), (0.14, 0.45, 2.2),
        (0.08, 0.45, 1.6), (0.08, 0.53, 1.6), (0.0, 0.52, 1.15), (0.0, 0.57, 1.2)]), VIOLET_DARK, bevel=0.008)
    n = Vector((0, 0.54, 0.13)).normalized()
    bar("back_screen", (0, back_y(2.66), 2.66), (0, back_y(2.4), 2.4), 0.16, n, SCREEN, t=0.012)
    tri_frame("back_emblem", (0, back_y(2.53) + 0.008, 2.53), n, (0, -n.z, n.y), 0.045, 0.01, DECAL)
    for s in (-1, 1):
        bar(f"spine_glow{s}", (0.105 * s, back_y(2.36) + 0.002, 2.36), (0.11 * s, back_y(1.95) + 0.002, 1.95),
            0.022, (0, 1, 0.15), GLOW_BLUE)
        bar(f"spine_glow_lo{s}", (0.04 * s, back_y(1.85) + 0.002, 1.85), (0.03 * s, back_y(1.42) + 0.002, 1.42),
            0.018, (0, 1, 0.07), GLOW_PURPLE)
        hull(f"wing_slab{s}", side(s, [
            (0.12, 0.21, 2.66), (0.28, 0.19, 2.62), (0.12, 0.27, 2.66), (0.28, 0.25, 2.62),
            (0.16, 0.35, 2.0), (0.3, 0.31, 2.05), (0.16, 0.41, 2.0), (0.3, 0.37, 2.05),
            (0.22, 0.41, 1.45), (0.22, 0.45, 1.45)]), VIOLET, bevel=0.006)
        bar(f"wing_glow{s}", (0.22 * s, 0.288, 2.5), (0.235 * s, 0.39, 2.0), 0.024, (0, 1, 0.2), GLOW_BLUE)
        hull(f"outer_slab{s}", side(s, [
            (0.26, 0.17, 2.5), (0.38, 0.14, 2.45), (0.26, 0.23, 2.5), (0.38, 0.2, 2.45),
            (0.3, 0.29, 1.9), (0.37, 0.26, 1.9), (0.3, 0.34, 1.9), (0.37, 0.31, 1.9), (0.33, 0.35, 1.6)]),
            GUNMETAL, bevel=0.005)
        bar(f"outer_glow{s}", (0.335 * s, 0.235, 2.35), (0.34 * s, 0.315, 1.95), 0.02, (0.3 * s, 1, 0.15), GLOW_PURPLE)


BACK_PROFILE = [(2.74, 0.32), (2.2, 0.45), (1.6, 0.53), (1.2, 0.57)]


def back_y(z):
    """Depth of the back plate's rear face at height z."""
    for (z0, y0), (z1, y1) in zip(BACK_PROFILE, BACK_PROFILE[1:]):
        if z1 <= z <= z0:
            return y0 + (y1 - y0) * (z0 - z) / (z0 - z1)
    return BACK_PROFILE[-1][1]


# --- Arms --------------------------------------------------------------------

def build_arm(s):
    S = SIDE_NAME[s]
    z = SHOULDER_Z

    # Shoulder cap: sits above the shoulder ball so the arm can swing out or forward beneath it.
    GROUP[0] = f"{S}Shoulder"
    hull("pauldron", side(s, [
        (0.34, -0.2, 2.88), (0.34, 0.2, 2.88), (0.64, -0.2, 2.84), (0.64, 0.2, 2.84),
        (0.74, -0.15, 2.74), (0.74, 0.15, 2.74), (0.68, -0.18, 2.69), (0.68, 0.18, 2.69),
        (0.36, -0.18, 2.72), (0.36, 0.18, 2.72)]), VIOLET, bevel=0.008)
    hull("pauldron_inner", side(s, [  # inner wall down toward the chest, clear of the arm
        (0.3, -0.17, 2.86), (0.3, 0.17, 2.86), (0.34, -0.17, 2.86), (0.34, 0.17, 2.86),
        (0.3, -0.15, 2.63), (0.3, 0.15, 2.63), (0.33, -0.15, 2.63), (0.33, 0.15, 2.63)]), VIOLET_DARK)
    hull("pauldron_cap", side(s, [
        (0.36, -0.19, 2.88), (0.36, 0.19, 2.88), (0.62, -0.19, 2.85), (0.62, 0.19, 2.85),
        (0.38, -0.16, 2.92), (0.38, 0.16, 2.92), (0.58, -0.16, 2.9), (0.58, 0.16, 2.9)]), GREY)
    hull("pauldron_fin", side(s, [
        (0.62, -0.14, 2.84), (0.62, 0.14, 2.84), (0.84, -0.04, 2.76), (0.84, 0.06, 2.76),
        (0.68, -0.12, 2.74), (0.68, 0.12, 2.74)]), GREY)
    hull("pauldron_spike", side(s, [
        (0.69, -0.19, 2.72), (0.75, -0.19, 2.72), (0.69, -0.13, 2.72), (0.75, -0.13, 2.73),
        (0.72, -0.17, 2.5)]), CRYSTAL, bevel=0.003)
    text("pauldron_num", PALETTE["number"], (0.52 * s, -0.205, 2.79), (R90, 0, 0), 0.075, DECAL)
    tri_frame("pauldron_emblem", (0.5 * s, 0.0, 2.925), (0, 0, 1), (0, 1, 0), 0.05, 0.01, DECAL)
    tri_frame("pauldron_side_emblem", (0.715 * s, 0.0, 2.75), (0.6 * s, 0, 0.8), (-0.8 * s, 0, 0.6),
              0.04, 0.009, GLOW_BLUE)

    # Upper arm: ball joint at the shoulder, forks around the elbow hinge at the far end.
    GROUP[0] = f"{S}UpperArm"
    ball("shoulder_ball", P(f"{S}UpperArm"), 0.105)
    ring("shoulder_collar", (0.585 * s, 0, z), (1, 0, 0), 0.095, 0.02, GREY, seg=24)
    xtaper("upper_arm", 0.6 * s, 0.8 * s, 0, z, (0.085, 0.085), (0.075, 0.08), GUNMETAL)
    hull("upper_arm_plate", side(s, [
        (0.62, -0.07, z + 0.085), (0.62, 0.07, z + 0.085), (0.79, -0.06, z + 0.08), (0.79, 0.06, z + 0.08),
        (0.64, -0.06, z + 0.115), (0.64, 0.06, z + 0.115), (0.77, -0.05, z + 0.105), (0.77, 0.05, z + 0.105)]), GREY)
    hull("upper_arm_front", side(s, [
        (0.63, -0.085, z - 0.06), (0.78, -0.075, z - 0.06), (0.63, -0.085, z + 0.07), (0.78, -0.075, z + 0.07),
        (0.65, -0.105, z - 0.04), (0.76, -0.095, z - 0.04), (0.65, -0.105, z + 0.05), (0.76, -0.095, z + 0.05)]), GREY)
    for k, dz in enumerate((0.1, -0.1)):  # elbow fork: plates above and below the hinge
        hull(f"elbow_fork{k}", side(s, [
            (0.78, -0.07, z + dz - 0.015), (0.78, 0.07, z + dz - 0.015), (0.78, -0.07, z + dz + 0.015),
            (0.78, 0.07, z + dz + 0.015), (0.9, -0.06, z + dz - 0.015), (0.9, 0.06, z + dz - 0.015),
            (0.9, -0.06, z + dz + 0.015), (0.9, 0.06, z + dz + 0.015)]), GUNMETAL, bevel=0.004)
    ring("elbow_cap_ring", (0.86 * s, 0, z + 0.118), (0, 0, 1), 0.04, 0.008, GLOW_BLUE, seg=20)

    # Forearm: swings on the elbow hinge (vertical in the T-pose, so the elbow bends forward).
    GROUP[0] = f"{S}LowerArm"
    hinge("elbow_hinge", P(f"{S}LowerArm"), (0, 0, 1), 0.07, 0.17)
    xtaper("forearm", 0.92 * s, 1.24 * s, 0, z, (0.09, 0.09), (0.08, 0.08), GUNMETAL)
    hull("forearm_front", side(s, [
        (0.95, -0.09, z - 0.08), (1.22, -0.08, z - 0.07), (0.95, -0.09, z + 0.08), (1.22, -0.08, z + 0.07),
        (0.98, -0.135, z - 0.06), (1.19, -0.12, z - 0.05), (0.98, -0.135, z + 0.06), (1.19, -0.12, z + 0.05)]), GREY)
    hull("forearm_outer", side(s, [
        (0.95, -0.11, z + 0.09), (0.95, 0.12, z + 0.09), (1.23, -0.1, z + 0.08), (1.23, 0.1, z + 0.08),
        (0.99, -0.08, z + 0.15), (0.99, 0.09, z + 0.15), (1.2, -0.07, z + 0.135), (1.2, 0.07, z + 0.135)]),
        VIOLET, bevel=0.006)
    bar("forearm_glow", (1.0 * s, 0.0, z + 0.148), (1.18 * s, 0.0, z + 0.135), 0.028, (0, 0, 1), GLOW_BLUE)
    hull("forearm_back", side(s, [
        (0.97, 0.09, z - 0.07), (1.21, 0.08, z - 0.06), (0.97, 0.09, z + 0.07), (1.21, 0.08, z + 0.06),
        (1.0, 0.13, z - 0.05), (1.18, 0.12, z - 0.04), (1.0, 0.13, z + 0.05), (1.18, 0.12, z + 0.04)]), VIOLET_DARK)
    bar("forearm_back_glow", (1.02 * s, 0.134, z), (1.16 * s, 0.124, z), 0.02, (0, 1, 0), GLOW_PURPLE)
    cbox("wrist_cuff", (1.245 * s, 0, z), (0.05, 0.2, 0.2), VIOLET, ch=0.02, bevel=0.004)

    if s > 0:
        build_hand(s)
    else:
        build_cannon(s)


def build_hand(s):
    """Clawed left hand, palm down: a ball wrist, knuckle pin and three-segment fingers on hinges."""
    S = SIDE_NAME[s]
    z = SHOULDER_Z
    GROUP[0] = f"{S}Hand"
    ball("wrist_ball", P(f"{S}Hand"), 0.06)
    hull("palm", side(s, [
        (1.33, -0.075, z - 0.04), (1.33, 0.075, z - 0.04), (1.33, -0.075, z + 0.04), (1.33, 0.075, z + 0.04),
        (1.46, -0.085, z - 0.035), (1.46, 0.085, z - 0.035), (1.46, -0.085, z + 0.03), (1.46, 0.085, z + 0.03)]),
        GUNMETAL)
    hull("hand_plate", side(s, [
        (1.34, -0.07, z + 0.04), (1.34, 0.07, z + 0.04), (1.45, -0.08, z + 0.03), (1.45, 0.08, z + 0.03),
        (1.36, -0.05, z + 0.065), (1.36, 0.05, z + 0.065), (1.43, -0.06, z + 0.055), (1.43, 0.06, z + 0.055)]), VIOLET)
    hinge("knuckle_pin", (1.46 * s, 0, z - 0.01), (0, 1, 0), 0.022, 0.18)

    for i, y in enumerate((-0.065, -0.022, 0.021, 0.064)):
        p0 = Vector((1.46 * s, y, z - 0.01))
        p1 = p0 + Vector((0.06 * s, 0, -0.006))
        p2 = p1 + Vector((0.05 * s, 0, -0.012))
        p3 = p2 + Vector((0.065 * s, 0, -0.025))
        names = [f"{S}{FINGERS[i]}{seg}" for seg in ("Proximal", "Intermediate", "Distal")]
        GROUP[0] = names[0]
        rod("segment", p0, p1, 0.02, GUNMETAL, segs=8)
        GROUP[0] = names[1]
        hinge("knuckle", p1, (0, 1, 0), 0.017, 0.034, segs=10)
        rod("segment", p1, p2, 0.018, GUNMETAL, segs=8)
        GROUP[0] = names[2]
        hinge("knuckle", p2, (0, 1, 0), 0.016, 0.032, segs=10)
        rod("claw", p2, p3, 0.019, CRYSTAL, r1=0.0, segs=6)
        for name, a, b in zip(names, (p0, p1, p2), (p1, p2, p3)):
            FINGER_JOINTS[name] = (a, b)

    t0 = Vector((1.37 * s, -0.085, z - 0.03))
    t1 = t0 + Vector((0.05 * s, -0.05, -0.01))
    t2 = t1 + Vector((0.05 * s, -0.035, -0.02))
    GROUP[0] = f"{S}ThumbProximal"
    ball("thumb_joint", t0, 0.022)
    rod("segment", t0, t1, 0.02, GUNMETAL, segs=8)
    GROUP[0] = f"{S}ThumbDistal"
    hinge("knuckle", t1, (s, 1, 0), 0.017, 0.034, segs=10)  # across the thumb, so it curls down
    rod("claw", t1, t2, 0.019, CRYSTAL, r1=0.0, segs=6)
    FINGER_JOINTS[f"{S}ThumbProximal"] = (t0, t1)
    FINGER_JOINTS[f"{S}ThumbDistal"] = (t1, t2)


def build_cannon(s):
    """Right arm cannon in place of the hand: a ball wrist, a housing, a barrel ringed with
    glowing energy coils, and a muzzle, all along the arm's axis (-X in the T-pose)."""
    z = SHOULDER_Z
    GROUP[0] = "RightHand"
    ball("wrist_ball", P("RightHand"), 0.06)
    cbox("cannon_housing", (1.42 * s, 0, z), (0.22, 0.24, 0.22), VIOLET, ch=0.04, bevel=0.005)
    hull("cannon_top", side(s, [
        (1.33, -0.08, z + 0.11), (1.51, -0.08, z + 0.11), (1.33, 0.08, z + 0.11), (1.51, 0.08, z + 0.11),
        (1.35, -0.06, z + 0.135), (1.49, -0.06, z + 0.135), (1.35, 0.06, z + 0.135), (1.49, 0.06, z + 0.135)]), GREY)
    for k, y in enumerate((-0.122, 0.122)):
        bar(f"cannon_vent{k}", (1.35 * s, y, z), (1.49 * s, y, z), 0.03, (0, 1 if y > 0 else -1, 0), GLOW_BLUE)
    rod("barrel", (1.5 * s, 0, z), (1.84 * s, 0, z), 0.07, GUNMETAL, segs=14)
    for i, x in enumerate((1.6, 1.68, 1.76)):
        ring(f"coil{i}", (x * s, 0, z), (1, 0, 0), 0.078, 0.012, GLOW_PURPLE, seg=20)
    rod("muzzle", (1.82 * s, 0, z), (1.89 * s, 0, z), 0.09, JOINT, r1=0.1, segs=14)
    ring("muzzle_ring", (1.89 * s, 0, z), (1, 0, 0), 0.085, 0.012, GLOW_BLUE, seg=24)
    disc("muzzle_core", (1.892 * s, 0, z), (1, 0, 0), 0.06, 0.01, GLOW_PURPLE, segs=16)
    MUZZLE["head"] = Vector((1.9 * s, 0, z))
    MUZZLE["tail"] = Vector((2.02 * s, 0, z))


# --- Legs --------------------------------------------------------------------

def build_leg(s):
    S = SIDE_NAME[s]

    # Thigh: ball joint at the hip with a rotary cover outside it; forks around the knee hinge.
    GROUP[0] = f"{S}UpperLeg"
    ball("hip_ball", P(f"{S}UpperLeg"), 0.11)
    disc("hip_drum", (0.335 * s, 0, 1.82), (1, 0, 0), 0.11, 0.06, GUNMETAL, segs=20)
    disc("hip_hub", (0.37 * s, 0, 1.82), (1, 0, 0), 0.06, 0.02, GREY, segs=16)
    taper("thigh_core", (0.21 * s, 0.0, 1.74), (0.2, 0.24), (0.255 * s, 0.0, 1.42), (0.17, 0.2), GUNMETAL)
    hull("thigh_plate", side(s, [
        (0.12, -0.12, 1.68), (0.31, -0.12, 1.68), (0.13, -0.19, 1.64), (0.3, -0.19, 1.64),
        (0.18, -0.11, 1.42), (0.33, -0.11, 1.42), (0.19, -0.165, 1.45), (0.32, -0.165, 1.45)]), GREY)
    hull("thigh_side", side(s, [
        (0.31, -0.1, 1.7), (0.31, 0.12, 1.7), (0.36, -0.08, 1.66), (0.36, 0.1, 1.66),
        (0.36, -0.07, 1.46), (0.36, 0.08, 1.46), (0.33, -0.08, 1.43), (0.33, 0.1, 1.43)]), VIOLET)
    bar("thigh_glow", (0.364 * s, 0.0, 1.64), (0.364 * s, 0.0, 1.5), 0.025, (s, 0, 0), GLOW_BLUE)
    hull("thigh_back", side(s, [
        (0.13, 0.1, 1.7), (0.3, 0.1, 1.7), (0.15, 0.16, 1.65), (0.3, 0.16, 1.65),
        (0.19, 0.08, 1.43), (0.32, 0.08, 1.43), (0.2, 0.13, 1.48), (0.32, 0.13, 1.48)]), VIOLET_DARK)
    for k, x in enumerate((0.165, 0.375)):  # knee fork: plates either side of the hinge
        hull(f"knee_fork{k}", side(s, [
            (x - 0.012, -0.07, 1.44), (x + 0.012, -0.07, 1.44), (x - 0.012, 0.07, 1.44), (x + 0.012, 0.07, 1.44),
            (x - 0.012, -0.055, 1.27), (x + 0.012, -0.055, 1.27), (x - 0.012, 0.055, 1.27), (x + 0.012, 0.055, 1.27)]),
            GUNMETAL, bevel=0.003)

    # Shin: swings on the knee hinge; the knee cap rides with it.
    GROUP[0] = f"{S}LowerLeg"
    knee = P(f"{S}LowerLeg")
    hinge("knee_hinge", knee, (1, 0, 0), 0.075, 0.19)
    disc("knee_hub", (0.394 * s, 0, 1.3), (1, 0, 0), 0.05, 0.02, GREY)
    ring("knee_ring", (0.405 * s, 0, 1.3), (1, 0, 0), 0.055, 0.011, GLOW_BLUE)
    hull("knee_cap", side(s, [
        (0.2, -0.1, 1.38), (0.34, -0.1, 1.38), (0.27, -0.2, 1.31), (0.2, -0.12, 1.2),
        (0.34, -0.12, 1.2), (0.27, -0.165, 1.15), (0.21, -0.06, 1.37), (0.33, -0.06, 1.37)]), GREY)
    taper("shin_core", (0.28 * s, 0.0, 1.22), (0.2, 0.24), (0.31 * s, 0.02, 0.6), (0.16, 0.2), GUNMETAL)
    hull("shin_plate", side(s, [
        (0.19, -0.1, 1.12), (0.37, -0.1, 1.12), (0.19, -0.155, 1.12), (0.37, -0.155, 1.12),
        (0.18, -0.1, 0.95), (0.39, -0.1, 0.95), (0.18, -0.155, 0.95), (0.39, -0.155, 0.95),
        (0.23, -0.1, 0.68), (0.35, -0.1, 0.68), (0.24, -0.15, 0.68), (0.34, -0.15, 0.68),
        (0.285, -0.18, 1.06), (0.285, -0.18, 0.9)]), GREY)
    for i, zz in enumerate((0.98, 0.78)):
        bar(f"shin_glow{i}", (0.285 * s, -0.178, zz), (0.285 * s, -0.17, zz - 0.07), 0.02, (0, -1, 0), GLOW_PURPLE)
    hull("calf", side(s, [
        (0.2, 0.08, 1.15), (0.37, 0.08, 1.15), (0.22, 0.2, 1.05), (0.36, 0.2, 1.05),
        (0.23, 0.17, 0.72), (0.35, 0.17, 0.72), (0.24, 0.08, 0.65), (0.35, 0.08, 0.65)]), VIOLET)
    bar("calf_glow", (0.29 * s, 0.2, 1.03), (0.29 * s, 0.172, 0.76), 0.03, (0, 1, 0.05), GLOW_BLUE)
    bar("shin_side_glow", (0.385 * s, -0.04, 1.06), (0.38 * s, -0.04, 0.8), 0.02, (s, 0, 0), GLOW_PURPLE)
    cbox("ankle_cuff", (0.31 * s, 0.01, 0.62), (0.26, 0.28, 0.15), VIOLET, ch=0.04, bevel=0.005)
    bar("ankle_glow", (0.31 * s, -0.132, 0.66), (0.31 * s, -0.132, 0.59), 0.03, (0, -1, 0), GLOW_PURPLE)

    # Foot: ball joint at the ankle; the toes hinge at the front.
    GROUP[0] = f"{S}Foot"
    ball("ankle_ball", P(f"{S}Foot"), 0.08)
    fx = 0.31 * s
    rod("ankle_socket", (fx, 0, 0.36), (fx, 0, 0.465), 0.1, GUNMETAL, r1=0.085, segs=16)  # cup the ball sits in
    hull("foot_body", side(s, [
        (0.17, -0.2, 0.03), (0.45, -0.2, 0.03), (0.17, 0.16, 0.03), (0.45, 0.16, 0.03),
        (0.2, -0.21, 0.16), (0.42, -0.21, 0.16),
        (0.21, -0.1, 0.38), (0.41, -0.1, 0.38), (0.21, 0.1, 0.38), (0.41, 0.1, 0.38)]), GUNMETAL)
    hull("foot_top", side(s, [
        (0.23, -0.19, 0.2), (0.39, -0.19, 0.2), (0.24, -0.1, 0.38), (0.38, -0.1, 0.38),
        (0.23, -0.17, 0.17), (0.39, -0.17, 0.17), (0.24, -0.07, 0.35), (0.38, -0.07, 0.35)]), GREY)
    bar("foot_glow", (fx, -0.17, 0.25), (fx, -0.12, 0.33), 0.025, (0, -0.8, 0.6), GLOW_PURPLE)
    for k, x0 in enumerate((0.45, 0.17)):
        out = 1 if k == 0 else -1
        hull(f"foot_side{k}", side(s, [
            (x0, -0.17, 0.06), (x0, 0.12, 0.06), (x0, -0.1, 0.3), (x0, 0.08, 0.3),
            (x0 + 0.04 * out, -0.14, 0.08), (x0 + 0.04 * out, 0.1, 0.08),
            (x0 + 0.04 * out, -0.08, 0.24), (x0 + 0.04 * out, 0.06, 0.24)]), VIOLET)
        bar(f"foot_side_glow{k}", ((x0 + 0.042 * out) * s, -0.08, 0.16), ((x0 + 0.042 * out) * s, 0.05, 0.16),
            0.025, (out * s, 0, 0), GLOW_PURPLE if k == 0 else GLOW_BLUE)
    # Block heel at the back of the foot.
    cbox("heel_block", (fx, 0.2, 0.08), (0.3, 0.1, 0.15), GUNMETAL, ch=0.025, bevel=0.004)
    cbox("heel_cap", (fx, 0.22, 0.165), (0.26, 0.08, 0.03), VIOLET, ch=0.01)
    bar("heel_glow", (fx - 0.09 * s, 0.252, 0.08), (fx + 0.09 * s, 0.252, 0.08), 0.025, (0, 1, 0), GLOW_BLUE)

    # Block toe cap, hinged at the front of the foot.
    GROUP[0] = f"{S}Toes"
    hinge("toe_hinge", P(f"{S}Toes"), (1, 0, 0), 0.05, 0.27)
    cbox("toe_block", (fx, -0.335, 0.08), (0.3, 0.22, 0.15), GUNMETAL, ch=0.03, bevel=0.004)
    hull("toe_plate", side(s, [
        (0.18, -0.25, 0.155), (0.44, -0.25, 0.155), (0.19, -0.42, 0.135), (0.43, -0.42, 0.135),
        (0.2, -0.26, 0.18), (0.42, -0.26, 0.18), (0.21, -0.4, 0.16), (0.41, -0.4, 0.16)]), GREY)
    cbox("toe_bumper", (fx, -0.45, 0.07), (0.28, 0.03, 0.1), VIOLET, ch=0.01)
    bar("toe_glow", (fx - 0.1 * s, -0.467, 0.07), (fx + 0.1 * s, -0.467, 0.07), 0.025, (0, -1, 0), GLOW_PURPLE)


# --- Assemble --------------------------------------------------------------

build_torso()
for _s in (1, -1):
    build_arm(_s)
    build_leg(_s)

# Bones: (name, parent, head, tail). Every head is a joint pivot.
BONES = [("Root", None, P("Root"), (0, 0, 0.3)),
         ("Hips", "Root", P("Hips"), P("Spine")),
         ("Spine", "Hips", P("Spine"), P("Chest")),
         ("Chest", "Spine", P("Chest"), (0, 0, 2.66)),
         ("Neck", "Chest", P("Neck"), P("Head")),
         ("Head", "Neck", P("Head"), (0, -0.03, 3.0)),
         ("Backpack", "Chest", P("Backpack"), (0, 0.5, 1.6))]
for _s, S in SIDE_NAME.items():
    BONES += [(f"{S}Shoulder", "Chest", P(f"{S}Shoulder"), P(f"{S}UpperArm")),
              (f"{S}UpperArm", f"{S}Shoulder", P(f"{S}UpperArm"), P(f"{S}LowerArm")),
              (f"{S}LowerArm", f"{S}UpperArm", P(f"{S}LowerArm"), P(f"{S}Hand")),
              (f"{S}Hand", f"{S}LowerArm", P(f"{S}Hand"), (1.46 * _s, 0, SHOULDER_Z))]
    if _s < 0:  # the arm cannon: no fingers, a muzzle bone for the game to fire from
        BONES.append(("RightMuzzle", "RightHand", MUZZLE["head"], MUZZLE["tail"]))
    for f in FINGERS + ("Thumb",):
        parent = f"{S}Hand"
        for seg in ("Proximal", "Intermediate", "Distal"):
            name = f"{S}{f}{seg}"
            if name in FINGER_JOINTS:
                BONES.append((name, parent, *FINGER_JOINTS[name]))
                parent = name
    BONES += [(f"{S}UpperLeg", "Hips", P(f"{S}UpperLeg"), P(f"{S}LowerLeg")),
              (f"{S}LowerLeg", f"{S}UpperLeg", P(f"{S}LowerLeg"), P(f"{S}Foot")),
              (f"{S}Foot", f"{S}LowerLeg", P(f"{S}Foot"), P(f"{S}Toes")),
              (f"{S}Toes", f"{S}Foot", P(f"{S}Toes"), (0.32 * _s, -0.48, 0.04))]

rig_data = bpy.data.armatures.new(f"{TITLE}_rig")
rig_data.display_type = "STICK"
rig = bpy.data.objects.new(TITLE, rig_data)
rig.show_in_front = True
COL.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for name, parent, head, tail in BONES:
    eb = rig_data.edit_bones.new(name)
    eb.head, eb.tail = Vector(head), Vector(tail)
    if parent:
        eb.parent = rig_data.edit_bones[parent]
bpy.ops.object.mode_set(mode="OBJECT")

# One part object per bone: join that bone's pieces, put the origin on the joint, parent to the bone.
heads = {name: Vector(head) for name, _, head, _ in BONES}
part_objs = {}
for bone, objs in PARTS.items():
    assert bone in heads, bone
    if len(objs) > 1:
        with bpy.context.temp_override(active_object=objs[0], object=objs[0],
                                       selected_objects=objs, selected_editable_objects=objs):
            bpy.ops.object.join()
    obj = objs[0]
    obj.name = obj.data.name = f"{bone}_Part"
    obj.data.transform(Matrix.Translation(-heads[bone]))
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = bone
    part_objs[bone] = obj
bpy.context.view_layer.update()
for bone, obj in part_objs.items():
    obj.matrix_world = Matrix.Translation(heads[bone])

tris = sum(len(p.vertices) - 2 for o in part_objs.values() for p in o.data.polygons)
print(f"{TITLE}: {len(BONES)} bones, {len(part_objs)} parts, ~{tris} triangles")


# --- Animations ------------------------------------------------------------
# Looping clips for the game: Idle, Run, Fly (moving through the air), Hover (holding
# position in the air) and Cruise (lock-in dive).
# Rotations are given about the rest-pose world axes (X = the mech's left,
# -Y = forward, Z = up) and converted to each bone's local space, so:
#   legs/arms swing about X (negative = forward), knees bend +X, toes point +X,
#   arms lower about Y (handled per side), spine leans forward +X, twist about Z.
# Root, Backpack and RightMuzzle are never keyed: the game drives the back plates and aims the cannon.

X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
FPS = 30
KEYED = [b[0] for b in BONES if b[0] not in ("Root", "Backpack", "RightMuzzle")]


def local_quat(bone, rots):
    q = Quaternion()
    for axis, deg in rots:
        q = Quaternion(Vector(axis), math.radians(deg)) @ q
    B = rig_data.bones[bone].matrix_local.to_3x3()
    return (B.inverted() @ q.to_matrix() @ B).to_quaternion()


def arm(pose, s, lower, swing=0.0, elbow=0.0, curl=0.0):
    S = SIDE_NAME[s]
    pose[f"{S}UpperArm"] = [(Y, lower * s), (X, swing)]
    pose[f"{S}LowerArm"] = [(Z, -elbow * s)]
    for f in FINGERS + ("Thumb",):
        for seg in ("Proximal", "Intermediate", "Distal"):
            pose[f"{S}{f}{seg}"] = [(Y, curl * s)]


def leg(pose, s, thigh, knee, foot=0.0):
    S = SIDE_NAME[s]
    pose[f"{S}UpperLeg"] = [(X, thigh)]
    pose[f"{S}LowerLeg"] = [(X, knee)]
    pose[f"{S}Foot"] = [(X, foot)]


def torso(pose, lean=0.0, twist=0.0, hip_twist=0.0, head_nod=0.0, head_turn=0.0, lift=0.0):
    pose["Spine"] = [(X, lean)]
    pose["Chest"] = [(Z, twist)]
    pose["Hips"] = [(Z, hip_twist)]
    pose["Head"] = [(X, head_nod), (Z, head_turn)]
    pose["lift"] = lift


def apply_pose(pose):
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = local_quat(pb.name, pose.get(pb.name, []))
    rig.pose.bones["Hips"].location = (rig_data.bones["Hips"].matrix_local.to_3x3().inverted()
                                       @ Vector((0, 0, pose.get("lift", 0.0))))


def make_action(name, length, keys):
    """keys: [(frame, pose)]. The first pose is repeated at `length` to close the loop."""
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    hips_rest = rig_data.bones["Hips"].matrix_local.to_3x3().inverted()
    for frame, pose in keys + [(length, keys[0][1])]:
        for bone in KEYED:
            pb = rig.pose.bones[bone]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = local_quat(bone, pose.get(bone, []))
            pb.keyframe_insert("rotation_quaternion", frame=frame, group=bone)
        hips = rig.pose.bones["Hips"]
        hips.location = hips_rest @ Vector((0, 0, pose.get("lift", 0.0)))
        hips.keyframe_insert("location", frame=frame, group="Hips")
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 0, action)
    track.mute = True
    rig.animation_data.action = None
    return action


def idle_pose(t):
    p = {}
    for s in (1, -1):
        arm(p, s, lower=72 + 2 * t, swing=-5, elbow=15 + 3 * t, curl=18)
        leg(p, s, thigh=-3, knee=6 + 2 * t, foot=-3)
    torso(p, lean=2 + 2 * t, head_turn=-4 + 8 * t, lift=-0.015 * t)
    return p


# Run cycle, left leg phase: contact, mid-stance, toe-off, swing. Right leg is half a cycle later.
RUN_LEG = [(-35, 12, -15), (-5, 35, 5), (30, 25, 10), (-15, 75, 5)]
RUN_LIFT = [0.02, -0.06, 0.02, -0.06]


def run_pose(i):
    p = {}
    for s, offset in ((1, 0), (-1, 2)):
        leg(p, s, *RUN_LEG[(i + offset) % 4])
        swing = (25, 0, -25, 0)[(i + offset) % 4]  # each arm swings opposite its own leg
        arm(p, s, lower=75, swing=swing, elbow=75, curl=30)
    twist = (8, 0, -8, 0)[i]
    torso(p, lean=14, twist=twist, hip_twist=-0.75 * twist, head_turn=-twist, lift=RUN_LIFT[i])
    return p


def fly_pose(t):
    p = {}
    leg(p, 1, thigh=-12 + 6 * t, knee=30 + 10 * t, foot=35)
    leg(p, -1, thigh=-4 - 6 * t, knee=45 - 10 * t, foot=30)
    for s in (1, -1):
        arm(p, s, lower=55 - 5 * t, swing=-10, elbow=30, curl=25)
    torso(p, lean=6, head_nod=-5, lift=0.04 * t)
    return p


def hover_pose(t):
    """Holding position in the air: legs together and pointed, arms out balancing, slow bob."""
    p = {}
    leg(p, 1, thigh=-4, knee=10 + 6 * t, foot=30)
    leg(p, -1, thigh=2, knee=22 - 6 * t, foot=35)
    for s in (1, -1):
        arm(p, s, lower=60 - 6 * t, swing=-8, elbow=20 + 4 * t, curl=8)
    torso(p, lean=3, twist=-2 + 4 * t, head_nod=-3, lift=0.05 * t)
    return p


def cruise_pose(t):
    p = {}
    for s in (1, -1):
        leg(p, s, thigh=8 + 2 * t * s, knee=12 + 3 * t, foot=40)
        arm(p, s, lower=80, swing=30 + 3 * t, elbow=5, curl=35)
    torso(p, lean=-5, head_nod=-35)
    p["Neck"] = [(X, -15)]
    return p


scene.render.fps = FPS
rig.animation_data_create()
ANIMS = {
    "Idle": make_action("Idle", 90, [(0, idle_pose(0)), (45, idle_pose(1))]),
    "Run": make_action("Run", 20, [(5 * i, run_pose(i)) for i in range(4)]),
    "Fly": make_action("Fly", 60, [(0, fly_pose(0)), (30, fly_pose(1))]),
    "Hover": make_action("Hover", 90, [(0, hover_pose(0)), (45, hover_pose(1))]),
    "Cruise": make_action("Cruise", 30, [(0, cruise_pose(0)), (15, cruise_pose(1))]),
}
scene.frame_start, scene.frame_end = 0, 90
print(f"{TITLE}: animations {list(ANIMS)}")


# --- Preview renders, save, export -----------------------------------------

def setup_render():
    world = bpy.data.worlds.new("World")
    scene.world = world
    if world.node_tree is None:
        world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.32, 0.32, 0.33, 1)
    bg.inputs["Strength"].default_value = 0.8
    for name, kind, energy, rot in (("key", "SUN", 3.5, (50, 0, -35)), ("fill", "SUN", 1.2, (60, 0, 140)),
                                    ("rim", "SUN", 2.0, (110, 0, 180))):
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        lo = bpy.data.objects.new(name, ld)
        lo.rotation_euler = [math.radians(a) for a in rot]
        COL.objects.link(lo)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 4.4
    cam = bpy.data.objects.new("cam", cam_data)
    COL.objects.link(cam)
    scene.camera = cam
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            pass
    scene.render.resolution_x, scene.render.resolution_y = 960, 960
    try:
        scene.view_settings.look = "AgX - Punchy"
    except TypeError:
        pass
    return cam


VIEWS = {"front": ((0, -10, 1.62), (90, 0, 0)), "side": ((10, 0, 1.62), (90, 0, 90)),
         "back": ((0, 10, 1.62), (90, 0, 180)), "three_quarter": ((-7, -7, 1.62), (90, 0, -45))}


def render(label, view):
    cam.location = VIEWS[view][0]
    cam.rotation_euler = [math.radians(a) for a in VIEWS[view][1]]
    scene.render.filepath = os.path.join(RENDER_DIR, f"{label}.png")
    bpy.ops.render.render(write_still=True)


if RENDER_DIR:
    os.makedirs(RENDER_DIR, exist_ok=True)
    cam = setup_render()
    apply_pose({})  # rest (T-pose); building the clips leaves the last keyframe applied
    for view in VIEWS:
        render(view, view)
    # Head close-ups (visor detail).
    cam.data.ortho_scale = 0.7
    for label, loc, rot in (("head_front", (0, -10, 2.87), (90, 0, 0)), ("head_three_quarter", (-7, -7, 2.87), (90, 0, -45)),
                            ("head_side", (10, 0, 2.87), (90, 0, 90))):
        cam.location = loc
        cam.rotation_euler = [math.radians(a) for a in rot]
        scene.render.filepath = os.path.join(RENDER_DIR, f"{label}.png")
        bpy.ops.render.render(write_still=True)
    cam.data.ortho_scale = 4.4
    # Joint check: aim the cannon forward, bend an elbow, knee and fingers, flare the back plates.
    test = {}
    arm(test, 1, lower=40, swing=-30, elbow=90, curl=40)
    test["RightUpperArm"] = [(Z, 90)]            # cannon arm swung forward to aim
    leg(test, 1, thigh=-45, knee=80, foot=-20)
    leg(test, -1, thigh=20, knee=40, foot=25)
    torso(test, lean=8, twist=10, head_turn=25)
    test["Backpack"] = [(X, 25)]
    test["LeftToes"] = [(X, -25)]
    apply_pose(test)
    render("pose_test_three_quarter", "three_quarter")
    render("pose_test_side", "side")
    render("pose_test_front", "front")
    # Animation check: a few frames of each clip.
    for anim, frame, view in [("Idle", 0, "three_quarter"), ("Run", 0, "side"), ("Run", 5, "three_quarter"),
                              ("Hover", 0, "three_quarter"), ("Cruise", 0, "side")]:
        rig.animation_data.action = ANIMS[anim]
        scene.frame_set(frame)
        render(f"anim_{anim}_{frame}_{view}", view)
    rig.animation_data.action = None

# Leave the file in rest pose with nothing playing.
for pb in rig.pose.bones:
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.location = (0, 0, 0)
scene.frame_set(0)

if OUT_BLEND:
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
if OUT_GLB:
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", export_apply=True)
print(f"{TITLE}: done")
