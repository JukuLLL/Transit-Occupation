@tool
extends CompositorEffect
class_name PostProcessColorBleed

enum BlendMode { YUV, MIX, ADD }
enum Direction  { HORIZONTAL, VERTICAL, BOTH, ANGLE }
enum WeightMode { LINEAR, GAUSSIAN, EXPONENTIAL }

@export_group("Settings")

@export_range(0.0, 20.0, 0.1) var bleed_strength: float = 2.0:
	set(v):
		mutex.lock()
		bleed_strength = v
		mutex.unlock()

@export_range(1, 64, 1) var samples: int = 16:
	set(v):
		mutex.lock()
		samples = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var intensity: float = 1.0:
	set(v):
		mutex.lock()
		intensity = v
		mutex.unlock()

@export var direction: Direction = Direction.HORIZONTAL:
	set(v):
		mutex.lock()
		direction = v
		mutex.unlock()

@export var blend_mode: BlendMode = BlendMode.YUV:
	set(v):
		mutex.lock()
		blend_mode = v
		mutex.unlock()

@export_group("Advanced Settings")

@export_subgroup("Bleed")

@export_range(0.0, 4.0, 0.1) var bleed_saturation: float = 1.5:
	set(v):
		mutex.lock()
		bleed_saturation = v
		mutex.unlock()

@export var tint: Color = Color.WHITE:
	set(v):
		mutex.lock()
		tint = v
		mutex.unlock()

@export var weight_mode: WeightMode = WeightMode.LINEAR:
	set(v):
		mutex.lock()
		weight_mode = v
		mutex.unlock()

@export_subgroup("Source")

@export_range(0.0, 2.0, 0.01) var original_saturation: float = 1.0:
	set(v):
		mutex.lock()
		original_saturation = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var luma_threshold: float = 0.0:
	set(v):
		mutex.lock()
		luma_threshold = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var saturation_threshold: float = 0.1:
	set(v):
		mutex.lock()
		saturation_threshold = v
		mutex.unlock()

@export_subgroup("Angle Direction")

@export_range(-180.0, 180.0, 0.5) var angle: float = 45.0:
	set(v):
		mutex.lock()
		angle = v
		mutex.unlock()

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var _shader_copy: RID
var _pipe_copy: RID
var _sampler: RID

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
	var shader_file: RDShaderFile = load("res://addons/compositor_effects/color_bleed/color_bleed.glsl")
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
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = rd.sampler_create(sampler_state)

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
	var _strength: float = bleed_strength
	var _samples: float = float(samples)
	var _bleed_sat: float = bleed_saturation
	var _blend: float = float(blend_mode)
	var _intensity: float = intensity
	var _orig_sat: float = original_saturation
	var _sat_thr: float = saturation_threshold
	var _luma: float = luma_threshold
	var _tint: Color = tint
	var _dir: float = float(direction)
	var _angle: float = angle
	var _wmode: float = float(weight_mode)
	mutex.unlock()

	var push_constant: PackedFloat32Array = PackedFloat32Array([
		_strength, _samples, _bleed_sat, _blend,
		_intensity, _orig_sat, _sat_thr, _luma,
		_tint.r, _tint.g, _tint.b, _dir,
		_angle, _wmode, 0.0, 0.0,
	])

	var x_groups: int = (size.x + 15) / 16
	var y_groups: int = (size.y + 15) / 16

	for view: int in render_scene_buffers.get_view_count():
		var color_image: RID = render_scene_buffers.get_color_layer(view)

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
		u_src.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_src.binding = 0
		u_src.add_id(_sampler)
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
