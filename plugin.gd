@tool
extends EditorPlugin

const UtilRemote = preload("res://addons/gdaddon/src/util_remote.gd")

const Colors = UtilRemote.Colors
const UOs = UtilRemote.UOs

const DOT = "\u2022"
const SETTING_CHECK_ON_START = &"plugin/gdaddon/check_on_start"

const OSType = UOs.OSType

const PLUGIN_NAME = "gdaddon"

#region settings
var check_on_start:bool = false

#endregion

var dialog:Window

func _get_plugin_name() -> String:
	return PLUGIN_NAME
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("Node", &"EditorIcons")

func _enter_tree() -> void:
	add_tool_menu_item(PLUGIN_NAME, _open_gdaddon)
	
	
	await get_tree().create_timer(10).timeout
	var task_threader = TaskThreader.new()
	add_child(task_threader)
	var addon_data = AddonData.new()
	addon_data.task_threader = task_threader
	
	await addon_data.get_addon_list()
	if addon_data.data != null:
		var msg = ""
		var alert = addon_data.all_valid()
		if alert == AddonData.AlertType.ALL:
			msg = "gdaddon - Update available and dependencies missing."
		elif alert == AddonData.AlertType.DEPENDENCY:
			msg = "gdaddon - Dependency missing."
		elif alert == AddonData.AlertType.UPDATE:
			msg = "gdaddon - Update available."
		if msg != "":
			var editor_toaster = EditorInterface.get_editor_toaster()
			editor_toaster.push_toast(msg, EditorToaster.SEVERITY_INFO)
			print(msg)
	
	task_threader.queue_free()
	

func _exit_tree() -> void:
	remove_tool_menu_item(PLUGIN_NAME)

func _on_editor_settings_changed():
	var ed_settings = EditorInterface.get_editor_settings()
	if not ed_settings.has_setting(SETTING_CHECK_ON_START):
		ed_settings.set_setting(SETTING_CHECK_ON_START, true)
	check_on_start = ed_settings.get_setting(SETTING_CHECK_ON_START)


func _open_gdaddon() -> void:
	if is_instance_valid(dialog):
		dialog.grab_focus()
		dialog.show()
		print("gdaddon - Dialog already open.")
		return
	
	dialog = Window.new()
	dialog.size = Vector2(1000, 800)
	dialog.close_requested.connect(func(): dialog.queue_free())
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_SCREEN_WITH_MOUSE_FOCUS 
	var gdaddon_panel = GDAddonDialog.new()
	dialog.add_child(gdaddon_panel)
	
	EditorInterface.get_base_control().add_child(dialog)
	
	gdaddon_panel.refresh()

