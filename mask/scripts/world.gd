extends Node3D
# ============================================================================
# WORLD - Scène principale du jeu (utilise NetworkManager)
# ============================================================================

@onready var player_container = $PlayerContainer
@onready var spawn_points = $SpawnPoints

func _ready():
	# Sécurité : on doit être connecté au réseau
	if not multiplayer.has_multiplayer_peer():
		print("WORLD : Pas de connexion réseau, retour au lobby")
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		return

	# Connexion aux signaux du NetworkManager
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	# Si je suis le serveur, je spawn mon propre joueur
	if NetworkManager.is_server():
		print("WORLD : Je suis le serveur, spawn de mon joueur (ID 1)")
		_spawn_player(1)

# ============================================================================
# GESTION DES JOUEURS
# ============================================================================

func _on_player_joined(peer_id: int):
	"""Un nouveau joueur s'est connecté"""
	if not NetworkManager.is_server():
		return
	
	print("WORLD : Nouveau joueur ", peer_id, " -> Spawn")
	_spawn_player(peer_id)

func _on_player_left(peer_id: int):
	"""Un joueur s'est déconnecté"""
	if not NetworkManager.is_server():
		return
	
	print("WORLD : Joueur ", peer_id, " déconnecté -> Suppression")
	_remove_player(peer_id)

func _on_server_disconnected():
	"""Le serveur s'est déconnecté (côté client)"""
	print("WORLD : Serveur perdu, retour au lobby")
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

# ============================================================================
# SPAWN / DESPAWN
# ============================================================================

func _spawn_player(peer_id: int):
	"""Crée et positionne un joueur"""
	var player_scene = preload("res://scenes/player.tscn")
	var new_player = player_scene.instantiate()
	
	# Le nom du node = ID réseau (important pour le MultiplayerSpawner)
	new_player.name = str(peer_id)
	
	# Ajout au container (synchronisé par le MultiplayerSpawner)
	player_container.add_child(new_player, true)
	
	# Positionnement sur un point de spawn
	_position_player_at_spawn(new_player)

func _position_player_at_spawn(player: Node3D):
	"""Positionne un joueur sur un point de spawn libre"""
	var points = spawn_points.get_children()
	
	if points.size() > 0:
		var index = player_container.get_child_count() - 1
		var target_point = points[index % points.size()]
		player.global_transform = target_point.global_transform
	else:
		print("WORLD : ERREUR - Aucun point de spawn !")
		player.global_position = Vector3(0, 2, 0)

func _remove_player(peer_id: int):
	"""Supprime un joueur du monde"""
	var player_node = player_container.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
