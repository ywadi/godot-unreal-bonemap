@tool
extends EditorPlugin

## Godot Unreal BoneMap plugin for Godot 4.x
##
## Right-click selected FBX/GLB/GLTF files in the FileSystem dock to apply the
## UE5 BoneMap and the correct importer settings, then optionally save the
## resulting animations as .res files in a chosen export folder.
##
## Settings applied per file (different from cross-skeleton retargeting):
##   - fbx/importer = 1 (ufbx, fixes Z-up axis rotation for UE FBX)
##   - retarget/bone_map = ue5_bone_map.tres
##   - retarget/rest_fixer/fix_silhouette/enable = false
##     (profile and skeleton share identical rest poses, no fix needed)
##   - retarget/rest_fixer/retarget_method = 0 (None)
##     (1:1 same-skeleton playback, no retarget modifier)
##
## Bone names are NOT renamed — UE5 names are kept end-to-end.

const PLUGIN_DIR := "res://addons/godot_unreal_bonemap"
const BONE_MAP_PATH := PLUGIN_DIR + "/ue5_bone_map.tres"

var retarget_menu_id := 10004
var _is_initialized: bool = false
var _all_popups: Array[PopupMenu] = []


func _enter_tree():
	call_deferred("_initialize_plugin")


func _exit_tree():
	_cleanup_connections()


func _initialize_plugin():
	await get_tree().create_timer(0.5).timeout

	var fs_dock = get_editor_interface().get_file_system_dock()
	if not fs_dock:
		push_error("Unreal BoneMap: Could not get FileSystemDock")
		return

	_all_popups.clear()
	_find_all_popups(fs_dock)

	for i in range(_all_popups.size()):
		var popup = _all_popups[i]
		if not popup.about_to_popup.is_connected(_on_any_popup_about_to_show):
			popup.about_to_popup.connect(_on_any_popup_about_to_show.bind(i, popup))

	_is_initialized = true
	print("Unreal BoneMap: Initialized (found %d popups)" % _all_popups.size())


func _find_all_popups(node: Node):
	if node is PopupMenu:
		_all_popups.append(node as PopupMenu)
	for child in node.get_children(true):
		_find_all_popups(child)


func _cleanup_connections():
	for popup in _all_popups:
		if is_instance_valid(popup):
			if popup.id_pressed.is_connected(_on_popup_id_pressed):
				popup.id_pressed.disconnect(_on_popup_id_pressed)


func _on_any_popup_about_to_show(_index: int, popup: PopupMenu):
	if popup.item_count < 2:
		return
	_add_menu_item_to_popup(popup)


func _add_menu_item_to_popup(popup: PopupMenu):
	var idx = popup.get_item_index(retarget_menu_id)
	if idx != -1:
		popup.remove_item(idx)
		if idx > 0 and popup.is_item_separator(idx - 1):
			popup.remove_item(idx - 1)

	popup.add_separator("Unreal BoneMap")
	popup.add_item("Apply UE5 BoneMap to Selected", retarget_menu_id)

	if not popup.id_pressed.is_connected(_on_popup_id_pressed):
		popup.id_pressed.connect(_on_popup_id_pressed)


func _on_popup_id_pressed(id: int):
	if id == retarget_menu_id:
		_run_retarget()


# ============================================================
# MAIN WORKFLOW
# ============================================================

func _run_retarget():
	var fs_tree = _get_filesystem_tree()
	if not fs_tree:
		push_error("Unreal BoneMap: FileSystem tree not found.")
		return

	var selected_paths = _get_selected_paths(fs_tree)
	var valid_files = selected_paths.filter(func(path):
		var ext = path.to_lower().get_extension()
		return ext in ["fbx", "glb", "gltf"]
	)

	if valid_files.is_empty():
		push_warning("Unreal BoneMap: No FBX/GLB/GLTF files selected.")
		return

	# Ask whether to save animations as .res files. If yes, prompt for folder.
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Save extracted animations as .res files?\n\nYes  = pick an export folder\nNo   = apply BoneMap only (no .res export)\n\nFiles selected: %d" % valid_files.size()
	dialog.title = "Unreal BoneMap — Apply BoneMap"
	dialog.get_ok_button().text = "Yes (pick folder)"
	dialog.add_cancel_button("No (skip export)")
	dialog.confirmed.connect(func(): _show_export_dialog(valid_files))
	dialog.canceled.connect(func(): _process_files(valid_files, ""))
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered()


func _show_export_dialog(file_paths: Array) -> void:
	var fd := EditorFileDialog.new()
	fd.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	fd.access = EditorFileDialog.ACCESS_RESOURCES
	fd.title = "Select Export Folder for Retargeted UE5 Animations"
	fd.dir_selected.connect(func(dir_path): _process_files(file_paths, dir_path))
	fd.visibility_changed.connect(func():
		if not fd.visible:
			fd.queue_free()
	)
	get_editor_interface().get_base_control().add_child(fd)
	fd.popup_centered_ratio(0.4)


