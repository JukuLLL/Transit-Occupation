@tool
extends CompositorEffect
class_name PostProcessChromaticAberration

enum AberrationMode { RADIAL, LATERAL }

@export_group("Settings")

@export_range(0.0, 50.0, 0.1) var strength: float = 3.0:
	set(v):
		mutex.lock()
		strength = v
		mutex.unlock()

@export_range(1, 32, 1) var samples: int = 8:
	set(v):
		mutex.lock()
		samples = v
		mutex.unlock()

@export var mode: AberrationMode = AberrationMode.RADIAL:
	set(v):
		mutex.lock()
		mode = v
		mutex.unlock()

@export_group("Advanced Settings")

@export_subgroup("Channel Offsets")

@export_range(-2.0, 2.0, 0.01) var red_offset: float = 1.0:
	set(v):
		mutex.lock()
		red_offset = v
		mutex.unlock()

@export_range(-2.0, 2.0, 0.01) var green_offset: float = 0.0:
	set(v):
		mutex.lock()
		green_offset = v
		mutex.unlock()

@export_range(-2.0, 2.0, 0.01) var blue_offset: float = -1.0:
	set(v):
		mutex.lock()
		blue_offset = v
		mutex.unlock()

@export_subgroup("Fringe")

@export var fringe_color: Color = Color.WHITE:
	set(v):
		mutex.lock()
		fringe_color = v
		mutex.unlock()

@export_subgroup("Falloff")

@export_range(0.1, 8.0, 0.01) var falloff_power: float = 2.0:
	set(v):
		mutex.lock()
		falloff_power = v
		mutex.unlock()

@export_range(0.0, 0.95, 0.01) var inner_radius: float = 0.0:
	set(v):
		mutex.lock()
		inner_radius = v
		mutex.unlock()

@export_range(0.0, 2.0, 0.01) var barrel_distortion: float = 0.0:
	set(v):
		mutex.lock()
		barrel_distortion = v
		mutex.unlock()

@export_subgroup("Center")

@export_range(0.0, 1.0, 0.001) var center_x: float = 0.5:
	set(v):
		mutex.lock()
		center_x = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.001) var center_y: float = 0.5:
	set(v):
		mutex.lock()
		center_y = v
		mutex.unlock()

@export_subgroup("Lateral")

@export_range(-180.0, 180.0, 0.5) var lateral_angle: float = 0.0:
	set(v):
		mutex.lock()
		lateral_angle = v
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
	var shader_file: RDShaderFile = load("res://addons/compositor_effects/chromatic_aberration/chromatic_aberration.glsl")
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
	var _samples: float = float(samples)
	var _red: float = red_offset
	var _green: float = green_offset
	var _blue: float = blue_offset
	var _falloff: float = falloff_power
	var _barrel: float = barrel_distortion
	var _cx: float = center_x
	var _cy: float = center_y
	var _lateral: float = 1.0 if mode == AberrationMode.LATERAL else 0.0
	var _angle: float = lateral_angle
	var _inner: float = inner_radius
	var _fringe: Color = fringe_color
	mutex.unlock()

	var push_constant: PackedFloat32Array = PackedFloat32Array([
		_strength, _samples, _red, _green,
		_blue, _falloff, _barrel, _cx,
		_cy, _lateral, _angle, _inner,
		_fringe.r, _fringe.g, _fringe.b, 0.0,
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
