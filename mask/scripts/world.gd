extends Node

# Assure-toi que tu as bien un noeud appelé "PlayerContainer" dans ta scène World
# Assure-toi que tu as bien un MultiplayerSpawner configuré sur "PlayerContainer"

func _ready():
	# C'est ICI qu'on branche les câbles
	# On écoute si des gens se connectent ou se déconnectent
	if multiplayer.is_server():
		print("WORLD: Je suis le Serveur. J'écoute les connexions.")
		multiplayer.peer_connected.connect(_on_player_connected)
		multiplayer.peer_disconnected.connect(_on_player_disconnected)
		
		# CAS SPÉCIAL : Le signal 'peer_connected' ne se lance pas pour l'hôte lui-même
		# Donc on doit se spawner manuellement
		_on_player_connected(1)
	else:
		print("WORLD: Je suis un Client. J'attends que le spawner fasse son travail.")

func _on_player_connected(peer_id):
	print("SERVEUR: Nouvelle connexion détectée ! ID: " + str(peer_id))
	
	# 1. On charge le joueur
	var player = preload("res://player.tscn").instantiate()
	
	# 2. IMPORTANT : Le nom du noeud DOIT être l'ID pour que le réseau comprenne
	player.name = str(peer_id)
	
	# 3. On calcule la position
	setup_player_position(player)
	
	# 4. On l'ajoute au conteneur. Le MultiplayerSpawner va voir ça et le copier chez les autres.
	$PlayerContainer.add_child(player)
	print("SERVEUR: Joueur " + str(peer_id) + " ajouté à la scène.")

func _on_player_disconnected(peer_id):
	print("SERVEUR: Le joueur " + str(peer_id) + " est parti.")
	if $PlayerContainer.has_node(str(peer_id)):
		$PlayerContainer.get_node(str(peer_id)).queue_free()

func setup_player_position(player):
	# Petite astuce pour pas qu'ils spawnent tous au même endroit
	var index = $PlayerContainer.get_child_count()
	player.position = Vector3(index * 2.0, 1.0, 0) # 1.0 en Y pour pas tomber dans le sol
