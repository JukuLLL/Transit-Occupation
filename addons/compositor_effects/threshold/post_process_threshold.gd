@tool
extends CompositorEffect
class_name PostProcessThreshold

enum ColorSpace { LUMA, RED, GREEN, BLUE }

@export_group("Settings")

@export_range(0.0, 1.0, 0.01) var cutoff: float = 0.5:
	set(v):
		mutex.lock()
		cutoff = v
		mutex.unlock()

@export_range(0.0, 0.5, 0.01) var softness: float = 0.05:
	set(v):
		mutex.lock()
		softness = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var strength: float = 1.0:
	set(v):
		mutex.lock()
		strength = v
		mutex.unlock()

@export_group("Colors")

@export var dark_color: Color = Color(0.0, 0.0, 0.0, 1.0):
	set(v):
		mutex.lock()
		dark_color = v
		mutex.unlock()

@export var light_color: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(v):
		mutex.lock()
		light_color = v
		mutex.unlock()

@export_group("Advanced Settings")

@export var evaluate_mode: ColorSpace = ColorSpace.LUMA:
	set(v):
		mutex.lock()
		evaluate_mode = v
		mutex.unlock()

@export var invert: bool = false:
	set(v):
		mutex.lock()
		invert = v
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
	var shader_file: RDShaderFile = load("res://addons/compositor_effects/threshold/threshold.glsl")
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
	var _dr: float = dark_color.r
	var _dg: float = dark_color.g
	var _db: float = dark_color.b
	var _c: float = cutoff
	var _lr: float = light_color.r
	var _lg: float = light_color.g
	var _lb: float = light_color.b
	var _sf: float = softness
	var _st: float = strength
	var _inv: float = 1.0 if invert else 0.0
	var _em: float = float(evaluate_mode)
	mutex.unlock()

	var push_constant: PackedFloat32Array = PackedFloat32Array([
		_dr, _dg, _db, _c,
		_lr, _lg, _lb, _sf,
		_st, _inv, _em, 0.0,
		0.0, 0.0, 0.0, 0.0,
	])

	var x_groups: int = (size.x + 15) / 16
	var y_groups: int = (size.y + 15) / 16

	for view: int in render_scene_buffers.get_view_count():
		var color_image: RID = render_scene_buffers.get_color_layer(view)
		if not color_image.is_valid():
			continue

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
