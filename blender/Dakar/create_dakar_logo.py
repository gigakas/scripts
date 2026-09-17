"""Create the supplied Dakar SVG as editable, extruded Bezier curves."""
import math
import re
import xml.etree.ElementTree as ET
from pathlib import Path

import bpy
from mathutils import Vector

DIRECTORY = Path(__file__).resolve().parent
SVG = DIRECTORY / 'dakar_logo.svg'
OUTPUT = DIRECTORY / 'dakar_logo_3d.blend'
SCALE = 0.045


def parse_path(data):
    """Preserve straight and cubic SVG segments as exact Bezier handles."""
    tokens = re.findall(r'[a-zA-Z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?', data)
    contours, points = [], []
    pos = (0.0, 0.0)
    previous_control = None
    command = None
    previous_command = None
    i = 0

    def new_point(p, incoming=None):
        return {'p': p, 'left': p if incoming is None else incoming, 'right': p}

    def finish():
        nonlocal points
        if not points:
            return
        if len(points) > 1 and math.dist(points[0]['p'], points[-1]['p']) < 1e-7:
            points[0]['left'] = points[-1]['left']
            points.pop()
        if len(points) >= 2:
            contours.append(points)
        points = []

    while i < len(tokens):
        if tokens[i].isalpha():
            command = tokens[i]
            i += 1
        assert command is not None
        upper = command.upper()
        relative = command.islower()
        if upper == 'Z':
            pos = points[0]['p']
            finish()
            previous_command = 'Z'
            previous_control = None
            command = None
            continue
        arity = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6, 'S': 4}[upper]
        args = list(map(float, tokens[i:i + arity]))
        i += arity

        def absolute(x, y):
            return (x + pos[0], y + pos[1]) if relative else (x, y)

        if upper == 'M':
            finish()
            pos = absolute(*args)
            points.append(new_point(pos))
            command = 'l' if relative else 'L'
        elif upper in {'L', 'H', 'V'}:
            if upper == 'L':
                end = absolute(*args)
            elif upper == 'H':
                end = (args[0] + (pos[0] if relative else 0), pos[1])
            else:
                end = (pos[0], args[0] + (pos[1] if relative else 0))
            points.append(new_point(end))
            pos = end
        else:
            if upper == 'C':
                c1, c2, end = absolute(*args[:2]), absolute(*args[2:4]), absolute(*args[4:])
            else:
                c1 = tuple(2 * pos[k] - previous_control[k] for k in range(2)) if previous_command in {'C', 'S'} else pos
                c2, end = absolute(*args[:2]), absolute(*args[2:])
            points[-1]['right'] = c1
            points.append(new_point(end, c2))
            previous_control = c2
            pos = end
        previous_command = upper
        if upper not in {'C', 'S'}:
            previous_control = None
    finish()
    return contours


def svg_shapes(element, inherited='#3C6583', subtitle=False):
    fill = element.get('fill', inherited)
    subtitle = subtitle or element.get('id') == 'software-systems'
    kind = element.tag.split('}')[-1]
    if kind == 'path':
        yield fill, subtitle, element.get('id'), parse_path(element.attrib['d'])
    elif kind == 'polygon':
        values = list(map(float, re.findall(r'[-+]?\d*\.?\d+', element.attrib['points'])))
        coords = list(zip(values[::2], values[1::2]))
        yield fill, subtitle, None, [[{'p': p, 'left': p, 'right': p} for p in coords]]
    for child in element:
        yield from svg_shapes(child, fill, subtitle)


def linear(v):
    return v / 12.92 if v < 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def material(name, hex_color, metal=0.0, rough=0.35):
    color = tuple(linear(int(hex_color[k:k + 2], 16) / 255) for k in [1, 3, 5])
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    node = mat.node_tree.nodes['Principled BSDF']
    node.inputs['Base Color'].default_value = (*color, 1)
    node.inputs['Metallic'].default_value = metal
    node.inputs['Roughness'].default_value = rough
    node.inputs['Coat Weight'].default_value = 0.15
    node.inputs['Coat Roughness'].default_value = 0.25
    mat['SVG sRGB'] = hex_color
    return mat


def collection(name):
    col = bpy.data.collections.new(name)
    scene.collection.children.link(col)
    return col


def move(obj, name, col):
    obj.name = name
    if obj.data is not None:
        obj.data.name = name + ' | Data'
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    col.objects.link(obj)
    return obj


def box(name, location, size, mat, rounding, col):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = move(bpy.context.object, name, col)
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    mod = obj.modifiers.new('Soft bevel', 'BEVEL')
    mod.width, mod.segments = rounding, 5
    obj.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
    return obj


bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.name = 'DAKAR | 3D Vector Logo'
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1
logo_collection = collection('01 | Logo - Original Curves')
tag_collection = collection('02 | SOFTWARE SYSTEMS - Original Paths')
support = collection('03 | Panel and Base')
studio = collection('04 | Lighting and Cameras')
root = bpy.data.objects.new('DAKAR | Complete Logo', None)
logo_collection.objects.link(root)
root['source'] = 'Supplied SVG; original Bezier paths preserved without replacing typography'
root['width_m'] = 147.94 * SCALE
root['colors'] = '#3C6583 / #56B547 / #C12426'
materials = {
    '#3C6583': material('Brand | Blue #3C6583', '#3C6583', 0.18, 0.32),
    '#56B547': material('Brand | Green #56B547', '#56B547', 0.05, 0.30),
    '#C12426': material('Brand | Red #C12426', '#C12426', 0.05, 0.30),
}


