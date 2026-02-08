@tool
extends EditorPlugin

## 在 3D 编辑器工具栏中添加一个常驻的相机预览按钮插件。
##
## 逻辑：
## 1. 如果当前选中的是相机节点 -> 预览该相机。
## 2. 如果当前未选中相机 -> 寻找场景中 current=true 的主相机进行预览。
## 3. 退出预览时恢复之前的选中状态。

# --- Private Vars ---

var _toolbar_button: Button
var _previous_selection: Array[Node] = []
var _target_camera: Camera3D


# --- Built-in Functions ---

func _enter_tree() -> void:
	_toolbar_button = Button.new()
	_toolbar_button.text = "Camera Preview"
	_toolbar_button.tooltip_text = "预览相机视角 (优先预览选中相机，否则寻找主相机)"
	_toolbar_button.icon = get_editor_interface().get_base_control().get_theme_icon("Camera3D", "EditorIcons")
	_toolbar_button.flat = true
	_toolbar_button.toggle_mode = true
	_toolbar_button.toggled.connect(_on_toolbar_button_toggled)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar_button)


func _exit_tree() -> void:
	if _toolbar_button:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar_button)
		_toolbar_button.queue_free()


# --- Private Functions ---

func _toggle_preview_mode(p_is_active: bool) -> void:
	var selection: EditorSelection = get_editor_interface().get_selection()
	var current_nodes: Array[Node] = selection.get_selected_nodes()
	
	if p_is_active:
		# --- 开启预览 ---
		
		var camera_to_preview: Camera3D = null
		
		# 策略 1: 优先检查当前选中的节点是否为相机
		if current_nodes.size() == 1 and current_nodes[0] is Camera3D:
			camera_to_preview = current_nodes[0]
			# 如果刚好选中了相机，不需要记录恢复选区（或者视作不需要恢复）
			_previous_selection.clear() 
		
		# 策略 2: 如果没选中相机，则在场景中寻找主相机
		else:
			var edited_root: Node = get_tree().edited_scene_root
			camera_to_preview = _find_target_camera(edited_root)
			
			if camera_to_preview:
				# 记录旧选区并切换到目标相机
				_previous_selection = current_nodes.duplicate()
				selection.clear()
				selection.add_node(camera_to_preview)
		
		_target_camera = camera_to_preview
		
		if not _target_camera:
			push_warning("Camera Preview Toolbar: 未选中相机且场景中无可用 Camera3D。")
			_toolbar_button.set_pressed_no_signal(false)
			return
		
		# 等待 UI 并执行勾选
		await _wait_and_activate_native_preview(selection)
	
	else:
		# --- 关闭预览 ---
		
		var native_checkbox: CheckBox = _find_native_preview_checkbox()
		if native_checkbox and native_checkbox.button_pressed:
			native_checkbox.button_pressed = false
			
		# 恢复之前的选区
		if not _previous_selection.is_empty():
			selection.clear()
			for node in _previous_selection:
				if is_instance_valid(node):
					selection.add_node(node)
			_previous_selection.clear()


# 等待原生预览复选框就绪并激活
func _wait_and_activate_native_preview(selection: EditorSelection) -> void:
	var native_checkbox: CheckBox = null
	var max_retries: int = 20
	
	for i in range(max_retries):
		await get_tree().process_frame
		
		if not is_instance_valid(_target_camera):
			_toolbar_button.set_pressed_no_signal(false)
			return
			
		# 确保目标相机保持选中状态
		var current_sel = selection.get_selected_nodes()
		if current_sel.size() != 1 or current_sel[0] != _target_camera:
			selection.clear()
			selection.add_node(_target_camera)
		
		native_checkbox = _find_native_preview_checkbox()
		if native_checkbox and native_checkbox.is_visible_in_tree() and not native_checkbox.disabled:
			break
	
	if native_checkbox:
		if not native_checkbox.button_pressed:
			native_checkbox.button_pressed = true
	else:
		push_warning("Camera Preview Toolbar: 原生预览控件未就绪。")
		_toolbar_button.set_pressed_no_signal(false)


func _find_native_preview_checkbox() -> CheckBox:
	var main_screen: Control = get_editor_interface().get_editor_main_screen()
	return _find_node_recursive(main_screen, "Preview", "CheckBox") as CheckBox


func _find_node_recursive(p_node: Node, p_text_match: String, p_class_match: String) -> Node:
	if p_node.is_class(p_class_match) and "text" in p_node and p_node.text == p_text_match:
		return p_node
	for child in p_node.get_children():
		var result: Node = _find_node_recursive(child, p_text_match, p_class_match)
		if result: return result
	return null


# 查找场景中的主相机 (current=true 优先，否则取末尾)
func _find_target_camera(p_root: Node) -> Camera3D:
	if not p_root: return null
	# 使用 find_children 确保搜索包含子场景
	var nodes: Array[Node] = p_root.find_children("*", "Camera3D", true, false)
	var all_cameras: Array[Camera3D] = []
	
	if p_root is Camera3D: all_cameras.append(p_root)
	for node in nodes: if node is Camera3D: all_cameras.append(node)
	
	if all_cameras.is_empty(): return null
	
	# 倒序找 current = true
	for i in range(all_cameras.size() - 1, -1, -1):
		if all_cameras[i].current: return all_cameras[i]
		
	return all_cameras.back()


func _on_toolbar_button_toggled(p_is_toggled_on: bool) -> void:
	_toggle_preview_mode(p_is_toggled_on)
