# GDDraw UV tools

UV unwrapping for GDDraw's mesh painting, in its own **UV** menu in GDDraw's menu bar (File, Edit,
Image, Select, Tool, View, Godot, **UV**, Help). Select a `MeshInstance3D` in the scene tree, then
choose from the UV menu:

- **Auto Unwrap…** asks for a method and a margin, then unwraps every surface of the mesh.
  Every material slot gets its own 0-1 tile. Methods:
  - **Smart (automatic)** (default): cuts the mesh into low-distortion charts with Godot's built-in
    xatlas and repacks them with a real margin. Best for characters.
  - **Box, Cylinder, Sphere, Planar (front / side / top)**: Gator's simple projections, each followed
    by the same margin-honouring repack. Fast; for props, hard surfaces and quick tests.
- **UV Editor…** opens the full editor: mark seams, unwrap from seams, **Auto Unwrap** (same method
  dropdown), pack, relax, stitch/split/weld, move/rotate/scale, texel density, distortion view,
  3D-to-UV preview. Edits stay in memory until **Apply to Mesh**.

Both save the result as a **new mesh file** in `res://gddraw/meshes/` and assign it to the node
through the editor's undo history. The original mesh is never modified. Everything except UV1
(bones, weights, normals, colors, UV2, custom data, blend shapes, materials) is copied from the
source vertices, so skinned characters keep their weights. A running GDDraw paint session follows
the new mesh automatically.

## Files

| File | Role |
| --- | --- |
| `gddraw_uv_tools.gd` | UI controller behind the UV menu (created lazily by `gddraw_dock.gd`): unwrap dialog, background worker, editor session and undo history |
| `gddraw_uv_service.gd` | Unwrap + save + assign with undo |
| `gddraw_uv_mesh_adapter.gd` | Mesh <-> UV data bridge: welds vertices for topology, rebuilds the mesh by splitting vertices along UV seams, all unwrap methods, seam persistence |
| `gddraw_uv_editor_*.gd`, `gddraw_uv_preview.gd`, `gddraw_uv_unfold_preview_window.gd` | UV editor UI |
| `gddraw_uv_operations.gd`, `gddraw_uv_mesh_data.gd`, `gddraw_uv_topology.gd`, `gddraw_uv_background_*.gd` | UV algorithms and data model |

## Origin

The UV editor UI and algorithms are derived from **Gator Model Studio** by Blackwater Gator Studios
(MIT, see `LICENSE-GatorModelStudio.txt`). Changes: classes renamed to `GDDrawUV*`; Gator's mesh
rebuild code (which dropped bone data) removed and replaced by `GDDrawUVMeshAdapter`; Undo / Redo /
Apply / Auto Unwrap (with method dropdown) and a close guard added to the editor window; Gator's
angle-based "Smart UV Project" button removed (it never cut smooth shapes, leaving one badly
stretched island; Auto Unwrap replaces it); the 3D-viewport checker toggle hidden; a packer bug
fixed (`_try_shelf_pack` accepted islands wider than the tile).

## Keyboard shortcuts in the GDDraw panel

GDDraw's own shortcuts (Ctrl+S, Ctrl+Z, ...) only apply after you clicked inside the GDDraw
panel and while it is visible. Hovering does not count, and clicking anywhere else in the editor
hands the keys back to Godot. (The menu accelerators used to be window-wide and swallowed Godot's
Ctrl+S; see `_track_gddraw_click` and `_dispatch_menu_accelerator` in `gddraw_dock.gd`.)

## Notes for whoever edits this

The UV tools are a menu inside the GDDraw panel on purpose (the user asked for that). Do not add a
separate editor dock for them: an earlier attempt did, and its word-wrapping labels made the editor
stretch the whole dock group to 4,000+ px (Godot's `TabContainer` reserves the tallest minimum of all
its tabs, hidden ones included), which pushed the FileSystem dock and the bottom panel off screen.

## Known limits

- Marked seams are stored on the saved mesh (`gddraw_uv_seams` metadata) as 3D positions.
- LOD data of the source mesh is not carried over (Godot regenerates it on import only).
- Smart is slow on dense meshes: about 1 s at 12k triangles and 30-45 s at 50k. It runs on a worker
  thread, so the editor stays usable. The simple methods are instant.
- The Smart layout has a real margin between islands, so it covers roughly 35-45% of the tile
  (xatlas alone would cover about 65% but leaves islands touching).
- Pixels already painted for the old UVs do not follow a new layout.
- Face/edge picking on the 3D model (Gator's viewport tools) is not ported; seams are marked in the
  UV editor.
