extends Control




func _on_host_button_pressed() -> void:
	World.start_server()
	get_tree().change_scene_to_file("res://world.tscn")

func _on_join_button_pressed() -> void:
	World.start_client()
