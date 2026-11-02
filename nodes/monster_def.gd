class_name MonsterDef extends Resource

@export var id:StringName
@export var display_name := "Monster"
@export_multiline var description := ""
@export var scene:PackedScene          # the real playable monster scene
@export var preview_scene:PackedScene  # a lightweight model-only scene for the menu
@export var icon:Texture2D
