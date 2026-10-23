# Paint Channels

GDDraw paints more than color. In 3D mode a **Paint Channel** dropdown sits next to the 2D/3D/Split selector.

## The channels

- **Albedo** is the base color and the default.
- **Emission** paints glow. New emission textures use the Multiply operator so a white color never makes the whole model glow.
- **Roughness**, **Metallic**, **Ambient Occlusion** and **Height** are single values and are painted as gray. The color picker is limited to gray while one of them is active.
- **Normal** paints a tangent-space normal map. A new normal texture starts flat, so the surface looks unchanged. Godot uses OpenGL-style normal maps.

## How a channel is opened

Pick a channel, then choose **Godot > Use Selected 3D Object**. GDDraw opens the same objects for that channel. Changing the channel while a session is open reopens the objects in the new channel and asks what to do with unsaved textures.

If a material has no texture for the channel, GDDraw offers to create one. Nothing is created without your confirmation. New textures start neutral: they reproduce the material's current value, so the surface looks the same until you paint.

If the material stores several channels in one packed texture (for example glTF metallic-roughness), GDDraw unpacks the channel into a new dedicated texture and leaves the original untouched.

## Meshes without a material

A mesh surface without a material, including a fresh `CylinderMesh`, can be opened. GDDraw offers to create a `StandardMaterial3D` (assigned as a surface override, undoable) and its texture. The mesh resource itself is not changed.

## Texture size

**Image > Scale Textures...** resizes all textures of the object you are painting in one undoable step, which is the way to shrink a huge texture. **Resize Canvas**, **Crop** and **Trim** stay disabled in 3D because they would shift pixels against the UVs. Save afterwards to write the new size to disk.

## Scenes stay small

New GDDraw textures are written as PNG files. Once Godot has imported a PNG, GDDraw puts the imported file into the material, so a saved scene references the file instead of embedding the pixels.

## Limits

- The painted material must be a `StandardMaterial3D`. Other material types are refused with a reason.
- CSG shapes only have an albedo material, so the other channels cannot be painted on them.