def transform(p):
    return ((p[0] - 147.94 / 2) * SCALE, (60.11 - p[1]) * SCALE + 0.44, 0)


shapes = list(svg_shapes(ET.parse(SVG).getroot()))
assert len(shapes) == 43, f'Unexpected path count: {len(shapes)}'
for index, (color, subtitle, ident, contours) in enumerate(shapes):
    name = ('Tagline' if subtitle else 'Stripe') + f' | {index + 1:02d}'
    if color == '#56B547':
        name = 'Emblem | Green Leaf'
    elif color == '#C12426':
        name = 'Emblem | Red Leaf'
    elif ident == 'registered':
        name = 'Registered Trademark | R'
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '2D'
    curve.resolution_u = 16
    curve.render_resolution_u = 24
    curve.fill_mode = 'BOTH'
    small = subtitle or ident == 'registered'
    curve.extrude = 0.020 if small else (0.115 if color != '#3C6583' else 0.080)
    curve.bevel_depth = 0.0009 if small else 0.003
    curve.bevel_resolution = 3
    for contour in contours:
        spline = curve.splines.new('BEZIER')
        spline.bezier_points.add(len(contour) - 1)
        spline.use_cyclic_u = True
        for target, source in zip(spline.bezier_points, contour):
            target.handle_left_type = 'FREE'
            target.handle_right_type = 'FREE'
            target.co = transform(source['p'])
            target.handle_left = transform(source['left'])
            target.handle_right = transform(source['right'])
    obj = bpy.data.objects.new(name, curve)
    (tag_collection if subtitle else logo_collection).objects.link(obj)
    obj.rotation_euler = (math.pi / 2, 0, 0)
    obj.location.y = -0.045 if small else -0.100
    obj.parent = root
    curve.materials.append(materials[color])
    obj['SVG shape index'] = index
    obj['SVG color'] = color

porcelain = material('Support | Matte Porcelain', '#E9ECEB', 0.04, 0.58)
graphite = material('Support | Graphite', '#26353D', 0.55, 0.31)
ground = material('Studio | Gray Background', '#9AA7AD', 0, 0.80)
box('Panel | Logo Backing', (0, 0.18, 1.82), (7.32, 0.30, 3.24), porcelain, 0.075, support)
box('Base | Graphite Plinth', (0, 0.19, 0.105), (7.65, 1.12, 0.21), graphite, 0.06, support)
bpy.ops.mesh.primitive_plane_add(size=200)
floor = move(bpy.context.object, 'Studio | Floor', studio)
floor.location.z = -0.01
floor.data.materials.append(ground)
world = bpy.data.worlds.new('Studio | Ambient World')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.7, 0.78, 0.85, 1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.35
scene.world = world


def light(name, loc, power, size, color):
    bpy.ops.object.light_add(type='AREA', location=loc)
    obj = move(bpy.context.object, name, studio)
    obj.data.energy, obj.data.size = power, size
    obj.data.shape = 'DISK'
    obj.data.color = color
    obj.rotation_euler = (Vector((0, 0, 1.6)) - obj.location).to_track_quat('-Z', 'Y').to_euler()


light('Light | Key', (-4, -6, 8), 1500, 5, (1, 0.95, 0.88))
light('Light | Fill', (5, -3, 5), 950, 4, (0.82, 0.9, 1))
light('Light | Rim', (0, 4, 7), 1600, 4, (1, 1, 1))


def camera(name, position, target, scale):
    bpy.ops.object.camera_add(location=position)
    obj = move(bpy.context.object, name, studio)
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    obj.data.type = 'ORTHO'
    obj.data.ortho_scale = scale
    return obj


scene.camera = camera('Camera | 3D Presentation', (4.0, -16, 6.3), (0, 0, 1.72), 9.2)
camera('Camera | SVG Front View', (0, -20, 1.77), (0, 0, 1.77), 8.4)
scene.render.engine = 'CYCLES'
scene.cycles.samples = 64
scene.cycles.use_denoising = True
scene.render.resolution_x = 1600
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = 'AgX'
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = str(DIRECTORY / 'dakar_logo_3d_preview.png')
scene['Original SVG'] = SVG.name
scene['Editable shapes'] = len(shapes)
scene['Description'] = '3D logo with original SVG outlines, minimal bevels, brand sRGB materials and vector tagline.'
# Keep a portable copy of the cleaned SVG inside the blend file.
text = bpy.data.texts.new('SOURCE | dakar_logo.svg')
text.write(SVG.read_text())
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            area.spaces.active.region_3d.view_perspective = 'CAMERA'
            area.spaces.active.shading.type = 'MATERIAL'
bpy.ops.object.select_all(action='DESELECT')
root.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
bpy.ops.render.render(write_still=True)
print(f'CREATED: {OUTPUT}; original shapes: {len(shapes)}')