class GDAddonDialog extends ColorRect:
	
	var task_threader:TaskThreader
	
	var margin: MarginContainer
	var content_vbox:VBoxContainer
	
	var launch_button:Button
	var quick_status_label:Label
	var refresh_button:Button
	var waiting_label:Label
	
	var addon_list_scroll:ScrollContainer
	var addon_list:VBoxContainer
	
	var addon_data:AddonData
	var refreshing:bool = false
	var addon_json:Array
	
	var list_sb:StyleBoxFlat
	
	func _init() -> void:
		task_threader = TaskThreader.new()
		add_child(task_threader)
		task_threader.wait_tick.connect(func(tick:int): waiting_label.text = "Loading%s" % ".".repeat(tick))
		
		addon_data = AddonData.new()
		addon_data.task_threader = task_threader
		
		
		var panel_sb = EditorInterface.get_editor_theme().get_stylebox("panel", "Panel")
		var bg_color = panel_sb.bg_color
		
		#color = bg_color
		color = Colors.get_theme_color(Colors.ThemeColor.BASE)
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		
		margin = MarginContainer.new()
		add_child(margin)
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		Utils.set_margin(margin, 12)
		
		var bg = ColorRect.new()
		margin.add_child(bg)
		bg.color = Colors.get_theme_color(Colors.ThemeColor.BASE)
		
		content_vbox = VBoxContainer.new()
		margin.add_child(content_vbox)
		content_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		
		var launch_hbox = HBoxContainer.new()
		content_vbox.add_child(launch_hbox)
		launch_hbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		
		launch_button = Button.new()
		launch_hbox.add_child(launch_button)
		launch_button.text = "Launch gdaddon"
		launch_button.icon = Utils.get_icon("Terminal")
		#launch_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		launch_button.pressed.connect(_launch_gdaddon)


		var quick_status_hbox:= HBoxContainer.new()
		content_vbox.add_child(quick_status_hbox)
		quick_status_hbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		quick_status_hbox.custom_minimum_size = Vector2(150, 0) * EditorInterface.get_editor_scale()
		
		quick_status_label = Label.new()
		quick_status_hbox.add_child(quick_status_label)
		quick_status_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		quick_status_label.text = "Status: Loading"
		
		quick_status_hbox.add_spacer(false)
		
		refresh_button = Button.new()
		quick_status_hbox.add_child(refresh_button)
		refresh_button.pressed.connect(refresh)
		refresh_button.icon = Utils.get_icon("Reload")
		refresh_button.theme_type_variation = &"FlatButton"
		
		
		
		var list_marg = MarginContainer.new()
		content_vbox.add_child(list_marg)
		Utils.control_fill(list_marg)
		Utils.set_margin(list_marg, 12)
		
		
		var list_bg = Panel.new()
		list_marg.add_child(list_bg)
		Utils.control_fill(list_bg)
		
		addon_list_scroll = ScrollContainer.new()
		list_bg.add_child(addon_list_scroll)
		addon_list_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		
		addon_list = VBoxContainer.new()
		addon_list_scroll.add_child(addon_list)
		Utils.control_fill(addon_list)
		addon_list.add_theme_constant_override("separation", 0)
		
		waiting_label = Label.new()
		addon_list_scroll.add_child(waiting_label)
		waiting_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		waiting_label.text = "Loading"
		waiting_label.hide()
		
		
		list_sb = StyleBoxFlat.new()
		list_sb.bg_color = Colors.get_theme_color(Colors.ThemeColor.BASE)
		list_sb.border_color = bg_color
		list_sb.set_border_width_all(10)
		list_sb.border_width_right = 0
		list_sb.set_content_margin_all(10 * EditorInterface.get_editor_scale())
		#list_sb.set(10 * EditorInterface.get_editor_scale())
	
	
	func _launch_gdaddon():
		await UOs.launch_term(Utils.get_executable())
	
	func refresh():
		if refreshing:
			print("Refreshing..")
			return
		refreshing = true
		waiting_label.show()
		quick_status_label.text = "Status: Loading"
		clear_addon_list()
		await build_addon_list()
		waiting_label.hide()
		refreshing = false
		
	
	func build_addon_list():
		await addon_data.get_addon_list()
		quick_status_label.text = addon_data.all_valid_string()
		
		for entry:Dictionary in addon_data.data:
			var addon_item = AddonListItem.new()
			addon_item.add_theme_stylebox_override("panel", list_sb)
			addon_list.add_child(addon_item)
			addon_item.set_data(entry)
	
	func clear_addon_list():
		for c in addon_list.get_children():
			addon_list.remove_child(c)
			c.queue_free()