func _process_files(file_paths: Array, export_dir: String) -> void:
	var modified: Array[String] = []
	for fp in file_paths:
		if _write_import_settings(fp, export_dir):
			modified.append(fp)
	print("Unreal BoneMap: Updated import settings for %d / %d files." % [modified.size(), file_paths.size()])

	if modified.is_empty():
		return

	# Single batch reimport — avoids the progress_dialog race that nested
	# call_deferred chains trigger.
	var ef = get_editor_interface().get_resource_filesystem()
	ef.reimport_files(modified)
	print("Unreal BoneMap: Reimported %d file(s)." % modified.size())


func _write_import_settings(file_path: String, export_dir: String) -> bool:
	var import_path := file_path + ".import"
	if not FileAccess.file_exists(import_path):
		push_warning("Unreal BoneMap: No .import for %s — open it once in the Import dock first." % file_path)
		return false

	var bone_map: Resource = null
	if ResourceLoader.exists(BONE_MAP_PATH):
		bone_map = load(BONE_MAP_PATH)
	else:
		push_error("Unreal BoneMap: BoneMap not found at " + BONE_MAP_PATH)
		return false

	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		push_error("Unreal BoneMap: Failed to read " + import_path)
		return false

	# NOTE: We do NOT touch fbx/importer here. That setting is project-wide
	# and is the user's choice (Project Settings -> Filesystem -> Import -> FBX).
	# Touching it per-file with the wrong value can break files that depend on
	# the FBX2glTF binary (which may not be installed).

	# Skeleton3D node settings
	var sub: Dictionary = cfg.get_value("params", "_subresources", {})
	if not sub.has("nodes"):
		sub["nodes"] = {}
	if not sub["nodes"].has("PATH:Skeleton3D"):
		sub["nodes"]["PATH:Skeleton3D"] = {}
	var skel: Dictionary = sub["nodes"]["PATH:Skeleton3D"]

	skel["retarget/bone_map"] = bone_map
	skel["retarget/rest_fixer/fix_silhouette/enable"] = false
	# Overwrite Axis: rebakes animation tracks against the profile's reference
	# axes. Required when rename_bones is on, otherwise the skeleton ends up
	# half-processed (pelvis detaches from root, rest pose drifts).
	# 0 = None, 1 = Overwrite Axis, 2 = Use Retarget Modifier
	skel["retarget/rest_fixer/retarget_method"] = 1
	# Rename pass: bone names are no-op (UE5 names already match profile),
	# but enabling it unlocks unique_node/skeleton_name to unify the
	# Skeleton3D node name to GeneralSkeleton across every imported asset.
	skel["retarget/bone_renamer/rename_bones"] = true
	skel["retarget/bone_renamer/unique_node/skeleton_name"] = "GeneralSkeleton"
	skel["retarget/remove_tracks/unmapped_bones"] = false

	# Optional: save animations to .res in chosen export folder.
	if export_dir != "":
		if not sub.has("animations"):
			sub["animations"] = {}
		var anim_name = file_path.get_file().get_basename().to_snake_case()
		var res_path = export_dir.path_join(anim_name + ".res")
		var possible_takes := [
			"Take 001",
			"Unreal Take",
			"AnimStack::Take 001",
			anim_name,
		]
		for take in possible_takes:
			if not sub["animations"].has(take):
				sub["animations"][take] = {}
			sub["animations"][take]["save_to_file/enabled"] = true
			sub["animations"][take]["save_to_file/path"] = res_path

	cfg.set_value("params", "_subresources", sub)

	if cfg.save(import_path) != OK:
		push_error("Unreal BoneMap: Failed to save " + import_path)
		return false

	return true


# ============================================================
# TREE / PATH HELPERS
# ============================================================

func _get_filesystem_tree() -> Tree:
	var dock = get_editor_interface().get_file_system_dock()
	if not dock:
		return null
	var trees: Array[Tree] = []
	_find_all_trees(dock, trees)
	if trees.size() > 0:
		return trees[0]
	return null


func _find_all_trees(node: Node, trees: Array[Tree]):
	if node is Tree:
		trees.append(node as Tree)
	for child in node.get_children(true):
		_find_all_trees(child, trees)


func _get_selected_paths(fs_tree: Tree) -> Array:
	var result = []
	var item = fs_tree.get_next_selected(null)
	while item:
		var path = item.get_metadata(0)
		if path is String and not path.is_empty():
			result.append(path)
		item = fs_tree.get_next_selected(item)
	return result
