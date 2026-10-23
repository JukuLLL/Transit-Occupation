# Material Brush

The **Material Brush** is a tool in the left tool rail, below the Brush. It paints with a PBR material instead of a color. It is the normal brush underneath, so size, hardness, opacity, mirroring and selections all work.

## Choose a material

Use the **Material** menu in the tool options:

- **New Material** creates a `StandardMaterial3D` in `res://gddraw/materials/` and opens it in the Inspector. Changes you make there are followed live.
- **Open Material or Texture Set** takes a material file or any image of a texture set.
- **Edit Current Material in the Inspector**, **Rename** and **Delete** manage material files.
- Recent materials are listed at the bottom.

Supported sources:

- **Materials**: `StandardMaterial3D` and `ORMMaterial3D` files. The packed ORM texture is read: red is ambient occlusion, green is roughness, blue is metallic.
- **Texture sets**: pick one image and GDDraw finds the others by file name: `albedo`, `basecolor`, `diffuse`, `roughness`, `metallic`, `ao`, `emission`, `height`, `heightmap`, `displacement`, `normal`, and packed `_orm` or `_arm` images. Names containing `normal_dx` or `DirectX` are flipped automatically; **Flip Normal Green** does it by hand.
- **Shaders**: a `ShaderMaterial` or `.gdshader` is baked once into images (size under **Shader Bake Size**) and painted from those. A spatial shader can write `ALBEDO`, `ROUGHNESS`, `METALLIC`, `EMISSION`, `AO` and `NORMAL_MAP`; a `vertex()` function that moves vertices is baked as a height map. **New Shader Material** creates an example. Shaders that depend on world position are not supported.

**Scale** sets how often the pattern repeats across the texture and **Rotate** turns it.

## Also paint

**Also paint** lets one stroke paint several channels at once. Picking a material ticks the channels it has its own textures for (channels that only have a value, like a default roughness, are not ticked). You can change the ticks by hand.

When you load a model, GDDraw checks that every ticked channel has a texture on it. If not, the *Create Missing 3D Textures* question appears. If you decline, a message says those channels will not be painted. Surfaces that cannot take a channel (for example CSG shapes) are reported instead of silently skipped.

## Height, occlusion and emission settings

A texture only describes the data. How it looks also depends on material settings. When you paint with a material, GDDraw copies these to the painted material once, undoable: the height scale, deep parallax, layer counts and flips, the ambient-occlusion light effect and the emission energy. A texture set or shader has no such settings, so its height map gets deep parallax with 8-32 layers.

You can adjust them afterwards in the material's Inspector: **Heightmap > Scale** and **Min/Max Layers**. Godot's layered parallax shows its layers as steps at glancing angles when the scale is high; lowering the scale or raising the layers removes them. Values you change in the Inspector are never put back by GDDraw.

## Saving

Undo and redo cover all painted channels. Saving writes each texture once. See [Paint Channels](paint-channels.md) for how textures are created and kept out of your scenes.

## Limits

- Painting into the texture inputs of a `ShaderMaterial` is not supported; shaders are used as brush sources only.
- Normal maps are not generated from height maps.
- The brush size is limited to 512 pixels.