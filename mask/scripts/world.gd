extends Node3D

@onready var player_container = $PlayerContainer
@onready var spawn_points = $SpawnPoints
@onready var spawner = $MultiplayerSpawner

# Dictionnaire pour suivre les places occupées { peer_id : spawn_index }
var assigned_spawn_indices: Dictionary = {}
var next_spawn_index: int = 0

func _ready():
	if not multiplayer.has_multiplayer_peer():
		print("WORLD : Pas de connexion réseau, retour au lobby")
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		return

	# --- CONFIGURATION IMPORTANTE DU SPAWNER ---
	# On assigne la fonction qui va construire le joueur sur TOUS les PC (Serveur ET Clients)
	spawner.spawn_function = _spawn_player_setup

	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	if NetworkManager.is_server():
		print("WORLD : Je suis le serveur, spawn de mon joueur (ID 1)")
		_spawn_player(1)

# ============================================================================
# LA MAGIE DU SPAWN (C'est ici que tout change)
# ============================================================================

# Cette fonction est appelée AUTOMATIQUEMENT par le Spawner sur le Serveur ET le Client
# Elle reçoit les données qu'on lui passe (ici, un tableau [id, index])
func _spawn_player_setup(data):
	var peer_id = data[0]
	var spawn_index = data[1]
	
	var player_scene = preload("res://scenes/player.tscn")
	var new_player = player_scene.instantiate()
	new_player.name = str(peer_id)
	
	# --- DEBUGGING ---
	if spawn_points == null:
		print("ERREUR CRITIQUE : Le nœud 'SpawnPoints' n'est pas trouvé par le script !")
	else:
		var points = spawn_points.get_children()
		print("DEBUG : Nombre de markers trouvés : ", points.size())
		
		if points.size() > 0:
			var target_point = points[spawn_index % points.size()]
			new_player.global_transform = target_point.global_transform
			print("SUCCÈS : Joueur ", peer_id, " placé sur ", target_point.name, " à la position ", target_point.global_position)
		else:
			print("ATTENTION : Le dossier 'SpawnPoints' est vide ! Pas de Marker3D dedans.")
	# -----------------

	return new_player

# Fonction appelée uniquement par le SERVEUR pour déclencher le spawn
func _spawn_player(peer_id: int):
	# On calcule l'index de spawn uniquement sur le serveur
	if not assigned_spawn_indices.has(peer_id):
		assigned_spawn_indices[peer_id] = next_spawn_index
		next_spawn_index += 1
	
	var index = assigned_spawn_indices[peer_id]
	
	# AU LIEU DE add_child, on demande au Spawner de faire le travail
	# On lui passe les infos nécessaires : ID et numéro de siège
	spawner.spawn([peer_id, index])

# ============================================================================
# GESTION CLASSIQUE
# ============================================================================

func _on_player_joined(peer_id: int):
	if not NetworkManager.is_server(): return
	print("WORLD : Nouveau joueur ", peer_id, " -> Spawn")
	_spawn_player(peer_id)

func _on_player_left(peer_id: int):
	if not NetworkManager.is_server(): return
	print("WORLD : Joueur ", peer_id, " déconnecté -> Suppression")
	
	# Avec le Spawner, effacer l'objet sur le serveur l'efface chez tout le monde
	if player_container.has_node(str(peer_id)):
		player_container.get_node(str(peer_id)).queue_free()
	
	if assigned_spawn_indices.has(peer_id):
		assigned_spawn_indices.erase(peer_id)

func _on_server_disconnected():
	print("WORLD : Serveur perdu, retour au lobby")
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
