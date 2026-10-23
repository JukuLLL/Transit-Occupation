@tool
# Derived from Gator Model Studio (c) 2026 Blackwater Gator Studios, MIT License.
# See LICENSE-GatorModelStudio.txt. Modified for GDDraw: renamed classes, mesh-rebuild code removed,
# host hooks added to the editor window.
class_name GDDrawUVUnfoldPreviewWindow
extends Window

const UNFOLD_SHADER_CODE: String = """
shader_type spatial;
render_mode cull_disabled;

uniform float unfold_amount : hint_range(0.0, 1.0) = 0.0;
uniform float flat_y = 0.0;
uniform vec4 preview_color : source_color = vec4(0.78, 0.78, 0.82, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_albedo_texture = false;

void vertex() {
	vec3 flat_position = vec3(UV2.x, flat_y, UV2.y);
	VERTEX = mix(VERTEX, flat_position, unfold_amount);
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), unfold_amount));
}

void fragment() {
	vec4 colour = preview_color;
	if (has_albedo_texture) {
		colour *= texture(albedo_texture, UV);
	}
	ALBEDO = colour.rgb;
	ROUGHNESS = 0.78;
}
"""

var _source_mesh: GDDrawUVMeshData
var _textures: Array[Texture2D] = []
var _source_revision: int = -1
var _texture_signature: String = ""
var _preview_dirty: bool = true
var _mesh_instance: MeshInstance3D
var _subviewport: SubViewport
var _camera: Camera3D
var _amount_slider: HSlider
var _animate_button: Button
var _status_label: Label
var _shader_materials: Array[ShaderMaterial] = []
var _source_preview_bounds: AABB = AABB(Vector3.ZERO, Vector3.ONE)
var _flat_preview_bounds: AABB = AABB(Vector3.ZERO, Vector3.ONE)
var _unfold_amount: float = 0.0
var _animation_target: float = 1.0
var _animation_active: bool = false


func _ready() -> void:
	visible = false
	title = "GDDraw — 3D to UV Unfold Preview"
	initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	min_size = Vector2i(620, 420)
	size = Vector2i(860, 620)
	transient = true
	unresizable = false
	close_requested.connect(_on_close_requested)
	_build_interface()
	set_process(false)


func set_data(new_mesh: GDDrawUVMeshData, new_textures: Array[Texture2D] = []) -> void:
	var new_revision: int = new_mesh.get_change_revision() if new_mesh != null else -1
	var new_signature: String = _build_texture_signature(new_textures)
	if (
		_source_mesh == new_mesh
		and _source_revision == new_revision
		and _texture_signature == new_signature
	):
		return
	_source_mesh = new_mesh
	_source_revision = new_revision
	_texture_signature = new_signature
	_textures.clear()
	for source_texture: Texture2D in new_textures:
		_textures.append(source_texture)
	_preview_dirty = true
	if visible:
		_rebuild_preview()


func open_preview() -> void:
	if _preview_dirty:
		_rebuild_preview()
	if visible:
		grab_focus()
	else:
		popup_centered_clamped(Vector2i(860, 620), 0.9)
		call_deferred("grab_focus")
	_frame_camera()


func close_preview() -> void:
	_animation_active = false
	set_process(false)
	hide()


