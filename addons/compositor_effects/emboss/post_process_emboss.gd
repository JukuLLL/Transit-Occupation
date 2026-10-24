@tool
extends CompositorEffect
class_name PostProcessEmboss

enum MixMode { EMBOSS, SOFT_LIGHT, ADDITIVE, MULTIPLY }

@export_group("Settings")

@export_range(0.0, 10.0, 0.1) var strength: float = 1.0:
	set(v):
		mutex.lock()
		strength = v
		mutex.unlock()

@export_range(0.0, 360.0, 1.0) var angle: float = 135.0:
	set(v):
		mutex.lock()
		angle = v
		mutex.unlock()

@export var mix_mode: MixMode = MixMode.SOFT_LIGHT:
	set(v):
		mutex.lock()
		mix_mode = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var blend: float = 1.0:
	set(v):
		mutex.lock()
		blend = v
		mutex.unlock()

@export_group("Advanced Settings")

@export_subgroup("Kernel")

@export_range(1.0, 16.0, 1.0) var kernel_radius: float = 1.0:
	set(v):
		mutex.lock()
		kernel_radius = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var bias: float = 0.5:
	set(v):
		mutex.lock()
		bias = v
		mutex.unlock()

@export_range(0.1, 5.0, 0.1) var contrast: float = 1.0:
	set(v):
		mutex.lock()
		contrast = v
		mutex.unlock()

@export_subgroup("Color")

@export var edge_tint: Color = Color.WHITE:
	set(v):
		mutex.lock()
		edge_tint = v
		mutex.unlock()

@export var luma_only: bool = false:
	set(v):
		mutex.lock()
		luma_only = v
		mutex.unlock()

@export_subgroup("Metallic")

@export_range(0.0, 3.0, 0.1) var metallic: float = 0.0:
	set(v):
		mutex.lock()
		metallic = v
		mutex.unlock()

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var _shader_copy: RID
var _pipe_copy: RID

var mutex: Mutex = Mutex.new()
var _intermediate: RID
var _last_size: Vector2i = Vector2i()

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		return
	_create_pipeline()

func _create_pipeline() -> void:
	var shader_file: RDShaderFile = load("res://addons/compositor_effects/emboss/emboss.glsl")
	if shader_file == null:
		return

	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		return

	pipeline = rd.compute_pipeline_create(shader)

	var copy_file: RDShaderFile = load("res://addons/compositor_effects/shared/copy.glsl")
	if copy_file != null:
		_shader_copy = rd.shader_create_from_spirv(copy_file.get_spirv())
		if _shader_copy.is_valid():
			_pipe_copy = rd.compute_pipeline_create(_shader_copy)

func _render_callback(
	p_effect_callback_type: EffectCallbackType,
	p_render_data: RenderData
) -> void:
	if rd == null:
		return
	if not shader.is_valid() or not pipeline.is_valid():
		return

	var render_scene_buffers: RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
	if render_scene_buffers == null:
		return

	var size: Vector2i = render_scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return

	if size != _last_size or not _intermediate.is_valid():
		if _intermediate.is_valid():
			rd.free_rid(_intermediate)
		var fmt := RDTextureFormat.new()
		fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		fmt.width = size.x
		fmt.height = size.y
		fmt.usage_bits = (
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
			RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT |
			RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT |
			RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		)
		_intermediate = rd.texture_create(fmt, RDTextureView.new())
		_last_size = size

	mutex.lock()
	var _strength: float = strength
	var _angle: float = angle
	var _mode: float = float(mix_mode)
	var _bias: float = bias
	var _radius: float = kernel_radius
	var _tint: Color = edge_tint
	var _luma: float = 1.0 if luma_only else 0.0
	var _contrast: float = contrast
	var _blend: float = blend
	var _metallic: float = metallic
	mutex.unlock()

	var push_constant: PackedFloat32Array = PackedFloat32Array([
		_strength, _angle, _mode, _bias,
		_radius, _tint.r, _tint.g, _tint.b,
		_luma, _contrast, _blend, _metallic,
		0.0, 0.0, 0.0, 0.0,
	])

	var x_groups: int = (size.x + 15) / 16
	var y_groups: int = (size.y + 15) / 16

	for view: int in render_scene_buffers.get_view_count():
		var color_image: RID = render_scene_buffers.get_color_layer(view)
		if not color_image.is_valid():
			continue

		if _pipe_copy.is_valid():
			var u_cp_src: RDUniform = RDUniform.new()
			u_cp_src.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			u_cp_src.binding = 0
			u_cp_src.add_id(color_image)
			var set_cp_src: RID = UniformSetCacheRD.get_cache(_shader_copy, 0, [u_cp_src])

			var u_cp_dst: RDUniform = RDUniform.new()
			u_cp_dst.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			u_cp_dst.binding = 0
			u_cp_dst.add_id(_intermediate)
			var set_cp_dst: RID = UniformSetCacheRD.get_cache(_shader_copy, 1, [u_cp_dst])

			var cl_copy: int = rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(cl_copy, _pipe_copy)
			rd.compute_list_bind_uniform_set(cl_copy, set_cp_src, 0)
			rd.compute_list_bind_uniform_set(cl_copy, set_cp_dst, 1)
			rd.compute_list_dispatch(cl_copy, x_groups, y_groups, 1)
			rd.compute_list_end()

		var u_src: RDUniform = RDUniform.new()
		u_src.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_src.binding = 0
		u_src.add_id(_intermediate)
		var set_src: RID = UniformSetCacheRD.get_cache(shader, 0, [u_src])

		var u_dst: RDUniform = RDUniform.new()
		u_dst.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_dst.binding = 0
		u_dst.add_id(color_image)
		var set_dst: RID = UniformSetCacheRD.get_cache(shader, 1, [u_dst])

		var compute_list: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, set_src, 0)
		rd.compute_list_bind_uniform_set(compute_list, set_dst, 1)
		rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), 64)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
