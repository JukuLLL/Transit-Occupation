@tool
class_name UBToolbarMount
extends RefCounted
## Finds where the toolbar can move to its own row below the 3D editor's menu row.


## Returns {"vbox": VBoxContainer, "anchor": Node}, or {} when the tree does not match.
static func find_row_anchor(menu_hbox: Node) -> Dictionary:
	if menu_hbox == null:
		return {}
	var node := menu_hbox
	for _hop in 4:
		var parent := node.get_parent()
		if parent == null:
			return {}
		if parent is VBoxContainer:
			return {"vbox": parent, "anchor": node}
		node = parent
	return {}
