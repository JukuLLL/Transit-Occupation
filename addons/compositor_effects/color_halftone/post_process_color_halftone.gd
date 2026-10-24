@tool
extends CompositorEffect
class_name PostProcessColorHalftone

enum ColorMode { CMYK, RGB, BW }
enum DotShape  { CIRCLE, DIAMOND, LINE }
enum LumaMode  { BT601, BT709 }

@export_group("Settings")

@export_range(2.0, 80.0, 0.5) var dot_size: float = 8.0:
	set(v):
		mutex.lock()
		dot_size = v
		mutex.unlock()

@export_range(0.0, 1.0, 0.01) var strength: float = 1.0:
	set(v):
		mutex.lock()
		strength = v
		mutex.unlock()

@export var color_mode: ColorMode = ColorMode.CMYK:
	set(v):
		mutex.lock()
		color_mode = v
		mutex.unlock()

@export var dot_shape: DotShape = DotShape.CIRCLE:
	set(v):
		mutex.lock()
		dot_shape = v
		mutex.unlock()

@export_group("Advanced Settings")

@export_subgroup("Dot")

@export_range(0.1, 1.0, 0.01) var dot_scale: float = 0.5:
	set(v):
		mutex.lock()
		dot_scale = v
		mutex.unlock()

@export_range(0.1, 4.0, 0.01) var dot_gamma: float = 1.0:
	set(v):
		mutex.lock()
		dot_gamma = v
		mutex.unlock()

@export_range(0.0, 0.5, 0.005) var aa_width: float = 0.02:
	set(v):
		mutex.lock()
		aa_width = v
		mutex.unlock()

@export_subgroup("Grid")

@export_range(-180.0, 180.0, 1.0) var angle_offset: float = 0.0:
	set(v):
		mutex.lock()
		angle_offset = v
		mutex.unlock()

@export_subgroup("CMYK Angles")

@export_range(-180.0, 180.0, 1.0) var angle_c: float = 15.0:
	set(v):
		mutex.lock()
		angle_c = v
		mutex.unlock()

@export_range(-180.0, 180.0, 1.0) var angle_m: float = 75.0:
	set(v):
		mutex.lock()
		angle_m = v
		mutex.unlock()

@export_range(-180.0, 180.0, 1.0) var angle_y: float = 0.0:
	set(v):
		mutex.lock()
		angle_y = v
		mutex.unlock()

@export_range(-180.0, 180.0, 1.0) var angle_k: float = 45.0:
	set(v):
		mutex.lock()
		angle_k = v
		mutex.unlock()

@export_subgroup("RGB Angles")

@export_range(-180.0, 180.0, 1.0) var angle_r: float = 0.0:
	set(v):
		mutex.lock()
		angle_r = v
		mutex.unlock()

@export_range(-180.0, 180.0, 1.0) var angle_g: float = 30.0:
	set(v):
		mutex.lock()
		angle_g = v
		mutex.unlock()

@export_range(-180.0, 180.0, 1.0) var angle_b: float = 60.0:
	set(v):
		mutex.lock()
		angle_b = v
		mutex.unlock()

@export_subgroup("BW / Paper-Ink")

@export_range(-180.0, 180.0, 1.0) var angle_bw: float = 45.0:
	set(v):
		mutex.lock()
		angle_bw = v
		mutex.unlock()

@export var luma_mode: LumaMode = LumaMode.BT601:
	set(v):
		mutex.lock()
		luma_mode = v
		mutex.unlock()

@export var paper_color: Color = Color.WHITE:
	set(v):
		mutex.lock()
		paper_color = v
		mutex.unlock()

@export var ink_color: Color = Color.BLACK:
	set(v):
		mutex.lock()
		ink_color = v
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
	var shader_file: RDShaderFile = load("res://addons/compositor_effects/color_halftone/color_halftone.glsl")
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
	var _dot_size: float   = dot_size
	var _strength: float   = strength
	var _mode: float       = float(color_mode)
	var _angle: float      = angle_offset
	var _aa: float         = aa_width
	var _scale: float      = dot_scale
	var _gamma: float      = dot_gamma
	var _shape: float      = float(dot_shape)
	var _paper: Color      = paper_color
	var _ink: Color        = ink_color
	var _ac: float         = angle_c
	var _am: float         = angle_m
	var _ay: float         = angle_y
	var _ak: float         = angle_k
	var _ar: float         = angle_r
	var _ag: float         = angle_g
	var _ab: float         = angle_b
	var _abw: float        = angle_bw
	var _luma: float       = float(luma_mode)
	mutex.unlock()

	var push_constant: PackedFloat32Array = PackedFloat32Array([
		_dot_size, _strength, _mode, _angle,
		_aa, _scale, _gamma, _shape,
		_paper.r, _paper.g, _paper.b, _ink.r,
		_ink.g, _ink.b, _ac, _am,
		_ay, _ak, _ar, _ag,
		_ab, _abw, _luma, 0.0,
	])

	var x_groups: int = (size.x + 15) / 16
	var y_groups: int = (size.y + 15) / 16

	for view: int in render_scene_buffers.get_view_count():
		var color_image: RID = render_scene_buffers.get_color_layer(view)
		if not color_image.is_valid():
			continue
		if not _intermediate.is_valid():
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
		rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), 96)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
