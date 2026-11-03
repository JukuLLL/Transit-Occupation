class_name UBEdition
## Which build this is: full or demo.


const DEMO := false

## The public store URL, used by the toolbar chip, the buy dialog and the watermark.
const STORE_URL := "https://calinleafshade.itch.io/unibuilder"

## Minutes between the demo's periodic reminder toasts.
const NAG_MINUTES := 60


## Demo capacity caps: meshes per edited scene and faces per mesh.
const DEMO_MAX_NODES := 12
const DEMO_MAX_FACES := 500


## True when growing a mesh from `before` to `after` faces must be refused.
static func face_cap_blocks(before: int, after: int, demo := DEMO) -> bool:
	return demo and after > DEMO_MAX_FACES and after > before


## True when adding `adding` Unibuilder meshes to a scene that already holds
## `existing` must be refused.
static func node_cap_blocks(existing: int, adding := 1, demo := DEMO) -> bool:
	return demo and existing + adding > DEMO_MAX_NODES
