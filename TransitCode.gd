class_name TransitCoder extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

static func replace_wait(Code:String) -> String:
	var regex:RegEx = RegEx.new()
	regex.compile("wait\\((\\d+\\.?\\d*)\\)")
	var new_code : String = regex.sub(Code, "await get_tree().create_timer($1).timeout", true)
	return	new_code
	
static func replace_damage(Code:String) -> String:
	Code = Code.replace("damage()","get_parent().damger.damage()")
	return Code

static func to_code(Code:String) -> String:

	Code = Code.replace("|",";")
	Code = Code.strip_escapes()
	Code = Code.remove_chars(" ")
	Code = Code.to_lower()
	Code = replace_wait(Code)
	Code = replace_damage(Code)
	Code = Code.replace("-"," ")
	Code.replace("*","extends Node; func run(): ")
	
	return Code
