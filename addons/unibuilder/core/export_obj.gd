@tool
class_name UBExportObj
extends RefCounted
## Serializes UBMeshData to Wavefront OBJ text and an MTL sidecar.


static func to_obj(data, object_name := "unibuilder", mtllib := "",
		world_transform := Transform3D.IDENTITY) -> String:
	var w := _Writer.new()
	w.header(mtllib)
	w.add_object(data, object_name, Transform3D.IDENTITY, world_transform,
		func(slot: int) -> String: return _material_name(data, slot))
	return w.finish()


## Writes several meshes into one OBJ file, one `o` group each.
static func to_obj_nodes(entries: Array, mtllib := "") -> String:
	var reg := _Registry.new()
	var w := _Writer.new()
	w.header(mtllib)
	for entry in _valid_entries(entries):
		var data = entry["data"]
		var name: String = entry["name"]
		var xf: Transform3D = entry["transform"]
		w.add_object(data, name, xf, xf,
			func(slot: int) -> String: return reg.name_for(data, slot, name))
	return w.finish()


## Writes the MTL sidecar for one mesh's materials.
static func to_mtl(data) -> String:
	var used := {}
	for f in data.faces:
		used[f.material_index] = true
	var slots: Array = used.keys()
	slots.sort()
	var out := PackedStringArray()
	out.append("# Exported by Unibuilder")
	for slot in slots:
		var mat: Material = null
		if slot >= 0 and slot < data.material_slots.size():
			mat = data.material_slots[slot]
		out.append_array(_mtl_block(_material_name(data, slot), mat))
	return "\n".join(out) + "\n"


## The multi-mesh MTL: the same names to_obj_nodes wrote (both walk the same
## registry in the same order), each distinct material declared once.
static func to_mtl_nodes(entries: Array) -> String:
	var reg := _Registry.new()
	for entry in _valid_entries(entries):
		var data = entry["data"]
		var name: String = entry["name"]
		var used := {}
		for f in data.faces:
			used[f.material_index] = true
		var slots: Array = used.keys()
		slots.sort()
		for slot in slots:
			reg.name_for(data, slot, name)
	var out := PackedStringArray()
	out.append("# Exported by Unibuilder")
	for mtl_name in reg.order:
		out.append_array(_mtl_block(mtl_name, reg.materials[mtl_name]))
	return "\n".join(out) + "\n"


static func _valid_entries(entries: Array) -> Array:
	var valid: Array = []
	for i in entries.size():
		var entry = entries[i]
		if not (entry is Dictionary) or entry.get("data") == null:
			continue
		var name := String(entry.get("name", ""))
		valid.append({
			"data": entry["data"],
			"name": name if not name.is_empty() else "mesh%d" % i,
			"transform": entry.get("transform", Transform3D.IDENTITY),
		})
	return valid


static func _mtl_block(mtl_name: String, mat: Material) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("newmtl " + mtl_name)
	var std := mat as StandardMaterial3D
	var kd: Color = std.albedo_color if std != null else Color.WHITE
	out.append("Kd %.6f %.6f %.6f" % [kd.r, kd.g, kd.b])
	if std != null and std.albedo_texture != null:
		var tex_path: String = std.albedo_texture.resource_path
		if not tex_path.is_empty():
			out.append("map_Kd " + tex_path.get_file())
	return out


static func _material_name(data, slot: int) -> String:
	var base := _base_material_name(data, slot)
	for prior in slot:
		if _base_material_name(data, prior) == base:
			return "%s_%d" % [base, slot]
	return base


static func _base_material_name(data, slot: int) -> String:
	if slot >= 0 and slot < data.material_slots.size() and data.material_slots[slot] != null:
		var m: Material = data.material_slots[slot]
		if not m.resource_name.is_empty():
			return m.resource_name.validate_filename().replace(" ", "_")
	return "mat_%d" % slot


