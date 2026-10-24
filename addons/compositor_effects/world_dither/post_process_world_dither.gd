@tool
extends CompositorEffect
class_name PostProcessWorldDither

enum DitherPattern { BAYER_8X8, BAYER_4X4, IGN }
enum ColorMode { RGB, GRAYSCALE }

@export_group("Settings")

@export var dither_pattern: DitherPattern = DitherPattern.BAYER_8X8:
	set(v): mutex.lock(); dither_pattern = v; mutex.unlock()

@export var color_mode: ColorMode = ColorMode.RGB:
	set(v): mutex.lock(); color_mode = v; mutex.unlock()

@export_range(2, 256, 1) var color_levels: int = 8:
	set(v): mutex.lock(); color_levels = v; mutex.unlock()

@export_range(0.0, 1.0, 0.01) var strength: float = 1.0:
	set(v): mutex.lock(); strength = v; mutex.unlock()

@export_group("Advanced Settings")

@export_subgroup("Pattern Geometry")

@export_range(0.01, 50.0, 0.01) var world_scale: float = 1.0:
	set(v): mutex.lock(); world_scale = v; mutex.unlock()

@export_range(0.0, 2.0, 0.01) var dither_intensity: float = 1.0:
	set(v): mutex.lock(); dither_intensity = v; mutex.unlock()

@export_subgroup("Color")

@export_range(0.0, 1.0, 0.01) var posterize_strength: float = 1.0:
	set(v): mutex.lock(); posterize_strength = v; mutex.unlock()

@export_range(0.1, 5.0, 0.01) var gamma: float = 1.0:
	set(v): mutex.lock(); gamma = v; mutex.unlock()

@export_range(0.0, 3.0, 0.01) var saturation_boost: float = 1.0:
	set(v): mutex.lock(); saturation_boost = v; mutex.unlock()

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var _shader_copy: RID
var _pipe_copy: RID
var _nearest_sampler: RID
var _camera_ubo: RID

var mutex: Mutex = Mutex.new()
var _intermediate: RID
var _last_size: Vector2i = Vector2i()

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_normal_roughness = true
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		return
	_create_pipeline()

func _create_pipeline() -> void:
	var f: RDShaderFile = load("res://addons/compositor_effects/world_dither/world_dither.glsl")
	if f == null:
		return
	shader = rd.shader_create_from_spirv(f.get_spirv())
	if not shader.is_valid():
		return
	pipeline = rd.compute_pipeline_create(shader)

	var c_f: RDShaderFile = load("res://addons/compositor_effects/shared/copy.glsl")
	if c_f != null:
		_shader_copy = rd.shader_create_from_spirv(c_f.get_spirv())
		if _shader_copy.is_valid():
			_pipe_copy = rd.compute_pipeline_create(_shader_copy)

	var sampler_state := RDSamplerState.new()
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_nearest_sampler = rd.sampler_create(sampler_state)

	var ubo_init: PackedByteArray = PackedByteArray()
	ubo_init.resize(128)
	ubo_init.fill(0)
	_camera_ubo = rd.uniform_buffer_create(128, ubo_init)

