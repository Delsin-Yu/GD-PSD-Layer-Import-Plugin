@tool
extends EditorPlugin

var plugin : LayeredPSDImportPlugin;

func _enter_tree() -> void:
	plugin = LayeredPSDImportPlugin.new();
	add_import_plugin(plugin);

func _exit_tree() -> void:
	if !plugin: return;
	remove_import_plugin(plugin);
	plugin = null;
