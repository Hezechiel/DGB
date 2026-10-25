# Duel of Gods: Babylon — 2D Map Art Style

**Version:** 0.1  
**Status:** Approved for prototyping  
**Scope:** Map terrain and environmental assets only

This document defines the current visual standard for creating 2D map components for Duel of Gods: Babylon (DGB). The immediate goal is to build a usable map from a consistent set of terrain tiles, cliff edges, and simple environmental props.

This is a working standard. Validate it by assembling assets in the game before expanding it into a final art bible.

## 1. Current visual direction

**Style name:** Stylized Low-Poly-Inspired 2D Illustration

The artwork is genuinely 2D. The low-poly influence comes from simplified angular shapes, broad color regions, and restrained faceted shading—not from 3D models or renders.

### Viewpoint

Use the established **oblique 2D viewpoint** shown in the DGB reference tower: top surfaces and front-facing surfaces are visible. Match this viewpoint consistently across map components. Depth and lighting are illustrated directly into the 2D artwork.

Do not switch to a straight top-down view, a different isometric angle, or a 3D-rendered appearance unless the project’s viewpoint is deliberately revised.

### Shape and rendering language

- Bold, readable silhouettes and simplified angular forms.
- Broad color regions with restrained, hand-painted tonal variation.
- Warm, earthy colors: sandstone, terracotta, ochre, brown, and muted green where appropriate.
- Soft-looking illustrated light and shadow; no photorealistic textures.
- Moderate detail: enough to give terrain character, but not so much that tiles become noisy or distract from gameplay.
- Consistent apparent scale, viewpoint, edge treatment, palette, and shading across all map assets.

### Gameplay readability

Map artwork should establish the arena without competing with future gameplay elements. Keep the ground visually calmer than units and combat effects will need to be. Make cliffs and terrain boundaries easy to distinguish from walkable ground.

## 2. Master style prompt

Use this unchanged as the style foundation for map-asset generation. Add one specific asset request and its technical requirements after it.

> **DUEL OF GODS: BABYLON — 2D MAP ART STYLE**
>
> Create a production-oriented 2D map asset for Duel of Gods: Babylon (DGB), a competitive mythological MOBA.
>
> **Strictly 2D artwork:** Create a flat 2D illustration suitable for a 2D game engine such as Godot. Do not create 3D models, 3D renders, 3D scenes, or assets that look like rendered 3D objects. All depth, lighting, and shading must be illustrated directly into the 2D artwork.
>
> **Visual style:** Stylized low-poly-inspired 2D illustration. Use simplified angular shapes, broad color regions, clean silhouettes, restrained geometric detail, and controlled illustrated shading. The low-poly influence must come from the shapes and color blocking, not actual 3D geometry.
>
> **Fixed viewpoint:** Match the established oblique 2D viewpoint of the DGB reference tower, showing top surfaces and front-facing surfaces where appropriate. Keep this viewpoint consistent with the other map assets.
>
> **Palette and materials:** Use a cohesive, warm palette inspired by sandstone, terracotta, ochre, earthy brown, and muted natural greens where appropriate. Use matte-looking surfaces and restrained highlights and shadows. Avoid photorealistic textures, noisy detail, and excessive ornamentation.
>
> **Map readability:** Prioritize clear terrain shapes, readable boundaries, and a consistent visual scale. Map components must fit into one coherent modular environment and remain visually quieter than future gameplay units and effects.
>
> Create only the requested map asset. Follow the requested dimensions, tile layout, transparency, and intended in-game use. Do not add mockups, UI elements, labels, watermarks, unrelated objects, or a 3D-rendered scene.

## 3. Map tiles and terrain prompt

Append this block when generating ground tiles, paths, cliff edges, or terrain sets.

> **2D MAP TILE / TERRAIN REQUIREMENTS**
>
> Create the specific 2D map tiles or terrain components described in the request. Keep the established DGB oblique 2D viewpoint, visual scale, palette, shading, and edge treatment consistent.
>
> For ground tiles, create clearly defined, modular surfaces intended to be arranged into a larger map. When seamless tiling is explicitly requested, design adjacent edges to connect without visible seams. Do not assume that every tile must be seamless; follow the individual request.
>
> For cliffs and terrain-edge pieces, clearly distinguish the upper walkable surface from the vertical front face. Keep the shapes readable and make the boundaries between walkable and blocked terrain visually obvious.
>
> For isolated props and overlays, use a true transparent background when requested. For ground tiles, use the requested background and edge behavior.
>
> Follow the specified canvas size, tile size, layout, and transparency requirements. Do not replace the requested tiles with a complete map, a 3D scene, or a presentation sheet.

## 4. Initial visual reference

The first generated terrain sheet containing sandstone ground tiles, grassy ground tiles, and cliff-edge pieces is the initial visual reference for this style.

Use it as a comparison reference when generating additional map components. Preserve its overall illustrated 2D treatment, warm earthy palette, angular simplified forms, oblique viewpoint, and restrained hand-painted shading.

The image is a **style reference**, not proof that every tile is technically seamless or ready to import. Test tile connections, transparency, dimensions, and in-game readability in Godot before treating those properties as approved.

## 5. Current scope and workflow

### In scope now

1. Ground tiles and terrain variants.
2. Cliff edges and terrain boundaries.
3. Simple environmental props needed to assemble the map.

### Not in scope yet

Character and unit spritesheets, building sets, spell effects, animation standards, and a complete game-wide art bible. These can receive separate standards after the map-art approach has been tested in the game.

### Recommended workflow

1. Generate one small group of related terrain assets using the master prompt and the initial visual reference.
2. Assemble them in Godot and inspect them at the intended gameplay zoom.
3. Check for visible seams, inconsistent viewpoint, inconsistent scale, distracting detail, and unclear walkable boundaries.
4. Adjust the prompt only when testing reveals a specific problem.
5. Update this document when a visual or technical rule has been validated in practice.

## 6. Technical details to confirm

Do not assume values that have not yet been established. Record them here once confirmed:

- Standard ground-tile dimensions: **To be determined**
- Standard map-art scale in Godot: **To be determined**
- Required file format and alpha-channel workflow: **To be determined**
- Which tile categories must be seamless: **To be determined**
- Final approved reference image location: **To be added to project**

---

**Working rule:** For now, optimize for a coherent, usable 2D map—not for every category of game asset at once.