func _build_interface() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var viewport_container: SubViewportContainer = SubViewportContainer.new()
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.stretch = true
	root.add_child(viewport_container)

	_subviewport = SubViewport.new()
	_subviewport.name = "UVUnfoldPreviewViewport"
	_subviewport.size = Vector2i(820, 500)
	_subviewport.own_world_3d = true
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_subviewport.msaa_3d = Viewport.MSAA_4X
	viewport_container.add_child(_subviewport)

	var world_root: Node3D = Node3D.new()
	_subviewport.add_child(world_root)

	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.06, 0.075)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.74, 0.8)
	environment.ambient_light_energy = 0.65
	environment_node.environment = environment
	world_root.add_child(environment_node)

	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	key_light.light_energy = 1.15
	key_light.shadow_enabled = true
	world_root.add_child(key_light)

	var fill_light: DirectionalLight3D = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(35.0, 150.0, 0.0)
	fill_light.light_energy = 0.45
	fill_light.shadow_enabled = false
	world_root.add_child(fill_light)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "UVUnfoldPreviewMesh"
	world_root.add_child(_mesh_instance)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	world_root.add_child(_camera)

	var controls: HFlowContainer = HFlowContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(controls)

	var unfold_label: Label = Label.new()
	unfold_label.text = "3D  ←  Unfold  →  UV"
	controls.add_child(unfold_label)

	_amount_slider = HSlider.new()
	_amount_slider.min_value = 0.0
	_amount_slider.max_value = 1.0
	_amount_slider.step = 0.001
	_amount_slider.value = 0.0
	_amount_slider.custom_minimum_size = Vector2(280.0, 0.0)
	_amount_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount_slider.tooltip_text = "Scrub between the original 3D model and its flattened material UV tiles."
	_amount_slider.value_changed.connect(_on_amount_changed)
	controls.add_child(_amount_slider)

	_animate_button = Button.new()
	_animate_button.text = "Animate to UV"
	_animate_button.tooltip_text = "Animate to the opposite end of the unfold preview."
	_animate_button.pressed.connect(_on_animate_pressed)
	controls.add_child(_animate_button)

	var model_button: Button = Button.new()
	model_button.text = "3D"
	model_button.tooltip_text = "Return immediately to the original 3D shape."
	model_button.pressed.connect(_set_endpoint.bind(0.0))
	controls.add_child(model_button)

	var uv_button: Button = Button.new()
	uv_button.text = "UV"
	uv_button.tooltip_text = "Jump immediately to the fully flattened UV layout."
	uv_button.pressed.connect(_set_endpoint.bind(1.0))
	controls.add_child(uv_button)

	var frame_button: Button = Button.new()
	frame_button.text = "Frame"
	frame_button.tooltip_text = "Frame the model at the current unfold position."
	frame_button.pressed.connect(_frame_camera)
	controls.add_child(frame_button)

	_status_label = Label.new()
	_status_label.text = "Preview only. The mesh, UVs, materials, and document are not modified."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)


