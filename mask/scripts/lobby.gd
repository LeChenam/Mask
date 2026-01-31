extends Control

# --- CONFIGURATION ---
const GAME_PORT = 42069         # Port pour le jeu (ENet)
const BROADCAST_PORT = 8989     # Port pour la détection LAN (UDP)
const BROADCAST_ADDRESS = "255.255.255.255"
const MAGIC_WORD = "MASKARD_SERVER" # Pour être sûr que c'est ton jeu

# --- VARIABLES RÉSEAU (Inspiré du Script A) ---
var udp_listener = UDPServer.new()   # Écoute les broadcasts (Client potentiel)
var udp_sender = PacketPeerUDP.new() # Envoie les broadcasts (Hôte)

var searching = true
var is_host = false

@onready var ip_input = $VBoxContainer/IPInput 

func _ready() -> void:
	# Nettoyage
	multiplayer.multiplayer_peer = null
	
	# Signaux du multijoueur (Jeu)
	multiplayer.connected_to_server.connect(_on_connection_success)
	multiplayer.connection_failed.connect(_on_connection_failed)
	
	# 1. Préparer l'envoi UDP (pour plus tard si on devient hôte)
	udp_sender.set_broadcast_enabled(true)
	
	# 2. Commencer à écouter sur le port de Broadcast
	var err = udp_listener.listen(BROADCAST_PORT)
	if err != OK:
		print("INFO: Impossible d'écouter sur le port de scan (peut-être déjà utilisé).")
		# Si on ne peut pas écouter, c'est probablement qu'une instance tourne déjà ici,
		# ou qu'on devrait juste essayer de hoster/rejoindre manuellement.
	
	print("RECHERCHE : Scan du réseau local en cours...")
	
	# 3. Lancer le Timer d'auto-host (2 secondes)
	get_tree().create_timer(2.0).timeout.connect(_on_scan_timeout)

func _process(_delta: float) -> void:
	# --- LOGIQUE SERVEUR (HÔTE) ---
	if is_host:
		# L'hôte crie son existence en boucle
		var data = {
			"key": MAGIC_WORD,
			"port": GAME_PORT # On indique aux clients sur quel port se connecter
		}
		var packet = var_to_bytes(data)
		udp_sender.set_dest_address(BROADCAST_ADDRESS, BROADCAST_PORT)
		udp_sender.put_packet(packet)
		return # L'hôte ne cherche pas d'autres serveurs

	# --- LOGIQUE CLIENT (RECHERCHE) ---
	if searching:
		udp_listener.poll() # Vérifie s'il y a des paquets
		
		if udp_listener.is_connection_available():
			var peer = udp_listener.take_connection()
			var sender_ip = peer.get_packet_ip()
			var packet_bytes = peer.get_packet()
			
			# On tente de lire les données
			var data = bytes_to_var(packet_bytes)
			
			# Vérification : Est-ce bien notre jeu ?
			if data is Dictionary and data.has("key") and data["key"] == MAGIC_WORD:
				print("SERVEUR TROUVÉ : IP -> ", sender_ip)
				var target_port = data.get("port", GAME_PORT)
				_stop_searching_and_join(sender_ip, target_port)

func _on_scan_timeout():
	if searching:
		print("RECHERCHE : Délai dépassé. Aucun serveur trouvé.")
		_start_hosting()

# --- FONCTIONS DE GESTION ---

func _start_hosting() -> void:
	searching = false
	udp_listener.stop() # On arrête d'écouter
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(GAME_PORT)
	
	if error == OK:
		multiplayer.multiplayer_peer = peer
		is_host = true
		print("SERVEUR : Créé avec succès sur le port ", GAME_PORT)
		_load_game_scene()
	else:
		print("ERREUR SERVEUR : Impossible de créer le serveur (Code ", error, ")")

func _stop_searching_and_join(ip: String, port: int):
	searching = false
	udp_listener.stop() # On arrête d'écouter pour ne pas spammer les tentatives
	_join_server(ip, port)

func _join_server(ip: String, port: int) -> void:
	print("CLIENT : Tentative de connexion vers ", ip, ":", port)
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)
	
	if error == OK:
		multiplayer.multiplayer_peer = peer
	else:
		print("ERREUR CLIENT : Impossible de créer le client (Code ", error, ")")
		# En cas d'échec critique, on pourrait relancer le scan ou hoster
		# _start_hosting() 

# --- BOUTON JOIN MANUEL (Optionnel) ---
func _on_join_button_pressed() -> void:
	searching = false
	var target_ip = ip_input.text if ip_input.text != "" else "127.0.0.1"
	_join_server(target_ip, GAME_PORT)

# --- CALLBACKS RESEAU ---
func _on_connection_success():
	print("RESEAU : Connecté au serveur !")
	_load_game_scene()

func _on_connection_failed():
	print("RESEAU : Échec de la connexion.")
	# Ici, tu pourrais remettre searching = true pour réessayer

func _load_game_scene():
	var scene_path = "res://world.tscn" # Assure-toi que ce chemin est bon
	if FileAccess.file_exists(scene_path):
		# Attention: en réseau, souvent seul l'hôte change la scène et les clients suivent
		# Mais pour l'instant, on le fait localement
		get_tree().change_scene_to_file(scene_path)
	else:
		print("ERREUR : Scène introuvable : ", scene_path)
