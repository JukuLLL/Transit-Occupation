@tool
extends CompositorEffect
class_name PostProcessGaussianBlur

@export_group("Settings")

@export_range(0.0, 32.0, 1.0) var blur_radius: float = 6.0:
	set(v):
		mutex.lock()
		blur_radius = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var strength: float = 1.0:
	set(v):
		mutex.lock()
		strength = v
		mutex.unlock()

@export_group("Advanced Settings")

@export_subgroup("Kernel")

@export_range(0.0, 20.0, 0.1) var sigma: float = 0.0:
	set(v):
		mutex.lock()
		sigma = v
		mutex.unlock()

@export var gamma_correct: bool = false:
	set(v):
		mutex.lock()
		gamma_correct = v
		mutex.unlock()

@export_subgroup("Tint")

@export var tint: Color = Color.WHITE:
	set(v):
		mutex.lock()
		tint = v
		mutex.unlock()

@export_subgroup("Mask")

@export var luminance_mask: bool = false:
	set(v):
		mutex.lock()
		luminance_mask = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var mask_threshold: float = 0.5:
	set(v):
		mutex.lock()
		mask_threshold = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var mask_softness: float = 0.2:
	set(v):
		mutex.lock()
		mask_softness = v
		mutex.unlock()

@export var mask_invert: bool = false:
	set(v):
		mutex.lock()
		mask_invert = v
		mutex.unlock()

@export_subgroup("Alpha")

@export var preserve_alpha: bool = true:
	set(v):
		mutex.lock()
		preserve_alpha = v
		mutex.unlock()

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var _shader_copy: RID
var _pipe_copy: RID

var mutex: Mutex = Mutex.new()
var _intermediate_a: RID
var _intermediate_b: RID
var _last_size: Vector2i = Vector2i()

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		return
	_create_pipeline()

func _create_pipeline() -> void:
	var shader_file: RDShaderFile = load("res://addons/compositor_effects/gaussian_blur/gaussian_blur.glsl")
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

func _ensure_textures(size: Vector2i) -> void:
	if size != _last_size or not _intermediate_a.is_valid() or not _intermediate_b.is_valid():
		if _intermediate_a.is_valid():
			rd.free_rid(_intermediate_a)
		if _intermediate_b.is_valid():
			rd.free_rid(_intermediate_b)
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
		_intermediate_a = rd.texture_create(fmt, RDTextureView.new())
		_intermediate_b = rd.texture_create(fmt, RDTextureView.new())
		_last_size = size

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

	_ensure_textures(size)

	mutex.lock()
	var local_radius: float = blur_radius
	var local_sigma: float = sigma
	var local_strength: float = strength
	var _tint: Color = tint
	var _pa: float = 1.0 if preserve_alpha else 0.0
	var _lm: float = 1.0 if luminance_mask else 0.0
	var _mi: float = 1.0 if mask_invert else 0.0
	var _mt: float = mask_threshold
	var _ms: float = mask_softness
	var _gc: float = 1.0 if gamma_correct else 0.0
	mutex.unlock()

	if local_radius < 0.5 or local_strength < 0.001:
		return

	var x_groups: int = (size.x + 15) / 16
	var y_groups: int = (size.y + 15) / 16

	for view: int in render_scene_buffers.get_view_count():
		var color_image: RID = render_scene_buffers.get_color_layer(view)
		if not color_image.is_valid():
			continue
		if not _intermediate_a.is_valid() or not _intermediate_b.is_valid():
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
			u_cp_dst.add_id(_intermediate_a)
			var set_cp_dst: RID = UniformSetCacheRD.get_cache(_shader_copy, 1, [u_cp_dst])

			var cl0: int = rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(cl0, _pipe_copy)
			rd.compute_list_bind_uniform_set(cl0, set_cp_src, 0)
			rd.compute_list_bind_uniform_set(cl0, set_cp_dst, 1)
			rd.compute_list_dispatch(cl0, x_groups, y_groups, 1)
			rd.compute_list_end()

		var pc_h: PackedFloat32Array = PackedFloat32Array([
			local_radius, local_sigma, 1.0, 0.0,
			1.0, _pa, _lm, _mi,
			_mt, _ms, _tint.r, _tint.g,
			_tint.b, _gc, 0.0, 0.0,
		])

		var u_h_src: RDUniform = RDUniform.new()
		u_h_src.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_h_src.binding = 0
		u_h_src.add_id(_intermediate_a)
		var set_h_src: RID = UniformSetCacheRD.get_cache(shader, 0, [u_h_src])

		var u_h_dst: RDUniform = RDUniform.new()
		u_h_dst.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_h_dst.binding = 0
		u_h_dst.add_id(_intermediate_b)
		var set_h_dst: RID = UniformSetCacheRD.get_cache(shader, 1, [u_h_dst])

		var cl1: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl1, pipeline)
		rd.compute_list_bind_uniform_set(cl1, set_h_src, 0)
		rd.compute_list_bind_uniform_set(cl1, set_h_dst, 1)
		rd.compute_list_set_push_constant(cl1, pc_h.to_byte_array(), 64)
		rd.compute_list_dispatch(cl1, x_groups, y_groups, 1)
		rd.compute_list_end()

		var pc_v: PackedFloat32Array = PackedFloat32Array([
			local_radius, local_sigma, 0.0, 1.0,
			local_strength, _pa, _lm, _mi,
			_mt, _ms, 1.0, 1.0,
			1.0, _gc, 0.0, 0.0,
		])

		var u_v_src: RDUniform = RDUniform.new()
		u_v_src.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_v_src.binding = 0
		u_v_src.add_id(_intermediate_b)
		var set_v_src: RID = UniformSetCacheRD.get_cache(shader, 0, [u_v_src])

		var u_v_dst: RDUniform = RDUniform.new()
		u_v_dst.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_v_dst.binding = 0
		u_v_dst.add_id(color_image)
		var set_v_dst: RID = UniformSetCacheRD.get_cache(shader, 1, [u_v_dst])

		var cl2: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl2, pipeline)
		rd.compute_list_bind_uniform_set(cl2, set_v_src, 0)
		rd.compute_list_bind_uniform_set(cl2, set_v_dst, 1)
		rd.compute_list_set_push_constant(cl2, pc_v.to_byte_array(), 64)
		rd.compute_list_dispatch(cl2, x_groups, y_groups, 1)
		rd.compute_list_end()
