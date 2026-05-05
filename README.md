# Godot Unreal BoneMap

Drop-in plugin that lets Godot 4 play **Unreal Engine 5 Mannequin animations on UE5 Mannequin characters** with no retargeting loss. No T-pose snapping, no spine straightening, no chin-up artifacts — the imported skeleton matches the source one-to-one, and animation tracks apply directly.

If you've ever fought Mixamo → Godot retargeting, this is the alternative: standardize on the UE5 skeleton end-to-end and skip retargeting entirely. The plugin batches the correct import settings across selected files via right-click.

---

## Why this exists

Godot 4 ships with a humanoid retargeting pipeline (`SkeletonProfileHumanoid` + `BoneMap` + Fix Silhouette) designed to bridge **different** skeletons (e.g. Mixamo T-pose ↔ Godot humanoid A-pose). It works, but always at a cost: spine articulation gets flattened to 3 bones, fingers shift, the rest pose is normalized away from anatomical detail. Crisp UE-style motion suffers.

This plugin takes the opposite approach: **don't retarget**. Use the **same skeleton** on both sides — UE5's 89-bone Mannequin (with full 5-bone spine, 2 neck bones, twist bones, metacarpals, IK helpers, A-pose with anatomical curve and chin-down). Animations exported from Unreal play 1:1 because nothing is being converted.

Trade-off: every character and animation must use the UE5 Mannequin skeleton. In return, you keep all of UE's animation fidelity.

---

## Requirements

- **Godot 4.4 or later** (tested on 4.6 stable)
- Project's FBX importer set to **ufbx** (Project Settings → Filesystem → Import → FBX → Importer = `ufbx`). The legacy FBX2glTF importer also works *if* you have the binary installed, but ufbx is built-in and simpler.
- Source assets must use the UE5 Mannequin skeleton (`SK_Mannequin` — the one shared by Manny, Quinn, and MetaHuman). Mixamo characters, custom rigs, and UE4 Mannequin assets won't work without first re-rigging them to UE5.

---

## Installation

1. Copy or clone this repo's `addons/godot_unreal_bonemap/` folder into your project's `addons/` folder.
2. Open your project in Godot.
3. **Project → Project Settings → Plugins** → tick **Enable** for **Godot Unreal BoneMap**.
4. The Output panel should show `Unreal BoneMap: Initialized (found N popups)`.

---

## Usage

### Step 1 — Apply to your character

1. In FileSystem, right-click your character `.fbx` (or `.glb` / `.gltf`).
2. Select **Apply UE5 BoneMap to Selected** (at the bottom of the menu, under the *Unreal BoneMap* separator).
3. Dialog: **No (skip export)** — characters don't have animations to extract.
4. The character reimports with the correct settings and the skeleton node is renamed to `GeneralSkeleton`.

### Step 2 — Apply to your animations

1. Multi-select all UE5 animation files in FileSystem.
2. Right-click → **Apply UE5 BoneMap to Selected**.
3. Dialog options:
   - **Yes (pick folder)** — saves each animation as a standalone `.res` file in a folder you choose. Useful for `AnimationLibrary` workflows.
   - **No (skip export)** — just applies the import settings. Animations stay embedded in the imported scenes.
4. The plugin batches all selected files into a single reimport at the end.

### Step 3 — Use them

Instance the character into your scene, attach an `AnimationPlayer` (or use the one from import), and play the animations. They should:
- Stand upright at the origin
- Match the UE5 A-pose at frame 0
- Animate smoothly with full spine, neck, finger, and IK bone movement
- Share the `GeneralSkeleton` node name across all imports, so animation tracks resolve cleanly

---

## What the plugin sets per file

When you run *Apply UE5 BoneMap*, the plugin writes these to each selected file's `.import`:

| Setting | Value | Why |
|---|---|---|
| `retarget/bone_map` | `ue5_bone_map.tres` | Maps the UE5 SkeletonProfile to the imported skeleton (all 89 bones) |
| `retarget/rest_fixer/fix_silhouette/enable` | **`false`** | Profile and skeleton share identical rest poses; running the silhouette fix would corrupt them |
| `retarget/rest_fixer/retarget_method` | **`1` (Overwrite Axis)** | Required when the bone renamer is on; rebakes tracks against the profile's reference axes so root + pelvis stay aligned |
| `retarget/bone_renamer/rename_bones` | `true` | No-op for UE5 names but unlocks the skeleton node rename below |
| `retarget/bone_renamer/unique_node/skeleton_name` | `GeneralSkeleton` | Unifies the `Skeleton3D` node name across every imported asset so animation track paths resolve everywhere |
| `retarget/remove_tracks/unmapped_bones` | `false` | All bones are mapped; nothing to remove |