func _rebuild_preview() -> void:
	_preview_dirty = false
	_shader_materials.clear()
	_mesh_instance.mesh = null
	if _source_mesh == null or not _source_mesh.has_uv_map or not _source_mesh.is_valid():
		_status_label.text = "A valid mesh with UVs is required for the unfold preview."
		return

	var material_count: int = maxi(_textures.size(), 1)
	for face_index: int in _source_mesh.faces.size():
		material_count = maxi(material_count, _source_mesh.get_face_material(face_index) + 1)

	var uv_bounds: Rect2 = _calculate_material_uv_bounds(_source_mesh)
	if uv_bounds.size.x <= 0.000001 or uv_bounds.size.y <= 0.000001:
		_status_label.text = "The UV layout has no usable area to preview."
		return

	var source_bounds: AABB = _source_mesh.get_aabb()
	var source_extent: float = maxf(source_bounds.size.x, maxf(source_bounds.size.y, source_bounds.size.z))
	source_extent = maxf(source_extent, 0.001)
	var uv_extent: float = maxf(uv_bounds.size.x, uv_bounds.size.y)
	var flat_scale: float = source_extent / maxf(uv_extent, 0.000001)
	var source_center: Vector3 = source_bounds.get_center()
	var uv_center: Vector2 = uv_bounds.get_center()

	var output: ArrayMesh = ArrayMesh.new()
	var flat_bounds: AABB = AABB()
	var has_flat_bounds: bool = false
	var shader: Shader = Shader.new()
	shader.code = UNFOLD_SHADER_CODE
	var material_faces: Array[PackedInt32Array] = []
	var material_triangle_counts: PackedInt32Array = PackedInt32Array()
	material_faces.resize(material_count)
	material_triangle_counts.resize(material_count)
	for material_index: int in material_count:
		material_faces[material_index] = PackedInt32Array()
	for face_index: int in _source_mesh.faces.size():
		var face_material_index: int = clampi(
			_source_mesh.get_face_material(face_index), 0, material_count - 1
		)
		material_faces[face_material_index].append(face_index)
		material_triangle_counts[face_material_index] += maxi(
			_source_mesh.faces[face_index].size() - 2, 0
		)

	for material_index: int in material_count:
		var selected_faces: PackedInt32Array = material_faces[material_index]
		var triangle_count: int = material_triangle_counts[material_index]
		if triangle_count <= 0:
			continue

		var vertex_count: int = triangle_count * 3
		var render_vertices: PackedVector3Array = PackedVector3Array()
		var render_normals: PackedVector3Array = PackedVector3Array()
		var render_uvs: PackedVector2Array = PackedVector2Array()
		var flat_positions: PackedVector2Array = PackedVector2Array()
		render_vertices.resize(vertex_count)
		render_normals.resize(vertex_count)
		render_uvs.resize(vertex_count)
		flat_positions.resize(vertex_count)
		var write_index: int = 0

		for face_index: int in selected_faces:
			var face: PackedInt32Array = _source_mesh.faces[face_index]
			var face_uvs: PackedVector2Array = _source_mesh.uv_faces[face_index]
			var face_normal: Vector3 = _source_mesh.get_face_normal(face_index)
			for triangle_index: int in range(1, face.size() - 1):
				for corner_pass: int in 3:
					var corner_index: int = 0
					if corner_pass == 1:
						corner_index = triangle_index + 1
					elif corner_pass == 2:
						corner_index = triangle_index
					var model_vertex_index: int = face[corner_index]
					var uv: Vector2 = face_uvs[corner_index]
					var tiled_uv: Vector2 = Vector2(uv.x + float(material_index), uv.y)
					var flat_position: Vector3 = Vector3(
						source_center.x + (tiled_uv.x - uv_center.x) * flat_scale,
						source_center.y,
						source_center.z + (uv_center.y - tiled_uv.y) * flat_scale
					)
					render_vertices[write_index] = _source_mesh.vertices[model_vertex_index]
					render_normals[write_index] = face_normal
					render_uvs[write_index] = uv
					flat_positions[write_index] = Vector2(flat_position.x, flat_position.z)
					if not has_flat_bounds:
						flat_bounds = AABB(flat_position, Vector3.ZERO)
						has_flat_bounds = true
					else:
						flat_bounds = flat_bounds.expand(flat_position)
					write_index += 1

		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = render_vertices
		arrays[Mesh.ARRAY_NORMAL] = render_normals
		arrays[Mesh.ARRAY_TEX_UV] = render_uvs
		arrays[Mesh.ARRAY_TEX_UV2] = flat_positions
		output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var surface_index: int = output.get_surface_count() - 1
		var preview_material: ShaderMaterial = ShaderMaterial.new()
		preview_material.shader = shader
		preview_material.set_shader_parameter("unfold_amount", _unfold_amount)
		preview_material.set_shader_parameter("flat_y", source_center.y)
		preview_material.set_shader_parameter("preview_color", _material_preview_colour(material_index))
		var texture: Texture2D = _textures[material_index] if material_index < _textures.size() else null
		preview_material.set_shader_parameter("has_albedo_texture", texture != null)
		if texture != null:
			preview_material.set_shader_parameter("albedo_texture", texture)
		output.surface_set_material(surface_index, preview_material)
		_shader_materials.append(preview_material)

	if output.get_surface_count() <= 0:
		_status_label.text = "The mesh did not produce any triangles for the unfold preview."
		return
	_source_preview_bounds = source_bounds.grow(maxf(source_extent * 0.03, 0.01))
	_flat_preview_bounds = flat_bounds.grow(maxf(source_extent * 0.03, 0.01)) if has_flat_bounds else _source_preview_bounds
	output.custom_aabb = _source_preview_bounds.merge(_flat_preview_bounds)
	_mesh_instance.mesh = output
	_apply_unfold_amount(_unfold_amount)
	_frame_camera()
	_status_label.text = "Preview only. Seams split as the model flattens, and each material moves into its own UV tile."


func _calculate_material_uv_bounds(mesh: GDDrawUVMeshData) -> Rect2:
	var minimum: Vector2 = Vector2(INF, INF)
	var maximum: Vector2 = Vector2(-INF, -INF)
	for face_index: int in mesh.faces.size():
		if face_index >= mesh.uv_faces.size():
			continue
		var material_index: int = mesh.get_face_material(face_index)
		for uv: Vector2 in mesh.uv_faces[face_index]:
			var tiled_uv: Vector2 = Vector2(uv.x + float(material_index), uv.y)
			minimum.x = minf(minimum.x, tiled_uv.x)
			minimum.y = minf(minimum.y, tiled_uv.y)
			maximum.x = maxf(maximum.x, tiled_uv.x)
			maximum.y = maxf(maximum.y, tiled_uv.y)
	if not is_finite(minimum.x) or not is_finite(minimum.y):
		return Rect2()
	return Rect2(minimum, maximum - minimum)


func _material_preview_colour(material_index: int) -> Color:
	var hue: float = fmod(float(material_index) * 0.173, 1.0)
	return Color.from_hsv(hue, 0.18, 0.9, 1.0)


