extends Node3D

enum GamePhase { WAITING, PRE_FLOP, FLOP, TURN, RIVER, SHOWDOWN }
var current_phase = GamePhase.WAITING
var deck = []
var turn_index = 0

@onready var card_container = $CardContainer

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

# Fonction pour démarrer (à lier à un bouton "Start" sur l'UI du Host ou auto quand 2 joueurs sont là)
func start_game():
	if not multiplayer.is_server(): return
	print("SERVEUR: Démarrage de la partie !")

	# 1. Créer le deck
	deck.clear()
	for i in range(52): deck.append(i)
	deck.shuffle()

	# 2. Nettoyer la table
	for c in card_container.get_children(): c.queue_free()

	# 3. Lancer la phase 1
	current_phase = GamePhase.PRE_FLOP
	distribuer_mains()

func distribuer_mains():
	# Donner 2 cartes à chaque joueur
	for i in range(2):
		for player in $PlayerContainer.get_children():
			distribuer_carte_a(player.name.to_int())
			await get_tree().create_timer(0.2).timeout # Petit délai pour le style
			
	next_turn()

func distribuer_carte_a(target_id):
	if deck.is_empty(): return

	var card_val = deck.pop_back()
	var card = preload("res://card.tscn").instantiate()

	# Nom unique obligatoire pour le réseau
	card.name = "Card_" + str(card_val) + "_" + str(randi()) 
	card.card_id = card_val

	card_container.add_child(card) # Le Spawner la montre à tout le monde

	# DONNER L'AUTORITÉ AU JOUEUR (Il voit la face, les autres le dos)
	card.set_multiplayer_authority(target_id)

	# Déplacer vers le joueur
	var player_node = $PlayerContainer.get_node(str(target_id))
	# Position un peu devant le joueur
	card.global_position = player_node.global_position + Vector3(0, 1.0, 0.5) 

func next_turn():
	var players = $PlayerContainer.get_children()
	if players.size() == 0: return

	# Passer au suivant
	turn_index = (turn_index + 1) % players.size()
	var current_player_node = players[turn_index]
	var pid = current_player_node.name.to_int()
	print("C'est au tour du joueur : " + str(pid))
	
	# Dire au joueur que c'est à lui (RPC vers le Player.gd)
	# On suppose que Player.gd a une fonction "notify_turn"
	current_player_node.rpc("notify_turn", true)

func _input(event):
	if multiplayer.is_server() and event.is_action_pressed("ui_accept"): # Touche Espace
		start_game()
