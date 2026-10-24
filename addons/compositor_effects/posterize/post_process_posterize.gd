@tool
extends CompositorEffect
class_name PostProcessPosterize

enum EdgeMode { OFF, ENHANCE, DARKEN }

@export_group("Settings")

@export_range(2, 256, 1) var levels: int = 8:
	set(v):
		mutex.lock()
		levels = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var strength: float = 1.0:
	set(v):
		mutex.lock()
		strength = v
		mutex.unlock()

@export_group("Advanced Settings")

@export_subgroup("Quantization")

@export_range(0.1, 5.0, 0.01) var gamma: float = 1.0:
	set(v):
		mutex.lock()
		gamma = v
		mutex.unlock()

@export var hsv_mode: bool = false:
	set(v):
		mutex.lock()
		hsv_mode = v
		mutex.unlock()

@export_subgroup("Per-Channel Levels")

@export_range(0.25, 4.0, 0.01) var levels_r: float = 1.0:
	set(v):
		mutex.lock()
		levels_r = v
		mutex.unlock()

@export_range(0.25, 4.0, 0.01) var levels_g: float = 1.0:
	set(v):
		mutex.lock()
		levels_g = v
		mutex.unlock()

@export_range(0.25, 4.0, 0.01) var levels_b: float = 1.0:
	set(v):
		mutex.lock()
		levels_b = v
		mutex.unlock()

@export_subgroup("Dither")

@export_range(0.0, 1.0, 0.01) var dither_amount: float = 0.0:
	set(v):
		mutex.lock()
		dither_amount = v
		mutex.unlock()

@export_range(1.0, 8.0, 0.5) var dither_size: float = 1.0:
	set(v):
		mutex.lock()
		dither_size = v
		mutex.unlock()

@export_subgroup("Saturation")

@export_range(0.0, 3.0, 0.01) var saturation_boost: float = 1.0:
	set(v):
		mutex.lock()
		saturation_boost = v
		mutex.unlock()

@export_subgroup("Edge")

@export var edge_mode: EdgeMode = EdgeMode.OFF:
	set(v):
		mutex.lock()
		edge_mode = v
		mutex.unlock()

@export_range(0.0, 3.0, 0.1) var edge_strength: float = 1.0:
	set(v):
		mutex.lock()
		edge_strength = v
		mutex.unlock()

@export_range(0.0, 0.5, 0.01) var edge_threshold: float = 0.05:
	set(v):
		mutex.lock()
		edge_threshold = v
		mutex.unlock()

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var mutex: Mutex = Mutex.new()

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		return
	_create_pipeline()

func _create_pipeline() -> void:
	var shader_file: RDShaderFile = load("res://addons/compositor_effects/posterize/posterize.glsl")
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

	var render_scene_buffers: RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
	if render_scene_buffers == null:
		return

	var size: Vector2i = render_scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return

	mutex.lock()
	var _levels: float = float(levels)
	var _str: float = strength
	var _gamma: float = gamma
	var _sat: float = saturation_boost
	var _dither: float = dither_amount
	var _hsv: float = 1.0 if hsv_mode else 0.0
	var _lr: float = levels_r
	var _lg: float = levels_g
	var _lb: float = levels_b
	var _ds: float = dither_size
	var _em: float = float(edge_mode)
	var _es: float = edge_strength
	var _et: float = edge_threshold
	mutex.unlock()

	var push_constant: PackedFloat32Array = PackedFloat32Array([
		_levels, _str, _gamma, _sat,
		_dither, _hsv, _lr, _lg,
		_lb, _ds, _em, _es,
		_et, 0.0, 0.0, 0.0,
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
		rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), 64)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
