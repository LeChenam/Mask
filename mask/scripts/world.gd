extends Node3D # Important : Node3D, pas Node ou Control !

# Référence au container des joueurs
@onready var player_container = $PlayerContainer

func _ready():
	# Si on n'est pas sur le réseau, on ne fait rien (sécurité)
	if not multiplayer.has_multiplayer_peer(): return

	# On connecte les signaux pour savoir quand quelqu'un arrive ou part
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	
	# Si JE SUIS LE SERVEUR, je dois gérer les spawns
	if multiplayer.is_server():
		print("--- SERVEUR : Monde chargé. Création de mon propre joueur (ID 1) ---")
		spawn_player(1)

func _on_player_connected(peer_id):
	# Seul le serveur a le droit de faire apparaître des gens
	if not multiplayer.is_server(): return
	
	print("--- SERVEUR : Connexion du joueur ", peer_id, " -> Spawn en cours.")
	spawn_player(peer_id)

func _on_player_disconnected(peer_id):
	if not multiplayer.is_server(): return
	
	print("--- SERVEUR : Déconnexion du joueur ", peer_id)
	if player_container.has_node(str(peer_id)):
		player_container.get_node(str(peer_id)).queue_free()

func spawn_player(id):
	var player_scene = preload("res://player.tscn")
	var new_player = player_scene.instantiate()
	
	# CRUCIAL : Le nom du node DOIT être l'ID réseau
	new_player.name = str(id)
	
	# On l'ajoute au container (surveillé par le MultiplayerSpawner)
	player_container.add_child(new_player)
	
	# On décale un peu la position pour ne pas spawn les uns sur les autres
	var spawn_index = player_container.get_child_count()
	new_player.global_position = Vector3(spawn_index * 2.0, 2.0, 0.0)
