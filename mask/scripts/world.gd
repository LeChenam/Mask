extends Node

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	
	if multiplayer.is_server():
		print("MONDE : Serveur prêt.")
		# --- CORRECTION ICI ---
		# On force le spawn du serveur lui-même (ID 1) pour qu'il puisse jouer
		_on_player_connected(1)

func _on_player_connected(peer_id):
	if not multiplayer.is_server(): return
	
	# --- CORRECTION ICI ---
	# On retire la ligne "if peer_id == 1: return" 
	# pour permettre au serveur d'avoir son personnage.
	
	print("SERVEUR : Création du personnage pour le joueur ", peer_id)
	
	var player = preload("res://player.tscn").instantiate()
	player.name = str(peer_id)
	$PlayerContainer.add_child(player)
	
	var count = $PlayerContainer.get_child_count()
	player.global_position = Vector3(count * 3.0, 2, 0)


func _on_player_disconnected(peer_id):
	if not multiplayer.is_server(): return
	var p = $PlayerContainer.get_node_or_null(str(peer_id))
	if p: p.queue_free()
