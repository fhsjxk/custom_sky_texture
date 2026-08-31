import bpy
import gpu

import os

bl_info = {
    "name": "Custom Sky Texture",
    "description": "A custom sky texture with improved daytime appearance",
    "author": "03ff",
    "version": (0, 9, 1),
    "blender": (5, 1, 0),
    "location": "Shader Editor > Add Menu",
    "category": "Node",
}

DEBUG = False

SKYVIEW_WIDTH = 1024
SKYVIEW_HEIGHT = 1024

GPU_RESOURCES = {}

addon_dir = os.path.dirname(os.path.abspath(__file__))

with open(os.path.join(addon_dir, "atmosphere.glsl"), mode="r") as source:
    compute_shader_source = source.read()

def debug(message):
    if DEBUG:
        print(message)
    else:
        return

def genrate_id():
    debug("genrate_id")
    id = 0
    while id in GPU_RESOURCES:
        id += 1
    return id

class ShaderNodeTexSkyCustom(bpy.types.ShaderNodeCustomGroup):
    bl_label = "Custom Sky Texture"
    bl_icon = "NONE"

    sun_elevation: bpy.props.FloatProperty(
            name="Sun Elevation",
            default=40.0,
            update=lambda self, context: self.update_texture(),
        )

    sun_rotation: bpy.props.FloatProperty(
            name="Sun Rotation",
            default=0.0,
            update=lambda self, context: self.update_texture(),
        )

    altitude: bpy.props.FloatProperty(
            name="Altitude",
            default=100.0,
            min=0.0,
            update=lambda self, context: self.update_texture(),
        )
    
    air: bpy.props.FloatProperty(
            name="Air",
            default=1.0,
            min=0.0,
            update=lambda self, context: self.update_texture(),
        )

    aerosols: bpy.props.FloatProperty(
            name="Aerosols",
            default=1.0,
            min=0.0,
            update=lambda self, context: self.update_texture(),
        )

    ozone: bpy.props.FloatProperty(
            name="Ozone",
            default=1.0,
            min=0.0,
            update=lambda self, context: self.update_texture(),
        )

    scatter_muti: bpy.props.FloatProperty(
            name="Multiple Scattering",
            default=1.0,
            min=0.0,
            max=2.0,
            update=lambda self, context: self.update_texture(),
        )

    id: bpy.props.IntProperty(
            name="Id",
        )

    def create_gpu_resources(self):
        debug("create_gpu_resources")
        texture_skyview = gpu.types.GPUTexture((SKYVIEW_WIDTH, SKYVIEW_HEIGHT), format="RGBA32F")

        compute_shader_info = gpu.types.GPUShaderCreateInfo()
        compute_shader_info.image(0, "RGBA32F", "FLOAT_2D", "img_output", qualifiers={"WRITE"})
        compute_shader_info.compute_source(compute_shader_source)

        compute_shader_info.push_constant("FLOAT", "sun_elevation")
        compute_shader_info.push_constant("FLOAT", "sun_rotation")
        compute_shader_info.push_constant("FLOAT", "altitude")
        compute_shader_info.push_constant("FLOAT", "air")
        compute_shader_info.push_constant("FLOAT", "aerosols")
        compute_shader_info.push_constant("FLOAT", "ozone")
        compute_shader_info.push_constant("FLOAT", "scatter_muti")

        compute_shader_info.local_group_size(8, 8)
        compute_shader = gpu.shader.create_from_info(compute_shader_info)

        return texture_skyview, compute_shader

    def create_image(self):
        debug("create_image")
        image = bpy.data.images.new(
            name=f"ImageTexSkyCustom_{self.id}",
            width=SKYVIEW_WIDTH,
            height=SKYVIEW_HEIGHT,
            alpha=False,
            float_buffer=True,
            stereo3d=False,
        )

        return image

    def create_node_tree(self):
        debug("create_node_tree")
        image = bpy.data.images.get(f"ImageTexSkyCustom_{self.id}")
        if image is None:
            image = self.create_image()

        self.node_tree = bpy.data.node_groups.new(self.name, "ShaderNodeTree")
        nt = self.node_tree
        nt.color_tag = "TEXTURE"

        nt.interface.new_socket(name="Color", in_out="OUTPUT", socket_type="NodeSocketColor")

        env_tex = nt.nodes.new("ShaderNodeTexEnvironment")
        env_tex.image = image

        group_out = nt.nodes.new("NodeGroupOutput")
        group_out.is_active_output = True

        nt.links.new(env_tex.outputs["Color"], group_out.inputs["Color"])

    def copy_node_tree(self):
        debug("copy_node_tree")
        image = self.create_image()
        
        self.node_tree = self.node_tree.copy()
        nt = self.node_tree

        env_tex = next((node for node in nt.nodes if node.type == "TEX_ENVIRONMENT"), None)
        debug(env_tex)
        env_tex.image = image

    def init(self, context):
        debug("init")
        self.id = genrate_id()

        texture_skyview, compute_shader = self.create_gpu_resources()

        GPU_RESOURCES[self.id] = {
            "texture_skyview": texture_skyview,
            "compute_shader": compute_shader,
        }

        image = bpy.data.images.get(f"ImageTexSkyCustom_{self.id}")
        if image is None:
            image = self.create_image()

        self.create_node_tree()
        self.update_texture()

    def update_texture(self):
        debug("update_texture")
        resources = GPU_RESOURCES.get(self.id)

        if resources is None:
            texture_skyview, compute_shader = self.create_gpu_resources()

            resources = {
                "texture_skyview": texture_skyview,
                "compute_shader": compute_shader,
            }

            GPU_RESOURCES[self.id] = resources

        compute_shader = resources["compute_shader"]
        texture_skyview = resources["texture_skyview"]

        image = bpy.data.images.get(f"ImageTexSkyCustom_{self.id}")

        if image is None:
            image = self.create_image()
            env_tex = self.node_tree.nodes.get("Environment Texture")
            env_tex.image = image

        compute_shader.image("img_output", texture_skyview)
        compute_shader.uniform_float("sun_elevation", self.sun_elevation / 57.2957795131)
        compute_shader.uniform_float("sun_rotation", self.sun_rotation / 57.2957795131)
        compute_shader.uniform_float("altitude", max(self.altitude, 1.0) / 1000.0)
        compute_shader.uniform_float("air", self.air)
        compute_shader.uniform_float("aerosols", self.aerosols)
        compute_shader.uniform_float("ozone", self.ozone)
        compute_shader.uniform_float("scatter_muti", self.scatter_muti)
        gpu.compute.dispatch(compute_shader, SKYVIEW_WIDTH // 8, SKYVIEW_HEIGHT // 8, 1)

        data = texture_skyview.read()
        buffer_size = SKYVIEW_WIDTH * SKYVIEW_HEIGHT * 4
        buffer = gpu.types.Buffer("FLOAT", buffer_size, data)

        image.pixels.foreach_set(buffer)
        image.update()
        
        bpy.context.scene.world.color = bpy.context.scene.world.color
        if bpy.context.scene.render.engine == "CYCLES":
            bpy.context.scene.render.engine = "BLENDER_EEVEE"
            bpy.context.scene.render.engine = "CYCLES"

    def draw_buttons(self, context, layout):
        #debug("draw_buttons")
        row = layout.row()
        row.label(
            text="Sun disc not available",
            icon="ERROR"
        )
        layout.prop(self, "sun_elevation")
        layout.prop(self, "sun_rotation")
        layout.prop(self, "altitude")
        layout.prop(self, "air")
        layout.prop(self, "aerosols")
        layout.prop(self, "ozone")
        layout.prop(self, "scatter_muti")
        
        #layout.prop(self, "id")

    def copy(self, node):
        debug("copy")
        self.id = genrate_id()
        self.copy_node_tree()
        self.update_texture()

    def free(self):
        debug("free")
        GPU_RESOURCES.pop(self.id, None)

        if self.node_tree and self.node_tree.users == 1:
            bpy.data.node_groups.remove(self.node_tree, do_unlink=True)

        image = bpy.data.images.get(f"ImageTexSkyCustom_{self.id}")

        if image and image.users ==1:
            bpy.data.images.remove(image)


def add_to_menu(self, context):
    debug("add_to_menu")
    space = getattr(context, "space_data", None)
    shader_type = getattr(space, "shader_type", None)
    if shader_type != "WORLD":
        return
    op = self.layout.operator("node.add_node", text=ShaderNodeTexSkyCustom.bl_label, icon="NONE",)
    op.type = "ShaderNodeTexSkyCustom"
    op.use_transform = True

def update_all():
    debug("update_all")
    for world in bpy.data.worlds:
        if world.node_tree is None:
            continue
        for node in world.node_tree.nodes:
            if node.bl_idname == "ShaderNodeTexSkyCustom":
                node.update_texture()

@bpy.app.handlers.persistent
def update_post_load(dummy):
    debug("update_post_load")
    update_all()

@bpy.app.handlers.persistent
def update_post_undo(scene):
    debug("update_post_undo")
    update_all()

@bpy.app.handlers.persistent
def update_post_redo(scene):
    debug("update_post_redo")
    update_all()

def register():
    bpy.types.NODE_MT_category_shader_texture.append(add_to_menu)
    bpy.utils.register_class(ShaderNodeTexSkyCustom)

    if update_post_load not in bpy.app.handlers.load_post:
        bpy.app.handlers.load_post.append(update_post_load)

    if update_post_undo not in bpy.app.handlers.undo_post:
        bpy.app.handlers.undo_post.append(update_post_undo)

    if update_post_redo not in bpy.app.handlers.redo_post:
            bpy.app.handlers.redo_post.append(update_post_redo)


def unregister():
    bpy.types.NODE_MT_category_shader_texture.remove(add_to_menu)
    bpy.utils.unregister_class(ShaderNodeTexSkyCustom)
    
    if update_post_load in bpy.app.handlers.load_post:
        bpy.app.handlers.load_post.remove(update_post_load)

    if update_post_undo in bpy.app.handlers.undo_post:
        bpy.app.handlers.undo_post.remove(update_post_undo)

    if update_post_redo in bpy.app.handlers.redo_post:
            bpy.app.handlers.redo_post.remove(update_post_redo)