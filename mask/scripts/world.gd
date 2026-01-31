extends Node3D

# --- CONFIGURATION DU JEU ---
enum GamePhase { PRE_FLOP, FLOP, TURN, RIVER, SHOWDOWN }
var current_phase: GamePhase = GamePhase.PRE_FLOP
var deck: Array = []
var turn_index: int = 0

# --- RÉFÉRENCES AUX NOEUDS ---
@onready var player_container = $PlayerContainer
@onready var spawn_points = $SpawnPoints
@onready var card_container = $CardContainer 

# --- CONFIGURATION LAN (Variables qui manquaient) ---
const BROADCAST_PORT = 8989
const MAGIC_WORD = "MASKARD_SERVER"
var udp_broadcast = PacketPeerUDP.new()
var broadcast_timer = Timer.new()
var current_broadcast_ip = "255.255.255.255"

func _ready():
	# Sécurité : Si pas de réseau, on ne fait rien (ou retour au menu)
	if not multiplayer.has_multiplayer_peer(): 
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		return

	# Connexions
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	
	# Initialisation Serveur
	if multiplayer.is_server():
		print("--- SERVEUR : Lobby d'attente ouvert (ID 1) ---")
		print("--- ATTENTE : Il faut au moins 2 joueurs pour lancer (Espace) ---")
		
		# On crée notre propre joueur
		spawn_player(1) 
		
		# On lance le broadcast pour que les autres nous trouvent
		_setup_broadcast()

func _exit_tree():
	# Nettoyage propre du réseau
	if multiplayer.is_server():
		broadcast_timer.stop()
		udp_broadcast.close()

# --- GESTION DES JOUEURS ---

func _on_player_connected(peer_id):
	if not multiplayer.is_server(): return
	print("--- SERVEUR : Le joueur ", peer_id, " a rejoint la partie.")
	spawn_player(peer_id)
	
	var count = player_container.get_child_count()
	if count >= 2:
		print("--- INFO : ", count, " joueurs présents. Appuyez sur ESPACE pour lancer.")

func _on_player_disconnected(peer_id):
	if not multiplayer.is_server(): return
	if player_container.has_node(str(peer_id)):
		player_container.get_node(str(peer_id)).queue_free()

func spawn_player(id):
	var player_scene = preload("res://scenes/player.tscn") 
	var new_player = player_scene.instantiate()
	new_player.name = str(id)
	player_container.add_child(new_player, true)
	_setup_player_position(new_player)

func _setup_player_position(player_node):
	var points = spawn_points.get_children()
	if points.size() > 0:
		var index = player_container.get_child_count() - 1
		var target_point = points[index % points.size()]
		player_node.global_transform = target_point.global_transform

# --- LANCEMENT DE LA PARTIE ---

func _input(event):
	# Seul le serveur peut lancer la partie avec la touche ESPACE (ui_accept)
	if multiplayer.is_server() and event.is_action_pressed("ui_accept"):
		attempt_start_game()

func attempt_start_game():
	var player_count = player_container.get_child_count()
	
	if player_count >= 2:
		print("SERVEUR : --- LANCEMENT DE LA PARTIE ! ---")
		start_game()
	else:
		print("SERVEUR : Pas assez de joueurs (" + str(player_count) + "/2). Attendez vos amis.")

func start_game():
	# 1. Création du deck
	deck.clear()
	for i in range(52): deck.append(i)
	deck.shuffle()

	# 2. Nettoyer la table
	for c in card_container.get_children(): 
		c.queue_free()

	# 3. Initialiser
	current_phase = GamePhase.PRE_FLOP
	turn_index = 0
	
	# 4. Distribuer
	distribuer_mains()

func distribuer_mains():
	print("SERVEUR: Distribution des cartes...")
	# Donner 2 cartes à chaque joueur
	for i in range(2):
		for player in player_container.get_children():
			var p_id = player.name.to_int()
			distribuer_carte_a(p_id)
			await get_tree().create_timer(0.2).timeout 
			
	next_turn()

func distribuer_carte_a(target_id):
	if deck.is_empty(): return

	var card_val = deck.pop_back()
	var card = preload("res://scenes/card.tscn").instantiate()

	card.name = "Card_" + str(card_val) + "_" + str(randi()) 
	card.card_id = card_val 

	card_container.add_child(card, true)

	card.set_multiplayer_authority(target_id)

	var player_node = player_container.get_node(str(target_id))
	if player_node:
		card.global_position = player_node.global_position + Vector3(0, 1.0, 0.5) 

func next_turn():
	var players = player_container.get_children()
	if players.size() == 0: return

	turn_index = (turn_index + 1) % players.size()
	
	var current_player_node = players[turn_index]
	var pid = current_player_node.name.to_int()
	
	print("C'est au tour du joueur : " + str(pid))
	
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
	broadcast_timer.wait_time = 1.0 
	broadcast_timer.timeout.connect(_send_broadcast)
	broadcast_timer.start()
	_send_broadcast()

func _send_broadcast():
	udp_broadcast.set_dest_address(current_broadcast_ip, BROADCAST_PORT)
	udp_broadcast.put_packet(MAGIC_WORD.to_utf8_buffer())
