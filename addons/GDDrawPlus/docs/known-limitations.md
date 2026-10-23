# Known Limitations

This page describes the intended boundaries of GDDrawPlus 0.3.2 rather than unfinished behavior that should silently fail.

## 3D materials and channels

- 3D painting targets `StandardMaterial3D` surfaces. Albedo, emission, roughness, metallic, ambient occlusion, height and normal textures can be painted (see [Paint Channels](paint-channels.md)); other material types are refused with a reason.
- Shader materials cannot be painted into. They can be used as sources of the [Material Brush](material-brush.md), which bakes them into images.
- CSG shapes only support the albedo channel.
- Supported CSG painting is limited to generated geometry and material configurations that provide deterministic triangle UVs.
- Multi-material generated CSG results must be prepared outside GDDraw.
- `CSGTorus3D` creation is deferred because its generated seam triangles can interpolate across unrelated texture regions.

## UV ambiguity

- Overlapping UV shells can make linked 2D-to-3D hover choose a hidden or rear surface.
- Mirrored and shared UV pieces display the same texture pixels by design.
- Spatially separate shared pieces can often be disambiguated by the 3D ray hit, but coincident mappings may be rejected.
- Dense seams, tiny islands, and heavy overlap should be manually checked after painting.

## Texture and performance boundaries

- Very large textures require more memory and may pause briefly during first-time cache and preview initialization.
- Complex models and visually busy textures can make brush, hover, or UV previews harder to read.
- Resize Canvas, Crop and Trim are disabled in 3D sessions because they would shift pixels against the UVs. Use Image > Scale Textures to change the resolution of all textures of an object.

## Interface boundaries

- Split View and Preferences can feel crowded in narrow bottom-panel layouts.
- Native clipboard and file-dialog behavior can differ across desktop operating systems.
- In-app documentation supports the Markdown subset used by the packaged manual rather than every GitHub Markdown extension.

## File format boundaries

- PNG export is flattened by design.
- Use `.gddraw` layered projects to preserve editable layers, groups, target bindings, oversized layer content, and eraser baselines.
- Layered 3D documents reference their source Godot Scene; they do not embed a silent duplicate of the model geometry.

If behavior falls outside these documented boundaries without an explanation in the status bar, it may be a defect rather than a limitation.
