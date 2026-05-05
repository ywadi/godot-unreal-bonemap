# Godot Unreal BoneMap — Source Scripts

These four scripts are the build pipeline for the plugin's two shipped resources:

- `ue5_mannequin_profile.tres` — the canonical UE5 `SkeletonProfile` (89 bones, anatomical rest pose)
- `ue5_bone_map.tres` — pre-populated `BoneMap` mapping the profile to a UE5-named skeleton

You only need to run these if you want to **regenerate** those resources — for example, to retarget at a stripped-down skeleton (no IK, no twists), to add face bones for MetaHuman, or to update for a new UE skeleton variant. **For normal use of the plugin you never need to touch this folder.**

## Prerequisites

- A UE5 mannequin source FBX exported from Unreal Engine. Easiest source:
  1. Open Unreal, navigate to `Content/Characters/Mannequins/Meshes/SKM_Manny` (or `SKM_Quinn`).
  2. Right-click → **Asset Actions → Export…** → save as `.fbx`.
  3. In the FBX export dialog: **Skeletal Mesh ON**, **Export Animations OFF**. Other settings default.
- Drop the resulting file into this folder. By default scripts expect `SKM_Manny.fbx`. If you name it differently, update `SCENE_PATH` at the top of each script.

## Run order

Run each script as a Godot `EditorScript`: open it in the Script editor, press **Ctrl+Shift+X** (or **File → Run**). Output goes to the editor's Output panel and to disk.

| # | Script | Input | Output | Why |
|---|---|---|---|---|
| 1 | `extract_bones.gd` | `SKM_Manny.fbx` | `bone_dump.txt` | Inspection. Lists every bone, parent, and rest transform. Sanity check that the FBX imported with the bones you expect (~89 for the full UE5 mannequin). |
| 2 | `build_profile.gd` | `SKM_Manny.fbx` | `../ue5_mannequin_profile.tres` | Builds the SkeletonProfile from the FBX's skeleton. Reference poses are taken **straight from the skeleton's rest pose**, preserving the UE5 A-pose, spine S-curve, and chin-down tilt. |
| 3 | `build_bone_map.gd` | profile + `SKM_Manny.fbx` | `../ue5_bone_map.tres` | Builds the BoneMap by exact name match (UE5 source bone names == profile bone names, so all 89 entries auto-fill). |
| 4 | `validate_profile.gd` | profile + `SKM_Manny.fbx` | `validation_report.txt` | Round-trip check. Confirms every bone in the profile exists in the skeleton, parent names match, and reference poses match within `1e-4`. Should report `Failures: 0`. |

After step 4 passes, commit the regenerated `.tres` files. The plugin's runtime behavior changes accordingly on next reimport.

## Common reasons to regenerate

- **Switch to a stripped skeleton** — open `build_profile.gd` and filter out bones you don't want (e.g. skip everything containing `twist`, or names starting with `ik_`). Reduces bone count, simplifies the BoneMap, but may break animations that reference filtered bones.
- **Add face bones** (MetaHuman) — export `SKM_MetaHuman` (or your custom MetaHuman head rig) instead of `SKM_Manny`. `extract_bones.gd` will report 200+ bones; the profile builder handles the count automatically. Group `Face` will populate.
- **UE6 / new mannequin variant** — replace the source FBX, re-run all four scripts, validate, ship.

## Notes

- Scripts load `.fbx` files directly; no need to wrap them in a `.tscn` first.
- `build_profile.gd` and `build_bone_map.gd` overwrite the plugin's shipped `.tres` files in `../`. Diff with git before committing if you want to review what changed.
- Godot's Script editor caches compiled scripts. If you edit a script externally and your changes don't seem to apply, close and reopen the script tab (or restart the editor) before re-running.
