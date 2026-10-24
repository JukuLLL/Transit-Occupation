@tool
extends CompositorEffect
class_name PostProcessSharpness

@export_group("Settings")

@export_range(0.0, 5.0, 0.1) var strength: float = 1.0:
	set(v):
		mutex.lock()
		strength = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var threshold: float = 0.05:
	set(v):
		mutex.lock()
		threshold = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var limit: float = 0.5:
	set(v):
		mutex.lock()
		limit = v
		mutex.unlock()

@export_group("Advanced Settings")

@export_subgroup("Kernel")

@export_range(1, 4, 1) var radius: int = 1:
	set(v):
		mutex.lock()
		radius = v
		mutex.unlock()

@export var luma_only: bool = false:
	set(v):
		mutex.lock()
		luma_only = v
		mutex.unlock()

@export_subgroup("Detail")

@export_range(0.0, 5.0, 0.1) var detail_boost: float = 0.0:
	set(v):
		mutex.lock()
		detail_boost = v
		mutex.unlock()

@export_subgroup("Depth")

@export_range(0.0, 1.0, 0.01) var depth_threshold: float = 1.0:
	set(v):
		mutex.lock()
		depth_threshold = v
		mutex.unlock()

@export_range(0.0, 10.0, 0.1) var edge_protect: float = 0.0:
	set(v):
		mutex.lock()
		edge_protect = v
		mutex.unlock()

@export_subgroup("Camera")

@export_range(0.01, 10.0, 0.01) var near_plane: float = 0.05:
	set(v):
		mutex.lock()
		near_plane = v
		mutex.unlock()

@export_range(10.0, 10000.0, 10.0) var far_plane: float = 1000.0:
	set(v):
		mutex.lock()
		far_plane = v
		mutex.unlock()

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var _shader_copy: RID
var _pipe_copy: RID
var _nearest_sampler: RID

var mutex: Mutex = Mutex.new()
var _intermediate: RID
var _last_size: Vector2i = Vector2i()

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_depth = true
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		return
	_create_pipeline()

func _create_pipeline() -> void:
	var shader_file: RDShaderFile = load("res://addons/compositor_effects/sharpness/sharpness.glsl")
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

	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_nearest_sampler = rd.sampler_create(sampler_state)

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
	var _str: float = strength
	var _thr: float = threshold
	var _lim: float = limit
	var _dt: float = depth_threshold
	var _rad: float = float(radius)
	var _lo: float = 1.0 if luma_only else 0.0
	var _np: float = near_plane
	var _fp: float = far_plane
	var _db: float = detail_boost
	var _ep: float = edge_protect
	mutex.unlock()

	var push_constant: PackedFloat32Array = PackedFloat32Array([
		_str, _thr, _lim, _dt,
		_rad, _lo, _np, _fp,
		_db, _ep, 0.0, 0.0,
	])

	var x_groups: int = (size.x + 15) / 16
	var y_groups: int = (size.y + 15) / 16

	for view: int in render_scene_buffers.get_view_count():
		var color_image: RID = render_scene_buffers.get_color_layer(view)
		var depth_image: RID = render_scene_buffers.get_depth_layer(view)

		if not color_image.is_valid() or not depth_image.is_valid():
			continue
		if not _intermediate.is_valid():
			continue
		if not _nearest_sampler.is_valid():
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

		var u_depth: RDUniform = RDUniform.new()
		u_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_depth.binding = 0
		u_depth.add_id(_nearest_sampler)
		u_depth.add_id(depth_image)
		var set_depth: RID = UniformSetCacheRD.get_cache(shader, 2, [u_depth])

		var compute_list: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, set_src, 0)
		rd.compute_list_bind_uniform_set(compute_list, set_dst, 1)
		rd.compute_list_bind_uniform_set(compute_list, set_depth, 2)
		rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), 48)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
