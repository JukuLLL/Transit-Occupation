@tool
extends CompositorEffect
class_name PostProcessPixelation

enum ColorMode { NORMAL, GRAYSCALE, ONE_BIT }

@export_group("Settings")

@export_range(1.0, 128.0, 1.0) var pixel_size_x: float = 8.0:
	set(v):
		mutex.lock()
		pixel_size_x = v
		mutex.unlock()

@export_range(1.0, 128.0, 1.0) var pixel_size_y: float = 8.0:
	set(v):
		mutex.lock()
		pixel_size_y = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var strength: float = 1.0:
	set(v):
		mutex.lock()
		strength = v
		mutex.unlock()

@export_group("Advanced Settings")

@export_subgroup("Grid")

@export_range(-64.0, 64.0, 1.0) var grid_offset_x: float = 0.0:
	set(v):
		mutex.lock()
		grid_offset_x = v
		mutex.unlock()

@export_range(-64.0, 64.0, 1.0) var grid_offset_y: float = 0.0:
	set(v):
		mutex.lock()
		grid_offset_y = v
		mutex.unlock()

@export_subgroup("Gap")

@export_range(0.0, 64.0, 1.0) var gap_size_x: float = 0.0:
	set(v):
		mutex.lock()
		gap_size_x = v
		mutex.unlock()

@export_range(0.0, 64.0, 1.0) var gap_size_y: float = 0.0:
	set(v):
		mutex.lock()
		gap_size_y = v
		mutex.unlock()

@export var gap_color: Color = Color.BLACK:
	set(v):
		mutex.lock()
		gap_color = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var gap_roundness: float = 0.0:
	set(v):
		mutex.lock()
		gap_roundness = v
		mutex.unlock()

@export_range(0.01, 3.0, 0.01) var gap_aa: float = 0.5:
	set(v):
		mutex.lock()
		gap_aa = v
		mutex.unlock()

@export_subgroup("Color")

@export var color_mode: ColorMode = ColorMode.NORMAL:
	set(v):
		mutex.lock()
		color_mode = v
		mutex.unlock()

@export_range(0.0, 256.0, 1.0) var posterize_levels: float = 0.0:
	set(v):
		mutex.lock()
		posterize_levels = v
		mutex.unlock()

@export_subgroup("Outline")

@export_range(0.0, 3.0, 0.1) var outline_strength: float = 0.0:
	set(v):
		mutex.lock()
		outline_strength = v
		mutex.unlock()

@export_range(0.0, 0.5, 0.01) var outline_threshold: float = 0.05:
	set(v):
		mutex.lock()
		outline_threshold = v
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
	var shader_file: RDShaderFile = load("res://addons/compositor_effects/pixelation/pixelation.glsl")
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
	var _psx: float = pixel_size_x
	var _psy: float = pixel_size_y
	var _gox: float = grid_offset_x
	var _goy: float = grid_offset_y
	var _gsx: float = gap_size_x
	var _gsy: float = gap_size_y
	var _gc: Color = gap_color
	var _gr: float = gap_roundness
	var _gaa: float = gap_aa
	var _cm: float = float(color_mode)
	var _pl: float = posterize_levels
	var _os: float = outline_strength
	var _ot: float = outline_threshold
	var _str: float = strength
	mutex.unlock()

	var push_constant: PackedFloat32Array = PackedFloat32Array([
		_psx, _psy, _gox, _goy,
		_gsx, _gsy, _gc.r, _gc.g,
		_gc.b, _gr, _gaa, _cm,
		_pl, _os, _ot, _str,
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