> **Important:** Even if you assign the BoneMap manually instead of using the plugin, **Fix Silhouette must be OFF** and **Retarget Method must be Overwrite Axis** for both your character and your animations. Mixing these settings (e.g. Fix Silhouette ON with Overwrite Axis OFF, or rename ON with Overwrite Axis OFF) leaves the skeleton in a half-processed state where the pelvis floats, the rest pose drifts, and animations don't play correctly.

---

## Files in this plugin

| File | Type | Purpose |
|---|---|---|
| `plugin.cfg` | manifest | Tells Godot how to load the plugin |
| `plugin.gd` | EditorPlugin | Adds the right-click menu and applies import settings in batch |
| `ue5_mannequin_profile.tres` | `SkeletonProfile` | The 89-bone UE5 template with anatomical rest pose |
| `ue5_bone_map.tres` | `BoneMap` | Pre-populated mapping (89/89 matches against UE5-named skeletons) |
| `source_scripts/` | folder | Build-time scripts for regenerating the two `.tres` files. See [`source_scripts/README.md`](source_scripts/README.md). Not needed for normal use. |

---

## Troubleshooting

### "The selected resource (BoneMap) does not match any type expected for this property (SkeletonProfile)"
You assigned `ue5_bone_map.tres` to a `SkeletonProfile` slot. The BoneMap goes in the import dock's **BoneMap** field; the SkeletonProfile lives **inside** the BoneMap and is already wired up. Don't touch the Profile slot — assign only the BoneMap.

### Custom SkeletonProfile shows a black box with one pink dot in the BoneMap editor
Cosmetic only — Godot's BoneMap editor draws a body silhouette only for `SkeletonProfileHumanoid`. Custom profiles render as a black canvas with all 89 handle dots stacked at (0,0). Doesn't affect retargeting; the plugin pre-populates the BoneMap so you don't need that UI.

### Character imports lying on its back / rotated 90°
Two common causes:
1. **FBX importer mismatch** — confirm Project Settings → Filesystem → Import → FBX → Importer is `ufbx`.
2. **Front-axis mismatch in the source FBX** — re-export from Unreal with **Force Front X Axis ON** in the FBX export advanced options.

### Pelvis floats / model below origin / pose looks wrong after import
You're missing one of the two critical settings. Verify in the file's Import dock:
- **Fix Silhouette** = OFF
- **Retarget Method** = **Overwrite Axis** (not None, not Use Modifier)

If those are set correctly and it's still wrong, run the plugin's *Apply UE5 BoneMap* on the file once more — the plugin sets all six retargeting flags atomically.

### Animation only moves the root bone
The animation FBX has stripped per-bone keys, or the animation file's skeleton differs from the character's. Open the animation as a standalone scene, click the AnimationPlayer, look at the track count — should be 100+ tracks for a typical UE animation. If you see only 1–3, re-export from Unreal with **Export Animations: ON** and confirm the source file actually contains skeletal animation.

### `UID duplicate detected` warnings
Two `.tres` files share the same UID (typically because the plugin folder was copied somewhere else in the project). Find and remove the duplicate; the canonical files live in `addons/godot_unreal_bonemap/`.

### `Could not create child process … FBX2glTF`
Your project is set to the FBX2glTF importer but the binary isn't installed. Switch to ufbx in Project Settings (recommended) or install [FBX2glTF](https://github.com/godotengine/FBX2glTF) and point Godot at it.

---

## Customizing the skeleton

Want to retarget against a different UE skeleton variant (stripped IK, MetaHuman with face bones, UE4 Mannequin)? See [`source_scripts/README.md`](source_scripts/README.md) for the regeneration pipeline. You'll drop a different source FBX into `source_scripts/`, run four scripts in order, and ship the new `.tres` files.

---

## License

MIT.
