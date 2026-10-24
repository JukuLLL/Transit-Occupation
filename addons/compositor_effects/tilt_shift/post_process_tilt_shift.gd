@tool
extends CompositorEffect
class_name PostProcessTiltShift

enum FocusShape { LINEAR, CIRCULAR }

@export_group("Settings")

@export var focus_shape: FocusShape = FocusShape.LINEAR:
	set(v):
		mutex.lock()
		focus_shape = v
		mutex.unlock()

@export_range(-90.0, 90.0, 1.0) var focus_angle: float = 0.0:
	set(v):
		mutex.lock()
		focus_angle = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var focus_center: float = 0.5:
	set(v):
		mutex.lock()
		focus_center = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var focus_width: float = 0.2:
	set(v):
		mutex.lock()
		focus_width = v
		mutex.unlock()

@export_range(1.0, 32.0, 1.0) var blur_amount: float = 8.0:
	set(v):
		mutex.lock()
		blur_amount = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var strength: float = 1.0:
	set(v):
		mutex.lock()
		strength = v
		mutex.unlock()

@export_group("Advanced Settings")

@export_subgroup("Bokeh")

@export_range(0.0, 10.0, 0.1) var highlight_boost: float = 0.0:
	set(v):
		mutex.lock()
		highlight_boost = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var highlight_threshold: float = 0.8:
	set(v):
		mutex.lock()
		highlight_threshold = v
		mutex.unlock()

@export_subgroup("Looks")

@export_range(1.0, 3.0, 0.01) var saturation_boost: float = 1.3:
	set(v):
		mutex.lock()
		saturation_boost = v
		mutex.unlock()

@export_range(0.0, 20.0, 0.1) var sigma: float = 0.0:
	set(v):
		mutex.lock()
		sigma = v
		mutex.unlock()

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var _shader_copy: RID
var _pipe_copy: RID
var _intermediate: RID

var mutex: Mutex = Mutex.new()
var _last_size: Vector2i = Vector2i()

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		return
	_create_pipeline()

func _create_pipeline() -> void:
	var shader_file: RDShaderFile = load("res://addons/compositor_effects/tilt_shift/tilt_shift.glsl")
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
	var _fc: float = focus_center
	var _fw: float = focus_width
	var _ba: float = blur_amount
	var _si: float = sigma
	var _sb: float = saturation_boost
	var _an: float = focus_angle
	var _sh: float = float(focus_shape)
	var _hb: float = highlight_boost
	var _ht: float = highlight_threshold
	var _st: float = strength
	mutex.unlock()

	var push_constant: PackedFloat32Array = PackedFloat32Array([
		_fc, _fw, _ba, _si,
		_sb, _an, _sh, _hb,
		_ht, _st, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0,
	])

	var x_groups: int = (size.x + 15) / 16
	var y_groups: int = (size.y + 15) / 16

	for view: int in render_scene_buffers.get_view_count():
		var color_image: RID = render_scene_buffers.get_color_layer(view)
		if not color_image.is_valid() or not _intermediate.is_valid():
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
