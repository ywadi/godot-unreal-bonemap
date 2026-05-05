@tool
extends EditorScript

# Builds a SkeletonProfile resource that mirrors the UE5 Mannequin exactly:
# every bone name, parent, tail, group, and reference pose is taken straight
# from the imported source FBX. Overwrites the plugin's profile resource.
#
# Run from the Script editor (open this file, Ctrl+Shift+X).
# Input:  source_scripts/SKM_Manny.fbx
# Output: addons/godot_unreal_bonemap/ue5_mannequin_profile.tres (the plugin's profile)

const SCENE_PATH   := "res://addons/godot_unreal_bonemap/source_scripts/SKM_Manny.fbx"
const PROFILE_PATH := "res://addons/godot_unreal_bonemap/ue5_mannequin_profile.tres"

const FINGER_PREFIXES := ["index_", "middle_", "ring_", "pinky_", "thumb_"]

func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("Could not load " + SCENE_PATH)
		return

	var root: Node = packed.instantiate()
	var skel: Skeleton3D = _find_skeleton(root)
	if skel == null:
		push_error("No Skeleton3D under " + SCENE_PATH)
		root.queue_free()
		return

	var bone_count := skel.get_bone_count()

	# Build parent -> children map so we can pick a tail bone for each entry.
	var children := {}
	for i in bone_count:
		var p := skel.get_bone_parent(i)
		if p >= 0:
			if not children.has(p):
				children[p] = []
			children[p].append(i)

	var profile := SkeletonProfile.new()
	profile.root_bone = &"root"
	profile.scale_base_bone = &"pelvis"

	# Four standard groups (Face stays empty for the base UE5 skeleton).
	profile.group_size = 4
	profile.set_group_name(0, &"Body")
	profile.set_group_name(1, &"Face")
	profile.set_group_name(2, &"LeftHand")
	profile.set_group_name(3, &"RightHand")

	profile.bone_size = bone_count

	var by_group := {"Body": 0, "Face": 0, "LeftHand": 0, "RightHand": 0}

	for i in bone_count:
		var bname := skel.get_bone_name(i)
		var parent_idx := skel.get_bone_parent(i)
		var parent_name := skel.get_bone_name(parent_idx) if parent_idx >= 0 else ""

		var tail_name := ""
		if children.has(i) and (children[i] as Array).size() > 0:
			tail_name = skel.get_bone_name((children[i] as Array)[0])

		var group := _group_for(bname)
		by_group[group] += 1

		var rest: Transform3D = skel.get_bone_rest(i)

		profile.set_bone_name(i, StringName(bname))
		profile.set_bone_parent(i, StringName(parent_name))
		profile.set_bone_tail(i, StringName(tail_name))
		profile.set_group(i, StringName(group))
		profile.set_reference_pose(i, rest)
		profile.set_required(i, true)

	var err := ResourceSaver.save(profile, PROFILE_PATH)
	if err != OK:
		push_error("Failed to save profile (err " + str(err) + ")")
	else:
		print("Wrote profile to: " + PROFILE_PATH)
		print("  Total bones:  " + str(bone_count))
		print("  Body:         " + str(by_group["Body"]))
		print("  Face:         " + str(by_group["Face"]))
		print("  LeftHand:     " + str(by_group["LeftHand"]))
		print("  RightHand:    " + str(by_group["RightHand"]))

	root.queue_free()


func _group_for(bname: String) -> String:
	var l := bname.to_lower()
	if l.ends_with("_l"):
		for f in FINGER_PREFIXES:
			if l.begins_with(f):
				return "LeftHand"
	if l.ends_with("_r"):
		for f in FINGER_PREFIXES:
			if l.begins_with(f):
				return "RightHand"
	return "Body"


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null