class AddonListItem extends PanelContainer:
	
	var main_vbox:VBoxContainer
	var addon_path:String
	
	var top_label:Label
	
	var alert_icon:TextureRect
	var status_label:Label
	
	var middle_label:Label
	var lock_icon:TextureRect
	var lock_label:Label
	
	var bottom_label:Label
	var terminal_button:Button
	var open_button:Button
	var navigate_button:Button
	
	func _init() -> void:
		main_vbox = VBoxContainer.new()
		add_child(main_vbox)
		Utils.control_fill(main_vbox)
		
		var top_hbox = HBoxContainer.new()
		main_vbox.add_child(top_hbox)
		top_label = Label.new()
		top_hbox.add_child(top_label)
		
		
		
		alert_icon = TextureRect.new()
		alert_icon.texture = Utils.get_icon("NodeWarning")
		alert_icon.hide()
		alert_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		alert_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top_hbox.add_child(alert_icon)
		
		status_label = Label.new()
		top_hbox.add_child(status_label)
		status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		
		var middle_hbox:= HBoxContainer.new()
		main_vbox.add_child(middle_hbox)
		
		middle_label = Label.new()
		middle_hbox.add_child(middle_label)
		#middle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		lock_icon = TextureRect.new()
		middle_hbox.add_child(lock_icon)
		lock_icon.hide()
		lock_icon.texture = Utils.get_icon("Lock")
		lock_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
		lock_label = Label.new()
		lock_label.text = "locked"
		middle_hbox.add_child(lock_label)
		lock_label.hide()
		
		middle_hbox.add_spacer(false)
		
		var bottom_hbox:HBoxContainer = HBoxContainer.new()
		main_vbox.add_child(bottom_hbox)
		
		bottom_label = Label.new()
		bottom_hbox.add_child(bottom_label)
		bottom_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var button_target = bottom_hbox
		
		terminal_button = Button.new()
		button_target.add_child(terminal_button)
		terminal_button.icon = Utils.get_icon("Terminal")
		terminal_button.pressed.connect(_on_button_pressed.bind(terminal_button))
		terminal_button.theme_type_variation = &"FlatButton"
		terminal_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
		open_button = Button.new()
		button_target.add_child(open_button)
		open_button.icon = Utils.get_icon("Folder")
		open_button.pressed.connect(_on_button_pressed.bind(open_button))
		open_button.theme_type_variation = &"FlatButton"
		open_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
		navigate_button = Button.new()
		button_target.add_child(navigate_button)
		navigate_button.icon = Utils.get_icon("FileTree")
		navigate_button.pressed.connect(_on_button_pressed.bind(navigate_button))
		navigate_button.theme_type_variation = &"FlatButton"
		navigate_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	func set_data(data:Dictionary):
		var addon_name = data.get("name")
		addon_path = data.get("path")
		
		var tag = data.get("tag")
		
		
		var kind = data.get("kind")
		var state = data.get("state")
		
		var locked = data.get("lock", false)
		lock_icon.visible = locked
		lock_label.visible = locked
		var local_version = data.get("local_version")
		var pinned_version = data.get("pinned_version")
		
		var top_text = addon_name
		var middle_text = ""
		if kind == "package":
			top_text += " %s Package" % DOT
			middle_text = state
			if local_version == "" or state == "missing" or local_version != pinned_version:
				middle_text += " %s Target: %s" % [DOT, pinned_version]
			elif local_version == pinned_version:
				middle_text += " %s %s" %[DOT, local_version]
			#elif local_version != pinned_version:
				#middle_text += "%s Target: %s" %[DOT, pinned_version]
			
		elif kind == "clone":
			top_text += " %s Cloned (%s)" % [DOT, tag]
		elif kind == "submodule":
			top_text += " %s Submodule (%s)" % [DOT, tag]
		
		top_label.text = top_text
		middle_label.visible = middle_text != ""
		middle_label.text = middle_text
		
		var update_status = data.get("update")
		var missing_deps = data.get("missing_deps", [])
		
		var statuses = []
		if update_status == "available":
			statuses.append("Update")
		if not missing_deps.is_empty():
			statuses.append("Missing Deps")
		
		set_status(statuses)
		
		var bottom_text = addon_path
		set_bottom_text(bottom_text)
		tooltip_text = addon_path
		
	
	
	func set_status(statuses:Array):
		var status = ", ".join(statuses)
		if status != "":
			status_label.text = "[ %s ]" % status
			alert_icon.show()
	
	func set_bottom_text(string:String):
		bottom_label.text = string
	
	func _on_button_pressed(button:Button):
		if not DirAccess.dir_exists_absolute(addon_path):
			print("Not a valid path: ", addon_path)
			return
		var full_path = "res://".path_join(addon_path)
		match button:
			terminal_button: UOs.launch_term("", full_path)
			navigate_button: EditorInterface.get_file_system_dock().navigate_to_path(full_path)
			open_button: OS.shell_show_in_file_manager(ProjectSettings.globalize_path(full_path))


