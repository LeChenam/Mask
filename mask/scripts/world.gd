extends Node

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	
	if multiplayer.is_server():
		print("--- SERVEUR DÉMARRÉ (ID 1) ---")
		spawn_player(1)


func _on_player_connected(peer_id):
	# Ce log n'apparaît QUE sur le serveur
	print("--- RÉSEAU : Le joueur ", peer_id, " vient de se connecter ! ---")
	if multiplayer.is_server():
		spawn_player(peer_id)

func _on_player_disconnected(peer_id):
	print("--- RÉSEAU : Le joueur ", peer_id, " est parti. ---")
	var p = $PlayerContainer.get_node_or_null(str(peer_id))
	if p: p.queue_free()

func spawn_player(peer_id):
	print("--- SPAWN : Création du perso pour l'ID ", peer_id)
	var player = preload("res://player.tscn").instantiate()
	player.name = str(peer_id)
	$PlayerContainer.add_child(player)
	
	# Position de départ
	var offset = $PlayerContainer.get_child_count() * 3.0
	player.global_position = Vector3(offset, 2, 0)
