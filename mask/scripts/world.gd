extends Node3D # Important : Node3D, pas Node ou Control !

# Référence au container des joueurs
@onready var player_container = $PlayerContainer
# --- AJOUT ICI : Référence au dossier des points de spawn ---
@onready var spawn_points = $SpawnPoints

# --- Broadcast LAN pour que de nouveaux joueurs puissent rejoindre ---
const BROADCAST_PORT = 8989
const MAGIC_WORD = "MASKARD_SERVER"
var udp_broadcast = PacketPeerUDP.new()
var broadcast_timer = Timer.new()
var current_broadcast_ip = "255.255.255.255"

func _get_local_broadcast_ip() -> String:
	var addresses = IP.get_local_addresses()
	for ip in addresses:
		if ip.begins_with("192.168.") or ip.begins_with("10."):
			var parts = ip.split(".")
			parts[3] = "255"
			return ".".join(parts)
	return "255.255.255.255"

func _ready():
	# Si on n'est pas sur le réseau, on ne fait rien (sécurité)
	if not multiplayer.has_multiplayer_peer(): return

	# On connecte les signaux pour savoir quand quelqu'un arrive ou part
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	
	# Si JE SUIS LE SERVEUR, je dois gérer les spawns ET continuer à broadcaster
	if multiplayer.is_server():
		print("--- SERVEUR : Monde chargé. Création de mon propre joueur (ID 1) ---")
		spawn_player(1)
		
		# Démarrer le broadcast continu pour les nouveaux joueurs
		_setup_broadcast()

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
	var player_scene = preload("res://scenes/player.tscn")
	var new_player = player_scene.instantiate()
	
	# CRUCIAL : Le nom du node DOIT être l'ID réseau
	new_player.name = str(id)
	
	# On l'ajoute au container (surveillé par le MultiplayerSpawner)
	player_container.add_child(new_player, true)
	
	# --- CHANGEMENT ICI : Logique des SpawnPoints ---
	var points = spawn_points.get_children()
	
	if points.size() > 0:
		# On récupère l'index du joueur (0 pour le 1er, 1 pour le 2ème...)
		var index = player_container.get_child_count() - 1
		
		# Le modulo (%) permet de revenir au siège 0 si on a plus de joueurs que de sièges
		var target_point = points[index % points.size()]
		
		# On applique la Position ET la Rotation (pour qu'il regarde la table)
		new_player.global_transform = target_point.global_transform
	else:
		# Fallback si tu as oublié de mettre les markers
		print("ERREUR : Aucun marker dans SpawnPoints !")
		new_player.global_position = Vector3(0, 2, 0)

# --- BROADCAST CONTINU POUR LES NOUVEAUX JOUEURS ---
func _setup_broadcast():
	current_broadcast_ip = _get_local_broadcast_ip()
	print("WORLD : Broadcast LAN actif sur ", current_broadcast_ip)
	
	udp_broadcast.set_broadcast_enabled(true)
	
	# Timer pour broadcaster toutes les 0.5 secondes
	add_child(broadcast_timer)
	broadcast_timer.wait_time = 0.5
	broadcast_timer.timeout.connect(_send_broadcast)
	broadcast_timer.start()
	
	# Envoyer immédiatement un premier broadcast
	_send_broadcast()

func _send_broadcast():
	udp_broadcast.set_dest_address(current_broadcast_ip, BROADCAST_PORT)
	udp_broadcast.put_packet(MAGIC_WORD.to_utf8_buffer())

func _exit_tree():
	# Nettoyer proprement quand la scène est détruite
	if multiplayer.is_server():
		broadcast_timer.stop()
		udp_broadcast.close()