func _build_texture_signature(source_textures: Array[Texture2D]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for texture: Texture2D in source_textures:
		if texture == null:
			parts.append("null")
		else:
			parts.append("%d:%s" % [texture.get_instance_id(), texture.resource_path])
	return "|".join(parts)


func _on_amount_changed(value: float) -> void:
	_animation_active = false
	set_process(false)
	_apply_unfold_amount(float(value))


func _apply_unfold_amount(value: float) -> void:
	_unfold_amount = clampf(value, 0.0, 1.0)
	if _amount_slider != null and not is_equal_approx(float(_amount_slider.value), _unfold_amount):
		_amount_slider.set_value_no_signal(_unfold_amount)
	for material: ShaderMaterial in _shader_materials:
		if material != null:
			material.set_shader_parameter("unfold_amount", _unfold_amount)
	if _animate_button != null:
		_animate_button.text = "Animate to 3D" if _unfold_amount >= 0.5 else "Animate to UV"
	if visible:
		_frame_camera()


func _on_animate_pressed() -> void:
	_animation_target = 0.0 if _unfold_amount >= 0.5 else 1.0
	_animation_active = true
	set_process(true)


func _set_endpoint(value: float) -> void:
	_animation_active = false
	set_process(false)
	_apply_unfold_amount(value)


func _process(delta: float) -> void:
	if not _animation_active:
		set_process(false)
		return
	var next_amount: float = move_toward(_unfold_amount, _animation_target, delta / 1.35)
	_apply_unfold_amount(next_amount)
	if is_equal_approx(_unfold_amount, _animation_target):
		_animation_active = false
		set_process(false)


func _frame_camera() -> void:
	if _camera == null or _subviewport == null or _mesh_instance == null or _mesh_instance.mesh == null:
		return
	var current_bounds: AABB = _get_current_preview_bounds()
	var center: Vector3 = current_bounds.get_center()
	var radius: float = maxf(current_bounds.size.length() * 0.5, 0.05)
	var model_direction: Vector3 = Vector3(1.25, 0.9, 1.25).normalized()
	var model_camera_transform: Transform3D = Transform3D(
		Basis.IDENTITY,
		model_direction
	).looking_at(Vector3.ZERO, Vector3.UP)
	var uv_camera_transform: Transform3D = Transform3D(
		Basis.IDENTITY,
		Vector3.UP
	).looking_at(Vector3.ZERO, Vector3.BACK)
	var model_rotation: Quaternion = model_camera_transform.basis.get_rotation_quaternion()
	var uv_rotation: Quaternion = uv_camera_transform.basis.get_rotation_quaternion()
	var camera_rotation: Quaternion = model_rotation.slerp(uv_rotation, _unfold_amount)
	var camera_basis: Basis = Basis(camera_rotation).orthonormalized()
	var direction: Vector3 = camera_basis.z.normalized()
	_camera.basis = camera_basis
	_camera.position = center + direction * radius * 3.0
	_camera.near = maxf(radius * 0.002, 0.001)
	_camera.far = maxf(radius * 12.0, 100.0)

	var camera_basis_inverse: Basis = _camera.global_transform.basis.inverse()
	var half_size: Vector3 = current_bounds.size * 0.5
	var projected_half_width: float = 0.0
	var projected_half_height: float = 0.0
	for x_sign: float in [-1.0, 1.0]:
		for y_sign: float in [-1.0, 1.0]:
			for z_sign: float in [-1.0, 1.0]:
				var offset: Vector3 = Vector3(
					half_size.x * x_sign,
					half_size.y * y_sign,
					half_size.z * z_sign
				)
				var camera_space_offset: Vector3 = camera_basis_inverse * offset
				projected_half_width = maxf(projected_half_width, absf(camera_space_offset.x))
				projected_half_height = maxf(projected_half_height, absf(camera_space_offset.y))

	var viewport_size: Vector2i = _subviewport.size
	var aspect: float = float(maxi(viewport_size.x, 1)) / float(maxi(viewport_size.y, 1))
	var required_height: float = maxf(projected_half_height * 2.0, projected_half_width * 2.0 / maxf(aspect, 0.001))
	_camera.size = maxf(required_height * 1.16, 0.1)


func _get_current_preview_bounds() -> AABB:
	var source_center: Vector3 = _source_preview_bounds.get_center()
	var flat_center: Vector3 = _flat_preview_bounds.get_center()
	var current_center: Vector3 = source_center.lerp(flat_center, _unfold_amount)
	var current_size: Vector3 = _source_preview_bounds.size.lerp(
		_flat_preview_bounds.size,
		_unfold_amount
	)
	current_size.x = maxf(current_size.x, 0.001)
	current_size.y = maxf(current_size.y, 0.001)
	current_size.z = maxf(current_size.z, 0.001)
	return AABB(current_center - current_size * 0.5, current_size)


func _on_close_requested() -> void:
	close_preview()