class AddonData:

	enum AlertType {
		NONE,
		UPDATE,
		DEPENDENCY,
		ALL,
	}

	var read_success:bool=false
	var bin_found:bool=true
	var data:Array

	var task_threader:TaskThreader

	func get_addon_list() -> Variant:
		var res = await task_threader.run_task(_fetch_addon_list_blocking)
		read_success = res != null
		if read_success:
			data = res
		else:
			data = []
		return data

	func _fetch_addon_list_blocking() -> Variant:
		var exe_path = Utils.get_executable()
		bin_found = exe_path != ""
		if not bin_found:
			print("Could not find the gdaddon binary on PATH or in ~/.gdaddon/bin")
			return null
		var output := []
		var status := OS.execute(exe_path, ["list", "--json", "--updates"], output)
		if status != 0:
			print("Could not get addon status - Exit Code: %d" % status)
			return null
		return JSON.parse_string(output[0])

	func all_valid_string():
		if not bin_found:
			return "Status: gdaddon not found"
		if not read_success:
			return "Status: Error"
		var val = all_valid()
		match val:
			AlertType.NONE: return "Status: OK"
			AlertType.UPDATE: return "Status: Update"
			AlertType.DEPENDENCY: return "Status: Dependency"
			AlertType.ALL: return "Status: Update + Dep"
	
	func all_valid() -> AlertType:
		var final_alert = AlertType.NONE
		for entry in data:
			var alert = check_entry_status(entry)
			if alert > final_alert:
				final_alert = alert
		
		return final_alert
	
	static func check_entry_status(addon_data:Dictionary) -> AlertType:
		var update_status = addon_data.get("update")
		var missing_deps = not addon_data.get("missing_deps", []).is_empty()
		var has_update = update_status == "available"
		if missing_deps and has_update:
			return AlertType.ALL
		elif missing_deps:
			return AlertType.DEPENDENCY
		elif has_update:
			return AlertType.UPDATE
		return AlertType.NONE


class TaskThreader extends Node:
	signal wait_tick(count:int)

	func run_task(task:Callable):
		var thread := Thread.new()
		thread.start(task)
		
		var count = 0
		while thread.is_alive():
			count += 1
			if count == 160:
				count = 0
			wait_tick.emit(floori(count / 40.0))
			
			await get_tree().process_frame
		
		return thread.wait_to_finish()


class Utils:
	#region control helpers
	static func get_icon(icon_name:String):
		return EditorInterface.get_editor_theme().get_icon(icon_name, &"EditorIcons")
	
	static func set_margin(margin:MarginContainer, val:int):
		val *= int(EditorInterface.get_editor_scale())
		margin.add_theme_constant_override("margin_top", val)
		margin.add_theme_constant_override("margin_bottom", val)
		margin.add_theme_constant_override("margin_left", val)
		margin.add_theme_constant_override("margin_right", val)
	
	static func control_fill(control:Control):
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	#endregion
	
	
	static func get_executable() -> String:
		var out = []
		var exit = OS.execute("gdaddon", ["--version"], out)
		if exit == 0:
			return "gdaddon"
		
		out.clear()
		var os = UOs.get_os()
		var home_dir = UOs.get_home_dir()
		var bin_name = "gdaddon"
		if os == OSType.WINDOWS:
			bin_name += ".exe"
		var exec_path = home_dir.path_join(".gdaddon").path_join("bin").path_join(bin_name)
		var home_exit = OS.execute(exec_path, ["--version"], out)
		if home_exit == 0:
			return exec_path
		return ""
