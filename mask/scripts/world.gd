extends Node3D

@onready var player_container = $PlayerContainer
@onready var spawn_points = $SpawnPoints
@onready var spawner = $MultiplayerSpawner
@onready var dealer = $Dealer

# UI pour le serveur
var start_button: Button = null

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
		
		# Créer le bouton Start Game pour le host
		_create_start_button()

# ============================================================================
# BOUTON START GAME (Serveur uniquement)
# ============================================================================

func _create_start_button():
	"""Crée un bouton Start Game visible uniquement pour le host"""
	var canvas = CanvasLayer.new()
	canvas.name = "HostUI"
	add_child(canvas)
	
	start_button = Button.new()
	start_button.text = "🎮 DÉMARRER LA PARTIE"
	start_button.name = "StartGameButton"
	
	# Style du bouton
	start_button.custom_minimum_size = Vector2(250, 60)
	start_button.add_theme_font_size_override("font_size", 20)
	
	# Position en haut au centre
	start_button.anchor_left = 0.5
	start_button.anchor_right = 0.5
	start_button.anchor_top = 0.0
	start_button.anchor_bottom = 0.0
	start_button.offset_left = -125
	start_button.offset_right = 125
	start_button.offset_top = 20
	start_button.offset_bottom = 80
	
	canvas.add_child(start_button)
	start_button.pressed.connect(_on_start_game_pressed)
	
	print("WORLD : Bouton Start Game créé pour le host")

func _on_start_game_pressed():
	"""Appelé quand le host clique sur Start Game"""
	if not NetworkManager.is_server(): return
	
	var player_count = player_container.get_child_count()
	if player_count < 3:
		print("WORLD : Besoin d'au moins 3 joueurs pour démarrer (max 5)")
		# On pourrait afficher un message à l'écran ici
		return
	
	print("WORLD : Démarrage de la partie avec ", player_count, " joueurs")
	
	# Cache le bouton
	if start_button:
		start_button.hide()
	
	# Appelle le dealer pour démarrer
	if dealer:
		dealer.request_start_game()

func show_start_button():
	"""Réaffiche le bouton après une partie (si on veut relancer manuellement)"""
	if start_button:
		start_button.show()

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
