extends Node
# ============================================================================
# NETWORK MANAGER - Singleton pour gérer tout le networking du jeu
# ============================================================================
# Ajouter ce script comme Autoload dans Project Settings > Autoload
# Nom suggéré : "Network" ou "NetworkManager"

signal server_found(ip: String)
signal connection_established
signal connection_failed
signal server_disconnected
signal player_joined(peer_id: int)
signal player_left(peer_id: int)

# --- CONFIGURATION ---
const GAME_PORT = 42069
const BROADCAST_PORT = 8989
const MAGIC_WORD = "MASKARD_SERVER"
const SCAN_TIMEOUT = 4.0
const BROADCAST_INTERVAL = 0.5

# --- ÉTAT ---
var is_searching := false
var is_hosting := false
var current_broadcast_ip := "255.255.255.255"
var my_local_ips: Array = []
var player_name: String = "Player"

# --- UDP ---
var udp := PacketPeerUDP.new()
var broadcast_timer := Timer.new()

# ============================================================================
# INITIALISATION
# ============================================================================

func _ready():
	# Connexion des signaux Godot multiplayer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	# Préparation du timer de broadcast
	add_child(broadcast_timer)
	broadcast_timer.wait_time = BROADCAST_INTERVAL
	broadcast_timer.timeout.connect(_send_broadcast)
	
	# Calcul des IPs locales
	current_broadcast_ip = _get_local_broadcast_ip()
	my_local_ips = IP.get_local_addresses()
	print("NETWORK : Broadcast IP -> ", current_broadcast_ip)

# ============================================================================
# UTILITAIRES RÉSEAU
# ============================================================================

func _get_local_broadcast_ip() -> String:
	"""Retourne l'adresse de broadcast locale (ex: 192.168.1.255)"""
	var addresses = IP.get_local_addresses()
	for ip in addresses:
		if ip.begins_with("192.168.") or ip.begins_with("10."):
			var parts = ip.split(".")
			parts[3] = "255"
			return ".".join(parts)
	return "255.255.255.255"

func is_server() -> bool:
	"""Retourne true si on est le serveur"""
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()

func is_client() -> bool:
	"""Retourne true si on est un client connecté"""
	return multiplayer.has_multiplayer_peer() and not multiplayer.is_server()

func get_my_id() -> int:
	"""Retourne notre ID réseau (1 pour le serveur)"""
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return 0

func get_connected_peers() -> Array:
	"""Retourne la liste des IDs connectés"""
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_peers()
	return []

# ============================================================================
# DISCOVERY - Recherche automatique de serveur
# ============================================================================

func start_server_discovery():
	"""Démarre la recherche de serveur sur le réseau local"""
	is_searching = true
	
	# Bind UDP pour écouter
	udp.set_broadcast_enabled(true)
	var err = udp.bind(BROADCAST_PORT)
	
	if err == OK:
		print("NETWORK : Écoute UDP sur port ", BROADCAST_PORT)
	else:
		print("NETWORK : Port UDP occupé (une instance tourne peut-être déjà)")
	
	# Timer pour timeout
	print("NETWORK : Recherche de serveur pendant ", SCAN_TIMEOUT, " secondes...")
	get_tree().create_timer(SCAN_TIMEOUT).timeout.connect(_on_discovery_timeout)

func stop_discovery():
	"""Arrête la recherche de serveur"""
	is_searching = false

func _process(_delta):
	# Écoute des paquets UDP si on cherche un serveur
	if is_searching and udp.get_available_packet_count() > 0:
		var sender_ip = udp.get_packet_ip()
		var packet = udp.get_packet()
		var message = packet.get_string_from_utf8()
		
		# Ignorer nos propres messages
		var is_my_own = sender_ip in my_local_ips
		
		if message == MAGIC_WORD and sender_ip != "" and sender_ip != "0.0.0.0" and not is_my_own:
			print("NETWORK : Serveur trouvé à ", sender_ip)
			server_found.emit(sender_ip)

func _on_discovery_timeout():
	"""Appelé quand le timeout de recherche est atteint"""
	if is_searching:
		print("NETWORK : Aucun serveur trouvé (timeout)")
		# On ne fait rien automatiquement - c'est au lobby de décider

# ============================================================================
# HOSTING - Créer un serveur
# ============================================================================

func host_game() -> bool:
	"""Crée un serveur. Retourne true si succès."""
	stop_discovery()
	
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(GAME_PORT)
	
	if err != OK:
		print("NETWORK : Erreur création serveur : ", err)
		return false
	
	multiplayer.multiplayer_peer = peer
	is_hosting = true
	print("NETWORK : Serveur démarré (ID 1) sur port ", GAME_PORT)
	
	# Démarrer le broadcast pour que les clients nous trouvent
	_start_broadcasting()
	
	return true

func _start_broadcasting():
	"""Démarre le broadcast UDP pour être découvert"""
	print("NETWORK : Broadcast LAN actif")
	_send_broadcast() # Envoyer immédiatement
	broadcast_timer.start()

func _send_broadcast():
	"""Envoie un paquet de découverte"""
	udp.set_dest_address(current_broadcast_ip, BROADCAST_PORT)
	udp.put_packet(MAGIC_WORD.to_utf8_buffer())

func stop_broadcasting():
	"""Arrête le broadcast (quand on n'accepte plus de joueurs)"""
	broadcast_timer.stop()
	print("NETWORK : Broadcast arrêté")

# ============================================================================
# JOINING - Rejoindre un serveur
# ============================================================================

func join_game(ip: String) -> bool:
	"""Rejoint un serveur à l'IP donnée. Retourne true si la tentative démarre."""
	stop_discovery()
	broadcast_timer.stop()
	
	print("NETWORK : Connexion vers ", ip, ":", GAME_PORT, "...")
	
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, GAME_PORT)
	
	if err != OK:
		print("NETWORK : Erreur création client : ", err)
		return false
	
	multiplayer.multiplayer_peer = peer
	return true

# ============================================================================
# CALLBACKS RÉSEAU INTERNES
# ============================================================================

func _on_connected_to_server():
	"""Appelé quand on se connecte au serveur (côté client)"""
	print("NETWORK : Connecté au serveur !")
	udp.close() # On n'a plus besoin de l'UDP
	connection_established.emit()

func _on_connection_failed():
	"""Appelé quand la connexion échoue"""
	print("NETWORK : Échec de connexion")
	connection_failed.emit()

func _on_server_disconnected():
	"""Appelé quand le serveur se déconnecte"""
	print("NETWORK : Serveur déconnecté")
	_cleanup()
	server_disconnected.emit()

func _on_peer_connected(peer_id: int):
	"""Appelé quand un joueur se connecte"""
	print("NETWORK : Joueur ", peer_id, " connecté")
	player_joined.emit(peer_id)

func _on_peer_disconnected(peer_id: int):
	"""Appelé quand un joueur se déconnecte"""
	print("NETWORK : Joueur ", peer_id, " déconnecté")
	player_left.emit(peer_id)

# ============================================================================
# NETTOYAGE
# ============================================================================

func _cleanup():
	"""Nettoie les ressources réseau"""
	is_searching = false
	is_hosting = false
	broadcast_timer.stop()
	udp.close()

func disconnect_from_network():
	"""Déconnexion complète du réseau"""
	_cleanup()
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
	print("NETWORK : Déconnecté")

func _exit_tree():
	_cleanup()