class _Writer:
	var out := PackedStringArray()
	var v_count := 0
	var vt_count := 0
	var vn_count := 0
	var vn_index := {}

	func header(mtllib: String) -> void:
		out.append("# Exported by Unibuilder")
		if not mtllib.is_empty():
			out.append("mtllib " + mtllib)

	func add_object(data, object_name: String, bake: Transform3D,
			uv_transform: Transform3D, name_for: Callable) -> void:
		out.append("o " + object_name)
		var v_base := v_count
		for p in data.positions:
			var wp: Vector3 = bake * p
			out.append("v %.6f %.6f %.6f" % [wp.x, wp.y, wp.z])
		v_count += data.positions.size()

		var baked := bake != Transform3D.IDENTITY
		var mirrored := bake.basis.determinant() < 0.0
		var normal_basis := bake.basis.inverse().transposed()
		var vt := PackedStringArray()
		var vn := PackedStringArray()
		var body := PackedStringArray()
		var current_material := -1
		var current_smoothing := -1
		var topo := UBTopology.build(data)
		var face_normals := PackedVector3Array()
		face_normals.resize(data.faces.size())
		for fi in data.faces.size():
			face_normals[fi] = data.face_normal(data.faces[fi])
		for fi in data.faces.size():
			var face = data.faces[fi]
			if face.vertices.size() < 3:
				continue
			var corners := PackedVector3Array()
			for vi in face.vertices:
				corners.append(data.positions[vi])
			var normal: Vector3 = face_normals[fi]

			var corner_vn := PackedInt32Array()
			for vi in face.vertices:
				var cn := UBMeshCompiler.corner_normal(data, topo, face_normals, fi, vi)
				if baked:
					cn = (normal_basis * cn).normalized()
				var line := "vn %.6f %.6f %.6f" % [cn.x, cn.y, cn.z]
				if not vn_index.has(line):
					vn.append(line)
					vn_count += 1
					vn_index[line] = vn_count
				corner_vn.append(vn_index[line])
			var uvs: PackedVector2Array = (
				face.uv_coords
				if face.uv_manual and face.uv_coords.size() == face.vertices.size()
				else UBUVUnwrap.face_uvs(corners, normal, face, uv_transform))
			for uv in uvs:
				vt.append("vt %.6f %.6f" % [uv.x, 1.0 - uv.y])
			if face.material_index != current_material:
				current_material = face.material_index
				body.append("usemtl " + name_for.call(current_material))
			if face.smoothing_group != current_smoothing:
				current_smoothing = face.smoothing_group
				body.append("s off" if current_smoothing == 0 else "s %d" % current_smoothing)
			var refs := PackedStringArray()
			var n: int = face.vertices.size()

			for k in n:
				var i: int = k if mirrored else n - 1 - k
				refs.append("%d/%d/%d" % [
					v_base + face.vertices[i] + 1, vt_count + i + 1, corner_vn[i]])
			body.append("f " + " ".join(refs))
			vt_count += n
		out.append_array(vt)
		out.append_array(vn)
		out.append_array(body)

	func finish() -> String:
		return "\n".join(out) + "\n"


class _Registry:
	var names := {}
	var materials := {}
	var order: Array[String] = []

	func name_for(data, slot: int, object_name: String) -> String:
		var mat: Material = null
		if slot >= 0 and slot < data.material_slots.size():
			mat = data.material_slots[slot]
		var key = mat.get_instance_id() if mat != null else "%s/%d" % [object_name, slot]
		if names.has(key):
			return names[key]
		var base: String
		if mat != null and not mat.resource_name.is_empty():
			base = mat.resource_name.validate_filename().replace(" ", "_")
		else:
			base = "%s_mat_%d" % [object_name.validate_filename().replace(" ", "_"), slot]
		var mtl_name := base
		var n := 2
		while materials.has(mtl_name):
			mtl_name = "%s_%d" % [base, n]
			n += 1
		names[key] = mtl_name
		materials[mtl_name] = mat
		order.append(mtl_name)
		return mtl_name
