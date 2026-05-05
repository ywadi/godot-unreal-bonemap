@tool
extends EditorScript

# Round-trip validator: loads the saved profile and the source skeleton,
# verifies every bone matches in name, parent, and reference pose.
#
# Run from Script editor (Ctrl+Shift+X).

const SCENE_PATH   := "res://addons/godot_unreal_bonemap/source_scripts/SKM_Manny.fbx"
const PROFILE_PATH := "res://addons/godot_unreal_bonemap/ue5_mannequin_profile.tres"
const REPORT_PATH  := "res://addons/godot_unreal_bonemap/source_scripts/validation_report.txt"

# Tolerances for numeric comparison (rest poses come straight from the skeleton,
# so this should be effectively exact — wide tolerances would mask bugs).
const POS_EPS   := 0.0001
const ROT_EPS   := 0.0001
const SCALE_EPS := 0.0001

func _run() -> void:
	var profile: SkeletonProfile = load(PROFILE_PATH)
	if profile == null:
		push_error("Could not load " + PROFILE_PATH)
		return

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

	var lines: Array[String] = []
	lines.append("# UE5 Mannequin profile validation report")
	lines.append("# Profile:  " + PROFILE_PATH)
	lines.append("# Skeleton: " + SCENE_PATH)
	lines.append("")

	var skel_count := skel.get_bone_count()
	var prof_count := profile.bone_size
	lines.append("Bone count: skeleton=" + str(skel_count) + " profile=" + str(prof_count))
	if skel_count != prof_count:
		lines.append("FAIL: bone count mismatch")
	lines.append("")

	# Index bones by name on both sides
	var skel_by_name := {}
	for i in skel_count:
		skel_by_name[String(skel.get_bone_name(i))] = i
	var prof_by_name := {}
	for i in prof_count:
		prof_by_name[String(profile.get_bone_name(i))] = i

	var failures: Array[String] = []

	# Forward check: every profile bone must exist in skeleton with matching parent + rest
	for i in prof_count:
		var pname := String(profile.get_bone_name(i))
		if not skel_by_name.has(pname):
			failures.append("MISSING IN SKELETON: " + pname)
			continue

		var si: int = skel_by_name[pname]

		# Parent name match
		var prof_parent := String(profile.get_bone_parent(i))
		var skel_parent_idx := skel.get_bone_parent(si)
		var skel_parent := String(skel.get_bone_name(skel_parent_idx)) if skel_parent_idx >= 0 else ""
		if prof_parent != skel_parent:
			failures.append("PARENT MISMATCH: " + pname + "  profile='" + prof_parent + "'  skeleton='" + skel_parent + "'")

		# Reference pose vs rest pose (per-component tolerance)
		var ref_pose: Transform3D = profile.get_reference_pose(i)
		var rest_pose: Transform3D = skel.get_bone_rest(si)
		var pos_diff := (ref_pose.origin - rest_pose.origin).length()
		var rot_diff := _basis_diff(ref_pose.basis, rest_pose.basis)
		if pos_diff > POS_EPS or rot_diff > ROT_EPS:
			failures.append(
				"REST DRIFT: " + pname
				+ "  pos_diff=" + str(pos_diff)
				+ "  rot_diff=" + str(rot_diff)
			)

	# Reverse check: every skeleton bone must be in profile
	for sname in skel_by_name.keys():
		if not prof_by_name.has(sname):
			failures.append("MISSING IN PROFILE: " + String(sname))

	# Profile-level metadata
	if String(profile.root_bone) != "root":
		failures.append("root_bone is '" + String(profile.root_bone) + "', expected 'root'")
	if String(profile.scale_base_bone) != "pelvis":
		failures.append("scale_base_bone is '" + String(profile.scale_base_bone) + "', expected 'pelvis'")

	lines.append("Failures: " + str(failures.size()))
	if failures.is_empty():
		lines.append("PASS: profile and skeleton match exactly.")
	else:
		lines.append("FAIL:")
		for f in failures:
			lines.append("  - " + f)

	for l in lines:
		print(l)

	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f != null:
		for l in lines:
			f.store_line(l)
		f.close()
		print("\nWrote report to: " + REPORT_PATH)

	root.queue_free()


func _basis_diff(a: Basis, b: Basis) -> float:
	# Frobenius-norm distance between rotation matrices: max element-wise diff.
	var max_d := 0.0
	for col in 3:
		var ac: Vector3 = a[col]
		var bc: Vector3 = b[col]
		max_d = max(max_d, abs(ac.x - bc.x))
		max_d = max(max_d, abs(ac.y - bc.y))
		max_d = max(max_d, abs(ac.z - bc.z))
	return max_d


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null
