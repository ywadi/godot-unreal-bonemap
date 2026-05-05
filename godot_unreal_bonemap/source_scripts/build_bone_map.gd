@tool
extends EditorScript

# Builds a BoneMap that maps the UE5 profile's bones to a UE5-named skeleton
# by exact name match. Overwrites the plugin's bone map resource.
#
# Run from the Script editor (Ctrl+Shift+X).
# Inputs: the plugin's profile + the source FBX.
# Output: addons/godot_unreal_bonemap/ue5_bone_map.tres (the plugin's bone map)

const PROFILE_PATH  := "res://addons/godot_unreal_bonemap/ue5_mannequin_profile.tres"
const SCENE_PATH    := "res://addons/godot_unreal_bonemap/source_scripts/SKM_Manny.fbx"
const BONE_MAP_PATH := "res://addons/godot_unreal_bonemap/ue5_bone_map.tres"

func _run() -> void:
	var profile: SkeletonProfile = load(PROFILE_PATH)
	if profile == null:
		push_error("Could not load profile: " + PROFILE_PATH)
		return

	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("Could not load scene: " + SCENE_PATH)
		return
	var root: Node = packed.instantiate()
	var skel: Skeleton3D = _find_skeleton(root)
	if skel == null:
		push_error("No Skeleton3D under " + SCENE_PATH)
		root.queue_free()
		return

	# Index skeleton bone names for fast lookup
	var skel_names := {}
	for i in skel.get_bone_count():
		skel_names[String(skel.get_bone_name(i))] = true

	var bm := BoneMap.new()
	bm.profile = profile

	var matched := 0
	var unmatched: Array[String] = []

	for i in profile.bone_size:
		var pname := String(profile.get_bone_name(i))
		if skel_names.has(pname):
			bm.set_skeleton_bone_name(StringName(pname), StringName(pname))
			matched += 1
		else:
			unmatched.append(pname)

	var err := ResourceSaver.save(bm, BONE_MAP_PATH)
	if err != OK:
		push_error("Failed to save BoneMap (err " + str(err) + ")")
	else:
		print("Wrote BoneMap to: " + BONE_MAP_PATH)
		print("  Matched:    " + str(matched) + " / " + str(profile.bone_size))
		print("  Unmatched:  " + str(unmatched.size()))
		for u in unmatched:
			print("    - " + u)

	root.queue_free()


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null
