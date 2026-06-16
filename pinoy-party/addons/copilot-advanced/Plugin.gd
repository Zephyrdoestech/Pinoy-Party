@tool
extends EditorPlugin

const version = "1.1.0"
const scene_path = "res://addons/copilot-advanced/CopilotUI.tscn"

var dock
var editor_interface = EditorInterface

func _enter_tree() -> void:
	if(!dock):
		dock = load(scene_path).instantiate()
		add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, dock)
		main_screen_changed.connect(Callable(dock, "on_main_screen_changed"))
		dock.editor_interface = EditorInterface


func _exit_tree():
	remove_control_from_docks(dock)
	dock.queue_free()
