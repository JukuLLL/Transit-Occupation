@tool
extends CompositorEffect
class_name PostProcessBleachBypass

@export_group("Settings")

@export_range(0.0, 1.0, 0.01) var strength: float = 1.0:
	set(v): mutex.lock(); strength = v; mutex.unlock()

@export_range(0.0, 2.0, 0.01) var saturation_boost: float = 0.0:
	set(v): mutex.lock(); saturation_boost = v; mutex.unlock()

@export_range(0.5, 3.0, 0.01) var contrast: float = 1.0:
	set(v): mutex.lock(); contrast = v; mutex.unlock()

@export_group("Advanced Settings")

@export_range(0.0, 3.0, 0.01) var pre_exposure: float = 1.0:
	set(v): mutex.lock(); pre_exposure = v; mutex.unlock()

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
	var shader_file: RDShaderFile = load("res://addons/compositor_effects/bleach_bypass/bleach_bypass.glsl")
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
	var _st: float = strength
	var _sb: float = saturation_boost
	var _ct: float = contrast
	var _pe: float = pre_exposure
	mutex.unlock()

	var push_constant: PackedFloat32Array = PackedFloat32Array([
		_st, _sb, _ct, _pe,
		0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0
	])

	var x_groups: int = (size.x + 15) / 16
	var y_groups: int = (size.y + 15) / 16

	for view: int in render_scene_buffers.get_view_count():
		var color_img: RID = render_scene_buffers.get_color_layer(view)
		if not color_img.is_valid():
			continue

		var u_color: RDUniform = RDUniform.new()
		u_color.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_color.binding = 0
		u_color.add_id(color_img)
		var set_color: RID = UniformSetCacheRD.get_cache(shader, 0, [u_color])

		var compute_list: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, set_color, 0)
		rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), 64)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
