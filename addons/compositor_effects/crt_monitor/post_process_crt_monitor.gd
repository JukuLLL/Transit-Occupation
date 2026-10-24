@tool
extends CompositorEffect
class_name PostProcessCRTMonitor

enum MonitorType { APERTURE_GRILLE, SHADOW_MASK, SLOT_MASK, MONOCHROME_P38, LCD_MATRIX }

@export_group("Monitor Structure")

@export var monitor_type: MonitorType = MonitorType.APERTURE_GRILLE:
	set(v): mutex.lock(); monitor_type = v; mutex.unlock()

@export_range(0.1, 5.0, 0.01) var phosphor_scale: float = 1.0:
	set(v): mutex.lock(); phosphor_scale = v; mutex.unlock()

@export_range(0.0, 1.0, 0.01) var scanline_depth: float = 0.5:
	set(v): mutex.lock(); scanline_depth = v; mutex.unlock()

@export_range(120, 1080, 1) var scanline_count: int = 480:
	set(v): mutex.lock(); scanline_count = v; mutex.unlock()

@export var scanline_interlaced: bool = false:
	set(v): mutex.lock(); scanline_interlaced = v; mutex.unlock()

@export_range(0.0, 0.5, 0.01) var corner_roundness: float = 0.05:
	set(v): mutex.lock(); corner_roundness = v; mutex.unlock()

@export_group("Signal & Optics")

@export_range(-5.0, 5.0, 0.01) var electron_convergence_x: float = 0.0:
	set(v): mutex.lock(); electron_convergence_x = v; mutex.unlock()

@export_range(-5.0, 5.0, 0.01) var electron_convergence_y: float = 0.0:
	set(v): mutex.lock(); electron_convergence_y = v; mutex.unlock()

@export_range(0.0, 10.0, 0.01) var rf_color_bleed: float = 2.0:
	set(v): mutex.lock(); rf_color_bleed = v; mutex.unlock()

@export_range(0.0, 2.0, 0.01) var luma_halation: float = 0.5:
	set(v): mutex.lock(); luma_halation = v; mutex.unlock()

@export_range(0.0, 5.0, 0.01) var vignette_strength: float = 0.5:
	set(v): mutex.lock(); vignette_strength = v; mutex.unlock()

@export_group("Advanced Settings")

@export_range(0.0, 5.0, 0.01) var rf_noise_roll: float = 0.1:
	set(v): mutex.lock(); rf_noise_roll = v; mutex.unlock()

@export_range(0.0, 5.0, 0.01) var rf_noise_static: float = 0.1:
	set(v): mutex.lock(); rf_noise_static = v; mutex.unlock()

@export_range(0.1, 3.0, 0.01) var phosphor_power: float = 1.0:
	set(v): mutex.lock(); phosphor_power = v; mutex.unlock()

@export_range(1.0, 3.0, 0.01) var brightness_boost: float = 1.3:
	set(v): mutex.lock(); brightness_boost = v; mutex.unlock()

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var _shader_copy: RID
var _pipe_copy: RID

var mutex: Mutex = Mutex.new()
var _intermediate: RID
var _last_size: Vector2i = Vector2i()
var _time_accum: float = 0.0

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		return
	_create_pipeline()

func _create_pipeline() -> void:
	var shader_file: RDShaderFile = load("res://addons/compositor_effects/crt_monitor/crt_monitor.glsl")
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

	_time_accum += 0.0166

	mutex.lock()
	var _mt: float = float(monitor_type)
	var _ps: float = phosphor_scale
	var _pp: float = phosphor_power
	var _cx: float = electron_convergence_x
	var _cy: float = electron_convergence_y
	var _sd: float = scanline_depth
	var _sc: float = float(scanline_count)
	var _si: float = 1.0 if scanline_interlaced else 0.0
	var _rns: float = rf_noise_static
	var _rnr: float = rf_noise_roll
	var _rcb: float = rf_color_bleed
	var _lh: float = luma_halation
	var _vs: float = vignette_strength
	var _cr: float = corner_roundness
	var _bb: float = brightness_boost
	mutex.unlock()

	var push_constant: PackedFloat32Array = PackedFloat32Array([
		_mt, _ps, _pp, _cx,
		_cy, _sd, _sc, _si,
		_rns, _rnr, _rcb, _lh,
		_vs, _cr, _bb, _time_accum
	])

	var x_groups: int = (size.x + 15) / 16
	var y_groups: int = (size.y + 15) / 16

	for view: int in render_scene_buffers.get_view_count():
		var color_img: RID = render_scene_buffers.get_color_layer(view)
		if not color_img.is_valid() or not _intermediate.is_valid():
			continue

		if _pipe_copy.is_valid():
			var u_cp_src: RDUniform = RDUniform.new()
			u_cp_src.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			u_cp_src.binding = 0
			u_cp_src.add_id(color_img)
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
		u_dst.add_id(color_img)
		var set_dst: RID = UniformSetCacheRD.get_cache(shader, 1, [u_dst])

		var cl: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, pipeline)
		rd.compute_list_bind_uniform_set(cl, set_src, 0)
		rd.compute_list_bind_uniform_set(cl, set_dst, 1)
		rd.compute_list_set_push_constant(cl, push_constant.to_byte_array(), 64)
		rd.compute_list_dispatch(cl, x_groups, y_groups, 1)
		rd.compute_list_end()
