extends Node3D

# --- CONFIGURATION DU JEU ---
enum GamePhase { PRE_FLOP, FLOP, TURN, RIVER, SHOWDOWN }
var current_phase: GamePhase = GamePhase.PRE_FLOP
var deck: Array = []
var turn_index: int = 0

# --- RÉFÉRENCES AUX NOEUDS ---
@onready var player_container = $PlayerContainer
@onready var spawn_points = $SpawnPoints

# AJOUT CRUCIAL : Il faut créer ce Node3D dans ta scène pour y ranger les cartes
@onready var card_container = $CardContainer 

# --- CONFIGURATION LAN (Broadcast) ---
const BROADCAST_PORT = 8989
const MAGIC_WORD = "MASKARD_SERVER"
var udp_broadcast = PacketPeerUDP.new()
var broadcast_timer = Timer.new()
var current_broadcast_ip = "255.255.255.255"

func _ready():
	# Sécurité : Si pas de réseau, on ne fait rien (ou retour au menu)
	if not multiplayer.has_multiplayer_peer(): return

	# Connexion des signaux réseau
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	
	# Initialisation Serveur
	if multiplayer.is_server():
		print("--- SERVEUR : Monde chargé. (ID 1) ---")
		spawn_player(1) # Le serveur joue aussi
		_setup_broadcast() # On annonce la partie aux autres PC

func _exit_tree():
	# Nettoyage propre du réseau
	if multiplayer.is_server():
		broadcast_timer.stop()
		udp_broadcast.close()

# ==============================================================================
# GESTION DES JOUEURS (CONNEXION / DÉCONNEXION)
# ==============================================================================

func _on_player_connected(peer_id):
	if not multiplayer.is_server(): return
	print("--- SERVEUR : Nouveau joueur ", peer_id, " -> Spawn.")
	spawn_player(peer_id)

func _on_player_disconnected(peer_id):
	if not multiplayer.is_server(): return
	print("--- SERVEUR : Déconnexion du joueur ", peer_id)
	if player_container.has_node(str(peer_id)):
		player_container.get_node(str(peer_id)).queue_free()

func spawn_player(id):
	# Assure-toi que le chemin est bon (res://scenes/player.tscn ou res://player.tscn)
	var player_scene = preload("res://scenes/player.tscn") 
	var new_player = player_scene.instantiate()
	
	# 1. Nommer le node avec l'ID (OBLIGATOIRE pour MultiplayerSpawner)
	new_player.name = str(id)
	
	# 2. Ajouter à la scène
	player_container.add_child(new_player, true)
	
	# 3. Positionnement sur les chaises (SpawnPoints)
	_setup_player_position(new_player)

func _setup_player_position(player_node):
	var points = spawn_points.get_children()
	if points.size() > 0:
		var index = player_container.get_child_count() - 1
		var target_point = points[index % points.size()]
		player_node.global_transform = target_point.global_transform
	else:
		print("ERREUR : Pas de SpawnPoints !")
		player_node.global_position = Vector3(0, 2, 0)

# ==============================================================================
# LOGIQUE DU JEU (POKER)
# ==============================================================================

# Cette fonction lance la partie quand on appuie sur ESPACE (ou bouton Start)
func _input(event):
	# On autorise le lancement manuel via ESPACE seulement si on est Serveur
	if multiplayer.is_server() and event.is_action_pressed("ui_accept"):
		var player_count = player_container.get_child_count()
		if player_count >= 2:
			print("SERVEUR : Lancement de la partie avec ", player_count, " joueurs !")
			start_game()
		else:
			print("SERVEUR : Impossible de lancer. En attente de joueurs... (Actuellement : ", player_count, ")")

func start_game():
	print("SERVEUR: Démarrage de la partie !")

	# 1. Création du deck (0 à 51)
	deck.clear()
	for i in range(52): deck.append(i)
	deck.shuffle() # Mélange

	# 2. Nettoyer la table (supprimer les anciennes cartes)
	for c in card_container.get_children(): 
		c.queue_free()

	# 3. Initialiser l'état du jeu
	current_phase = GamePhase.PRE_FLOP
	turn_index = 0
	
	# 4. Distribuer
	distribuer_mains()

func distribuer_mains():
	print("SERVEUR: Distribution des cartes...")
	# Donner 2 cartes à chaque joueur
	for i in range(2):
		for player in player_container.get_children():
			# On récupère l'ID réseau du joueur grâce à son nom
			var p_id = player.name.to_int()
			distribuer_carte_a(p_id)
			
			# Petit délai pour l'animation/style
			await get_tree().create_timer(0.2).timeout 
			
	# Une fois distribué, on lance le premier tour
	next_turn()

func distribuer_carte_a(target_id):
	if deck.is_empty(): return

	var card_val = deck.pop_back()
	# Assure-toi d'avoir ta scène de carte ici
	var card = preload("res://scenes/card.tscn").instantiate()

	# Nom unique pour la réplication réseau
	card.name = "Card_" + str(card_val) + "_" + str(randi()) 
	card.card_id = card_val # Supposant que ton script card.gd a une variable card_id

	# Ajouter au CardContainer (Le MultiplayerSpawner doit surveiller ce dossier !)
	card_container.add_child(card, true)

	# --- GESTION DE LA VISIBILITÉ ---
	# On donne l'autorité de la carte au joueur qui la reçoit.
	# Dans le script card.gd, tu devras dire : "Si je suis l'autorité, je montre la face, sinon le dos"
	card.set_multiplayer_authority(target_id)

	# Déplacer la carte vers le joueur
	var player_node = player_container.get_node(str(target_id))
	if player_node:
		# On place la carte un peu devant le joueur
		card.global_position = player_node.global_position + Vector3(0, 1.0, 0.5) 

func next_turn():
	var players = player_container.get_children()
	if players.size() == 0: return

	# On passe au joueur suivant (boucle)
	turn_index = (turn_index + 1) % players.size()
	
	var current_player_node = players[turn_index]
	var pid = current_player_node.name.to_int()
	
	print("C'est au tour du joueur : " + str(pid))
	
	# On prévient le joueur que c'est à lui via RPC
	# (Assure-toi que player.gd a une fonction @rpc func notify_turn(is_my_turn))
	if current_player_node.has_method("notify_turn"):
		current_player_node.rpc("notify_turn", true)

# ==============================================================================
# SYSTÈME LAN BROADCAST (Pour la découverte auto)
# ==============================================================================

func _get_local_broadcast_ip() -> String:
	var addresses = IP.get_local_addresses()
	for ip in addresses:
		if ip.begins_with("192.168.") or ip.begins_with("10."):
			var parts = ip.split(".")
			parts[3] = "255"
			return ".".join(parts)
	return "255.255.255.255"

func _setup_broadcast():
	current_broadcast_ip = _get_local_broadcast_ip()
	print("WORLD : Broadcast LAN actif sur ", current_broadcast_ip)
	udp_broadcast.set_broadcast_enabled(true)
	
	add_child(broadcast_timer)
	broadcast_timer.wait_time = 1.0 # 1 seconde suffit
	broadcast_timer.timeout.connect(_send_broadcast)
	broadcast_timer.start()
	_send_broadcast()

func _send_broadcast():
	udp_broadcast.set_dest_address(current_broadcast_ip, BROADCAST_PORT)
	udp_broadcast.put_packet(MAGIC_WORD.to_utf8_buffer())
