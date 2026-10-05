class_name grabber extends Node3D

var mesh:PlaneMesh

func _ready() -> void:
	var mesh = ImmediateMesh.new()

func _grab_set_pos(pos:Vector3):
	if mesh:
		mesh.clear_surfaces()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		mesh.surface_add_vertex(Vector3.LEFT)
		mesh.surface_add_vertex(pos + Vector3.FORWARD + Vector3.LEFT)
		mesh.surface_add_vertex(pos + Vector3.FORWARD + Vector3.RIGHT)
		mesh.surface_add_vertex(Vector3.RIGHT)
		mesh.surface_end()
		$MeshInstance3D.mesh = mesh

func _destroy_grabber():
	self.queue_free()
