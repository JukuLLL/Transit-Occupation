@tool
extends CompositorEffect
class_name PostProcessCausticLensFocus

enum DistortionMode { RADIAL, TANGENTIAL }

@export_group("Settings")

@export_range(0.0, 5.0, 0.01) var intensity: float = 1.0:
	set(v):
		mutex.lock()
		intensity = v
		mutex.unlock()

@export_range(0.0, 2.0, 0.01) var aberration_spread: float = 0.5:
	set(v):
		mutex.lock()
		aberration_spread = v
		mutex.unlock()

@export_range(0.1, 200.0, 0.1) var wave_frequency: float = 20.0:
	set(v):
		mutex.lock()
		wave_frequency = v
		mutex.unlock()

@export_range(0.0, 20.0, 0.1) var wave_speed: float = 5.0:
	set(v):
		mutex.lock()
		wave_speed = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var blend: float = 1.0:
	set(v):
		mutex.lock()
		blend = v
		mutex.unlock()

@export_group("Advanced Settings")

@export_subgroup("Focus Point")

@export_range(0.0, 1.0, 0.001) var focus_x: float = 0.5:
	set(v):
		mutex.lock()
		focus_x = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.001) var focus_y: float = 0.5:
	set(v):
		mutex.lock()
		focus_y = v
		mutex.unlock()

@export_subgroup("Mask")

@export_range(0.0, 2.0, 0.01) var falloff_radius: float = 0.0:
	set(v):
		mutex.lock()
		falloff_radius = v
		mutex.unlock()

@export_range(0.01, 1.0, 0.01) var falloff_sharpness: float = 0.5:
	set(v):
		mutex.lock()
		falloff_sharpness = v
		mutex.unlock()

@export_subgroup("Wave")

@export_range(0.0, 10.0, 0.1) var luminance_boost: float = 2.0:
	set(v):
		mutex.lock()
		luminance_boost = v
		mutex.unlock()

@export_range(1.0, 8.0, 0.1) var harmonics: float = 2.0:
	set(v):
		mutex.lock()
		harmonics = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var harmonic_scale: float = 0.3:
	set(v):
		mutex.lock()
		harmonic_scale = v
		mutex.unlock()

@export_subgroup("Direction")

@export var distortion_mode: DistortionMode = DistortionMode.RADIAL:
	set(v):
		mutex.lock()
		distortion_mode = v
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
	var shader_file: RDShaderFile = load("res://addons/compositor_effects/caustic_lens_focus/caustic_lens_focus.glsl")
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

	var t: float = float(Time.get_ticks_msec()) / 1000.0

	mutex.lock()
	var _intensity: float = intensity
	var _aberration: float = aberration_spread
	var _frequency: float = wave_frequency
	var _speed: float = wave_speed
	var _focus_x: float = focus_x
	var _focus_y: float = focus_y
	var _falloff_r: float = falloff_radius
	var _falloff_s: float = falloff_sharpness
	var _luma_boost: float = luminance_boost
	var _harmonics: float = harmonics
	var _hscale: float = harmonic_scale
	var _blend: float = blend
	var _mode: float = float(distortion_mode)
	mutex.unlock()

	var push_constant: PackedFloat32Array = PackedFloat32Array([
		_intensity, _aberration, _frequency, t,
		_focus_x, _focus_y, _speed, _falloff_r,
		_falloff_s, _luma_boost, _harmonics, _hscale,
		_blend, _mode, 0.0, 0.0,
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
