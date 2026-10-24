@tool
extends CompositorEffect
class_name PostProcessAnalogNoise

enum BlendMode { ADDITIVE, SCREEN, OVERLAY, SOFT_LIGHT }

@export_group("Settings")

@export_range(0.0, 1.0, 0.005) var intensity: float = 0.1:
	set(v):
		mutex.lock()
		intensity = v
		mutex.unlock()

@export_range(1.0, 32.0, 0.1) var grain_scale: float = 1.0:
	set(v):
		mutex.lock()
		grain_scale = v
		mutex.unlock()

@export var monochromatic: bool = true:
	set(v):
		mutex.lock()
		monochromatic = v
		mutex.unlock()

@export var blend_mode: BlendMode = BlendMode.ADDITIVE:
	set(v):
		mutex.lock()
		blend_mode = v
		mutex.unlock()

@export_group("Advanced Settings")

@export_subgroup("Animation")

@export_range(0.0, 10.0, 0.1) var speed: float = 1.0:
	set(v):
		mutex.lock()
		speed = v
		mutex.unlock()

@export_subgroup("Tint")

@export var tint: Color = Color.WHITE:
	set(v):
		mutex.lock()
		tint = v
		mutex.unlock()

@export_subgroup("Luminance Response")

@export_range(0.0, 3.0, 0.01) var shadow_response: float = 1.2:
	set(v):
		mutex.lock()
		shadow_response = v
		mutex.unlock()

@export_range(0.0, 3.0, 0.01) var midtone_response: float = 1.0:
	set(v):
		mutex.lock()
		midtone_response = v
		mutex.unlock()

@export_range(0.0, 3.0, 0.01) var highlight_response: float = 0.4:
	set(v):
		mutex.lock()
		highlight_response = v
		mutex.unlock()

@export_range(0.0, 0.5, 0.01) var shadow_threshold: float = 0.25:
	set(v):
		mutex.lock()
		shadow_threshold = v
		mutex.unlock()

@export_range(0.5, 1.0, 0.01) var highlight_threshold: float = 0.75:
	set(v):
		mutex.lock()
		highlight_threshold = v
		mutex.unlock()

@export_subgroup("Distribution")

@export var triangle_distribution: bool = true:
	set(v):
		mutex.lock()
		triangle_distribution = v
		mutex.unlock()

@export var clamp_output: bool = true:
	set(v):
		mutex.lock()
		clamp_output = v
		mutex.unlock()

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var mutex: Mutex = Mutex.new()
var _frame_counter: int = 0

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		return
	_create_pipeline()

func _create_pipeline() -> void:
	var shader_file: RDShaderFile = load("res://addons/compositor_effects/analog_noise/analog_noise.glsl")
	if shader_file == null:
		return

	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		return

	pipeline = rd.compute_pipeline_create(shader)

func _render_callback(
	p_effect_callback_type: EffectCallbackType,
	p_render_data: RenderData
) -> void:
	if rd == null:
		return
	if not shader.is_valid() or not pipeline.is_valid():
		return
	if p_effect_callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return

	var render_scene_buffers: RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
	if render_scene_buffers == null:
		return

	var size: Vector2i = render_scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return

	mutex.lock()
	var _intensity: float = intensity
	var _grain_scale: float = grain_scale
	var _monochromatic: float = 1.0 if monochromatic else 0.0
	var _speed: float = speed
	var _tint: Color = tint
	var _blend_mode: float = float(blend_mode)
	var _shadow_response: float = shadow_response
	var _midtone_response: float = midtone_response
	var _highlight_response: float = highlight_response
	var _shadow_threshold: float = shadow_threshold
	var _highlight_threshold: float = highlight_threshold
	var _triangle: float = 1.0 if triangle_distribution else 0.0
	var _clamp: float = 1.0 if clamp_output else 0.0
	mutex.unlock()

	if _speed > 0.0:
		_frame_counter = (_frame_counter + maxi(1, int(_speed))) % 65536
	var frame_val: float = float(_frame_counter)

	var push_constant: PackedFloat32Array = PackedFloat32Array([
		_intensity, _grain_scale, _monochromatic, _speed,
		_tint.r, _tint.g, _tint.b, _blend_mode,
		_shadow_response, _midtone_response, _highlight_response, _shadow_threshold,
		_highlight_threshold, _triangle, _clamp, frame_val,
	])

	var x_groups: int = (size.x + 15) / 16
	var y_groups: int = (size.y + 15) / 16

	for view: int in render_scene_buffers.get_view_count():
		var color_image: RID = render_scene_buffers.get_color_layer(view)

		var color_uniform: RDUniform = RDUniform.new()
		color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		color_uniform.binding = 0
		color_uniform.add_id(color_image)

		var uniform_set: RID = UniformSetCacheRD.get_cache(shader, 0, [color_uniform])

		var compute_list: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_set_push_constant(
			compute_list,
			push_constant.to_byte_array(),
			push_constant.size() * 4
		)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
