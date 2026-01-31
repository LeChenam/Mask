extends Control

const GAME_PORT = 42069
const BROADCAST_PORT = 8989
#const BROADCAST_ADDRESS = "255.255.255.255"
const MAGIC_WORD = "MASKARD_SERVER"

var current_broadcast_ip = "255.255.255.255" # Valeur par défaut

# --- Fonction utilitaire pour trouver l'adresse .255 locale ---
func _get_local_broadcast_ip() -> String:
	var addresses = IP.get_local_addresses()
	for ip in addresses:
		# On cherche une IP locale classique (type 192.168.x.x ou 10.x.x.x)
		if ip.begins_with("192.168.") or ip.begins_with("10."):
			var parts = ip.split(".")
			# On remplace le dernier chiffre par 255
			parts[3] = "255" 
			return ".".join(parts)
	return "255.255.255.255" # Fallback si on ne trouve rien

@onready var ip_input = $VBoxContainer/IPInput 

var udp = PacketPeerUDP.new()
var searching = true
var broadcast_timer = Timer.new()

func _ready() -> void:
	# 1. Signaux réseau
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_lost)

	# 2. Préparation UDP (Bind pour écouter)
	udp.set_broadcast_enabled(true)
	var err = udp.bind(BROADCAST_PORT)
	
	current_broadcast_ip = _get_local_broadcast_ip()
	print("LOBBY : Adresse de broadcast calculée -> ", current_broadcast_ip)
	
	if err == OK:
		print("LOBBY : Écoute du réseau sur le port ", BROADCAST_PORT)
	else:
		print("LOBBY : Port UDP occupé. Une instance tourne peut-être déjà ?")
		# On ne bloque pas, on continue, mais le scan auto ne marchera peut-être pas sur ce PC

	# 3. Timer de 2 secondes pour devenir Hôte si personne ne répond
	print("LOBBY : Recherche de serveur...")
	get_tree().create_timer(2.0).timeout.connect(_on_scan_timeout)
	
	# Timer pour envoyer le broadcast (sera activé si on devient Host)
	add_child(broadcast_timer)
	broadcast_timer.wait_time = 1.0
	broadcast_timer.timeout.connect(_send_broadcast)

func _process(_delta):
	# Si on cherche, on écoute les paquets UDP
	if searching and udp.get_available_packet_count() > 0:
		var sender_ip = udp.get_packet_ip()
		var packet = udp.get_packet()
		var message = packet.get_string_from_utf8()
		
		# On ignore nos propres messages (important !)
		if message == MAGIC_WORD and sender_ip != "" and sender_ip != "0.0.0.0":
			print("LOBBY : Serveur trouvé à l'IP : ", sender_ip)
			_join_game(sender_ip)

func _on_scan_timeout():
	if searching:
		print("LOBBY : Aucun serveur trouvé. Je deviens l'HÔTE.")
		_host_game()

# --- HOSTING ---
func _host_game():
	searching = false
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(GAME_PORT)
	
	if err == OK:
		multiplayer.multiplayer_peer = peer
		print("SERVEUR : Démarré (ID 1).")
		
		# On commence à crier "JE SUIS LÀ" sur le réseau
		broadcast_timer.start()
		
		_load_world()
	else:
		print("ERREUR : Impossible de créer le serveur.")

func _send_broadcast():
	# Le serveur envoie le mot magique à tout le monde
	udp.set_dest_address(current_broadcast_ip, BROADCAST_PORT)
	udp.put_packet(MAGIC_WORD.to_utf8_buffer())

# --- JOINING ---
func _join_game(ip: String):
	searching = false
	broadcast_timer.stop() # On arrête de broadcaster au cas où
	
	print("CLIENT : Connexion vers ", ip, "...")
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, GAME_PORT)
	multiplayer.multiplayer_peer = peer

# --- BOUTON MANUEL ---
func _on_join_button_pressed():
	searching = false
	var ip = ip_input.text
	if ip == "": ip = "127.0.0.1"
	_join_game(ip)

# --- CALLBACKS ---
func _on_connected_ok():
	print("RÉSEAU : Connecté au serveur !")
	_load_world()

func _on_connected_fail():
	print("RÉSEAU : Échec connexion.")
	searching = true # On recommence à chercher ?

func _on_server_lost():
	print("RÉSEAU : Connexion perdue.")
	get_tree().change_scene_to_file("res://lobby.tscn")

func _load_world():
	# On ferme le port UDP proprement avant de changer de scène
	udp.close()
	get_tree().change_scene_to_file("res://world.tscn")
