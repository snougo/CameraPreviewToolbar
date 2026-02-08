@tool
extends EditorPlugin

## 在 3D 编辑器工具栏中添加一个常驻的相机预览按钮插件。
##
## 该插件允许用户在不选中相机的情况下快速切换到相机预览视角，
## 并在退出预览时自动恢复之前的选中状态。

# --- Private Vars ---

# 添加到工具栏的自定义按钮
var _toolbar_button: Button

# 记录切换预览模式前的选中项，用于后续恢复
var _previous_selection: Array[Node] = []

# 当前场景中找到的主相机缓存
var _target_camera: Camera3D


# --- Built-in Functions (_ready, _init, etc.) ---

func _enter_tree() -> void:
	# 初始化工具栏按钮
	_toolbar_button = Button.new()
	_toolbar_button.text = "Camera Preview"
	_toolbar_button.tooltip_text = "在Toolbar中快速进行相机预览的切换"
	# 获取编辑器图标
	_toolbar_button.icon = get_editor_interface().get_base_control().get_theme_icon("Camera3D", "EditorIcons")
	_toolbar_button.flat = true
	_toolbar_button.toggle_mode = true
	
	# 连接信号
	_toolbar_button.toggled.connect(_on_toolbar_button_toggled)
	
	# 添加到 3D 编辑器菜单容器
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar_button)


func _exit_tree() -> void:
	# 清理资源
	if _toolbar_button:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar_button)
		_toolbar_button.queue_free()


# --- Private Functions ---

## 执行预览模式的切换逻辑
## [param p_is_active]: 是否激活预览模式
func _toggle_preview_mode(p_is_active: bool) -> void:
	var selection: EditorSelection = get_editor_interface().get_selection()
	var current_nodes: Array[Node] = selection.get_selected_nodes()
	
	if p_is_active:
		# --- 开启预览模式 ---
		
		# 1. 寻找场景中的相机
		var edited_root: Node = get_tree().edited_scene_root
		_target_camera = _find_camera_recursive(edited_root)
		
		if not _target_camera:
			push_warning("Camera Preview Toolbar: 未找到 Camera3D 节点！")
			# 强制弹起按钮，不触发信号
			_toolbar_button.set_pressed_no_signal(false)
			return
		
		# 2. 如果当前选中的不是该相机，记录旧选区并切换选中
		# (原生预览功能依赖于必须选中相机节点)
		if current_nodes.size() != 1 or current_nodes[0] != _target_camera:
			_previous_selection = current_nodes.duplicate()
			selection.clear()
			selection.add_node(_target_camera)
		else:
			# 如果原本就选中了相机，就不需要恢复
			_previous_selection.clear()
		
		# 3. 必须等待一帧，让编辑器 UI 刷新出原生的 "Preview" 复选框
		await get_tree().process_frame
		
		# 4. 找到并勾选原生的预览框
		var native_checkbox: CheckBox = _find_native_preview_checkbox()
		if native_checkbox and not native_checkbox.button_pressed:
			native_checkbox.button_pressed = true
	
	else:
		# --- 关闭预览模式 ---
		
		# 1. 找到并取消勾选原生的预览框
		var native_checkbox: CheckBox = _find_native_preview_checkbox()
		if native_checkbox and native_checkbox.button_pressed:
			native_checkbox.button_pressed = false
			
		# 2. 恢复之前的选区（如果存在）
		if not _previous_selection.is_empty():
			selection.clear()
			for node in _previous_selection:
				# 检查节点是否依然有效（可能在预览期间被删除了）
				if is_instance_valid(node):
					selection.add_node(node)
			_previous_selection.clear()


## 递归寻找编辑器界面中的原生 "Preview" CheckBox
## 原理：遍历编辑器 UI 树，寻找文本为 "Preview" 且类型为 CheckBox 的控件
func _find_native_preview_checkbox() -> CheckBox:
	var main_screen: Control = get_editor_interface().get_editor_main_screen()
	# 注意：这里我们假设 "Preview" 是英文界面的文本，如果是多语言环境可能需要调整
	# 但 Godot 编辑器内部节点名通常固定，这里主要依靠 text 属性匹配
	return _find_node_recursive(main_screen, "Preview", "CheckBox") as CheckBox


## 通用递归节点查找工具
## [param p_node]: 当前搜索的根节点
## [param p_text_match]: 目标节点的 text 属性值
## [param p_class_match]: 目标节点的类名
func _find_node_recursive(p_node: Node, p_text_match: String, p_class_match: String) -> Node:
	if p_node.is_class(p_class_match) and "text" in p_node and p_node.text == p_text_match:
		return p_node
	
	for child in p_node.get_children():
		var result: Node = _find_node_recursive(child, p_text_match, p_class_match)
		if result:
			return result
	return null


## 在场景中寻找用于预览的目标 Camera3D 节点
## 逻辑：
## 1. 优先寻找 current = true 的相机，如果有多个，取最后一个。
## 2. 如果没有 current = true 的相机，取场景中最后一个 Camera3D。
## [param p_root]: 搜索起始节点
func _find_camera_recursive(p_root: Node) -> Camera3D:
	var all_cameras: Array[Camera3D] = []
	_collect_cameras_recursive(p_root, all_cameras)
	
	if all_cameras.is_empty():
		return null
	
	# 倒序查找第一个 current 为 true 的相机
	for i in range(all_cameras.size() - 1, -1, -1):
		var cam: Camera3D = all_cameras[i]
		if cam.current:
			return cam
			
	# 如果没有 current 相机，返回列表中的最后一个
	return all_cameras.back()


## 递归收集所有 Camera3D 节点到数组中
## [param p_node]: 当前遍历节点
## [param p_result]: 结果数组
func _collect_cameras_recursive(p_node: Node, p_result: Array[Camera3D]) -> void:
	if not p_node:
		return

	if p_node is Camera3D:
		p_result.append(p_node)
	
	for child in p_node.get_children():
		_collect_cameras_recursive(child, p_result)


# --- Signal Callbacks ---

func _on_toolbar_button_toggled(p_is_toggled_on: bool) -> void:
	_toggle_preview_mode(p_is_toggled_on)
