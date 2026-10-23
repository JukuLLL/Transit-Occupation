# UV Tools

GDDrawPlus adds a **UV** menu to GDDraw's menu bar. It creates and edits the UV layout of a mesh, so you can paint models that have no UVs or poor ones.

## Choose the mesh

Select a `MeshInstance3D` in the Scene tree. If a 3D painting session is open on a mesh and nothing is selected, that mesh is used. Godot's built-in shapes (`CylinderMesh`, `SphereMesh`, `BoxMesh`, ...) work too. CSG shapes are generated meshes and cannot be unwrapped.

## Auto Unwrap

**UV > Auto Unwrap...** asks for a method and a margin, then unwraps every surface. Each material slot gets its own 0-1 tile, because GDDraw paints one material texture at a time.

- **Smart (automatic)** is the default. It cuts the mesh into low-distortion charts with Godot's built-in xatlas and repacks them with a real margin between islands. It is the best choice for characters and organic shapes.
- **Box, Cylinder, Sphere and Planar (front, side, top)** are simple projections followed by the same margin-respecting repack. They are instant and suit props, hard surfaces and quick tests.

The dialog shows the triangle count and, for dense meshes, how long Smart may take. Smart needs about one second at 12,000 triangles and grows faster than linearly; it runs on a worker thread, so the editor stays usable.

## UV Editor

**UV > UV Editor...** opens a full editor window with:

- seam marking and unwrapping from seams,
- Auto Unwrap with the same method choices,
- packing, relaxing, stitching, splitting and welding,
- move, rotate and scale of islands, texel density and a distortion view,
- a 3D-to-UV preview.

Edits stay inside the editor until you choose **Apply to Mesh**. Closing the window with unapplied edits asks what to do.

## What happens to the mesh

Both tools save the result as a new mesh file in `res://gddraw/meshes/` and assign it to the node through the editor's undo history, so **Ctrl+Z** in the Scene reverts it. The original mesh is never modified. Bones, weights, normals, colors, UV2, custom data, blend shapes and materials are copied over, so skinned characters keep their weights. A running paint session follows the new mesh.

Pixels you already painted do not follow a new UV layout. Unwrap first, then paint.

## Limits

- Marked seams are stored on the saved mesh as 3D positions.
- LOD data of the source mesh is not carried over.
- Seams are marked in the UV editor; picking faces and edges on the 3D model is not available.

## Credits

The UV editor and its algorithms are derived from Gator Model Studio by Blackwater Gator Studios (MIT). See `THIRD_PARTY_NOTICES.md`.