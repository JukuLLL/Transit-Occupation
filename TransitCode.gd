extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


static func to_code(Code:String) -> Script:
	
	var translated_script:Script
	
	Code = Code.replace("|",";")
	Code = Code.strip_escapes()
	Code = Code.remove_chars(" ")
	Code = Code.to_lower()
	Code = Code.replace("wait()","await get_tree().timeout")

	translated_script.source_code = Code
	return translated_script