func _render_callback(
	cb_type: EffectCallbackType,
	r_data: RenderData
) -> void:
	if rd == null or not pipeline.is_valid():
		return
	if cb_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return

	var rsb: RenderSceneBuffersRD = r_data.get_render_scene_buffers()
	if rsb == null:
		return
	var size: Vector2i = rsb.get_internal_size()
	if size.x == 0 or size.y == 0:
		return

	var rsd: RenderSceneDataRD = r_data.get_render_scene_data()
	if rsd == null:
		return

	if size != _last_size or not _intermediate.is_valid():
		if _intermediate.is_valid():
			rd.free_rid(_intermediate)
		var fmt := RDTextureFormat.new()
		fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		fmt.width = size.x
		fmt.height = size.y
		fmt.usage_bits = (
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
			| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		)
		_intermediate = rd.texture_create(fmt, RDTextureView.new())
		_last_size = size

	mutex.lock()
	var _color_levels: float = float(color_levels)
	var _strength: float = strength
	var _dither_intensity: float = dither_intensity
	var _world_scale: float = world_scale
	var _gamma: float = gamma
	var _saturation_boost: float = saturation_boost
	var _dp: float = float(dither_pattern)
	var _cm: float = float(color_mode)
	var _ps: float = posterize_strength
	mutex.unlock()

	var pc: PackedFloat32Array = PackedFloat32Array([
		float(size.x),       float(size.y),
		_color_levels,       _strength,
		_dither_intensity,   _world_scale,
		_gamma,              _saturation_boost,
		_dp,                 _cm,
		_ps,                 0.0,
		0.0, 0.0, 0.0, 0.0
	])

	var x_groups: int = (size.x + 15) / 16
	var y_groups: int = (size.y + 15) / 16

	for view: int in rsb.get_view_count():
		var color_img: RID = rsb.get_color_layer(view)
		var depth_img: RID = rsb.get_depth_layer(view)
		var normal_img: RID = rsb.get_texture("forward_clustered", "normal_roughness")

		if not color_img.is_valid() or not depth_img.is_valid() or not normal_img.is_valid() or not _intermediate.is_valid() or not _camera_ubo.is_valid() or not _nearest_sampler.is_valid():
			continue

		var proj: Projection = rsd.get_view_projection(view)
		var cam_transform: Transform3D = rsd.get_cam_transform()

		var inv_proj: Projection = proj.inverse()
		var inv_view: Transform3D = cam_transform

		var ubo_data: PackedFloat32Array = PackedFloat32Array()
		_pack_projection(inv_proj, ubo_data)
		_pack_transform3d_as_mat4(inv_view, ubo_data)

		rd.buffer_update(_camera_ubo, 0, ubo_data.size() * 4, ubo_data.to_byte_array())

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

		var u_dep: RDUniform = RDUniform.new()
		u_dep.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_dep.binding = 0
		u_dep.add_id(_nearest_sampler)
		u_dep.add_id(depth_img)
		var set_dep: RID = UniformSetCacheRD.get_cache(shader, 2, [u_dep])

		var u_norm: RDUniform = RDUniform.new()
		u_norm.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_norm.binding = 0
		u_norm.add_id(_nearest_sampler)
		u_norm.add_id(normal_img)
		var set_norm: RID = UniformSetCacheRD.get_cache(shader, 3, [u_norm])

		var u_cam: RDUniform = RDUniform.new()
		u_cam.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		u_cam.binding = 0
		u_cam.add_id(_camera_ubo)
		var set_cam: RID = UniformSetCacheRD.get_cache(shader, 4, [u_cam])

		var cl: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, pipeline)
		rd.compute_list_bind_uniform_set(cl, set_src, 0)
		rd.compute_list_bind_uniform_set(cl, set_dst, 1)
		rd.compute_list_bind_uniform_set(cl, set_dep, 2)
		rd.compute_list_bind_uniform_set(cl, set_norm, 3)
		rd.compute_list_bind_uniform_set(cl, set_cam, 4)
		rd.compute_list_set_push_constant(cl, pc.to_byte_array(), 64)
		rd.compute_list_dispatch(cl, x_groups, y_groups, 1)
		rd.compute_list_end()

func _pack_projection(p: Projection, arr: PackedFloat32Array) -> void:
	for col: int in 4:
		for row: int in 4:
			arr.push_back(p[col][row])

func _pack_transform3d_as_mat4(t: Transform3D, arr: PackedFloat32Array) -> void:
	arr.push_back(t.basis.x.x); arr.push_back(t.basis.x.y); arr.push_back(t.basis.x.z); arr.push_back(0.0)
	arr.push_back(t.basis.y.x); arr.push_back(t.basis.y.y); arr.push_back(t.basis.y.z); arr.push_back(0.0)
	arr.push_back(t.basis.z.x); arr.push_back(t.basis.z.y); arr.push_back(t.basis.z.z); arr.push_back(0.0)
	arr.push_back(t.origin.x);  arr.push_back(t.origin.y);  arr.push_back(t.origin.z);  arr.push_back(1.0)
