extends Node3D

@onready var dealer = $Dealer

func _ready():
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_player_connected)
		_on_player_connected(1)

func _on_player_connected(peer_id):
	var player = preload("res://player.tscn").instantiate()
	player.name = str(peer_id)
	$PlayerContainer.add_child(player)
	setup_player_position(player)

func setup_player_position(player):
	var index = $PlayerContainer.get_child_count() - 1
	var marker = $SpawnPoint.get_child(index)
	player.global_transform = marker.global_transform

func _input(event):
	if multiplayer.is_server() and event.is_action_pressed("ui_accept"):
		dealer.start_game()
