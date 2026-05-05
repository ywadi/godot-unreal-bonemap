@tool
extends EditorScript

# One-shot extractor: loads a UE5 mannequin FBX, walks its Skeleton3D,
# and dumps every bone's name, parent, and rest transform. Used as the
# first inspection step when (re)building the plugin's resources.
#
# Setup:
#   Drop the source FBX (e.g. SKM_Manny.fbx exported from Unreal) into
#   this folder, then update SCENE_PATH below if the filename differs.
#
# Run from the Script editor with Ctrl+Shift+X.
# Output: bone_dump.txt next to this script.

const SCENE_PATH := "res://addons/godot_unreal_bonemap/source_scripts/SKM_Manny.fbx"
const DUMP_PATH  := "res://addons/godot_unreal_bonemap/source_scripts/bone_dump.txt"

func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("Could not load %s" % SCENE_PATH)
		return

	var root: Node = packed.instantiate()
	var skel: Skeleton3D = _find_skeleton(root)
	if skel == null:
		push_error("No Skeleton3D found under %s" % SCENE_PATH)
		root.queue_free()
		return

	var lines: Array[String] = []
	lines.append("# UE5 Mannequin bone dump")
	lines.append("# Source: " + SCENE_PATH)
	lines.append("# Skeleton node name: " + skel.name)
	lines.append("# Bone count: " + str(skel.get_bone_count()))
	lines.append("")

	# Categorize for a quick scope summary
	var counts := {
		"spine":       0,
		"neck":        0,
		"twist":       0,
		"ik":          0,
		"metacarpal":  0,
		"finger":      0,
		"foot":        0,
		"hand":        0,
		"other":       0,
	}
	var finger_roots := ["thumb", "index", "middle", "ring", "pinky"]

	for i in skel.get_bone_count():
		var name := skel.get_bone_name(i)
		var parent_idx := skel.get_bone_parent(i)
		var parent_name := skel.get_bone_name(parent_idx) if parent_idx >= 0 else "<ROOT>"
		var rest: Transform3D = skel.get_bone_rest(i)
		var pos := rest.origin
		var euler := rest.basis.get_euler()  # radians
		var euler_deg := Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z))

		var line := (
			"[" + str(i).lpad(3) + "] "
			+ name.rpad(30) + "  parent=" + parent_name.rpad(30)
			+ "  pos=(" + _f(pos.x) + ", " + _f(pos.y) + ", " + _f(pos.z) + ")"
			+ "  euler_deg=(" + _f(euler_deg.x, 2) + ", " + _f(euler_deg.y, 2) + ", " + _f(euler_deg.z, 2) + ")"
		)
		lines.append(line)

		var lower := name.to_lower()
		if   "twist"      in lower: counts.twist += 1
		elif "metacarpal" in lower: counts.metacarpal += 1
		elif lower.begins_with("ik_"): counts.ik += 1
		elif lower.begins_with("spine"): counts.spine += 1
		elif lower.begins_with("neck"):  counts.neck  += 1
		elif lower.begins_with("foot") or lower.begins_with("ball"): counts.foot += 1
		elif lower.begins_with("hand"): counts.hand += 1
		else:
			var matched_finger := false
			for f in finger_roots:
				if lower.begins_with(f):
					counts.finger += 1
					matched_finger = true
					break
			if not matched_finger:
				counts.other += 1

	lines.append("")
	lines.append("# Bone category counts")
	for k in counts.keys():
		lines.append("#   " + String(k).rpad(12) + " = " + str(counts[k]))

	# Print to Output
	for l in lines:
		print(l)

	# Write to disk
	var f := FileAccess.open(DUMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not write " + DUMP_PATH + " (err " + str(FileAccess.get_open_error()) + ")")
	else:
		for l in lines:
			f.store_line(l)
		f.close()
		print("\nWrote dump to: " + DUMP_PATH)

	root.queue_free()


# Padded fixed-precision float, sign-aligned with a leading space for non-negative.
func _f(v: float, decimals: int = 4) -> String:
	var s := String.num(v, decimals)
	if not s.begins_with("-"):
		s = " " + s
	return s.lpad(decimals + 4)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null
