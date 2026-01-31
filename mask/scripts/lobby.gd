extends Control

const PORT = 42069
const DISCOVERY_PORT = 42070 
const BROADCAST_ADDRESS = "255.255.255.255" 

@onready var ip_input = $VBoxContainer/IPInput 

var udp_peer := PacketPeerUDP.new()
var searching = true

func _ready() -> void:
	# Nettoyage au cas où une ancienne instance traîne
	multiplayer.multiplayer_peer = null
	
	multiplayer.connected_to_server.connect(_on_connection_success)
	multiplayer.connection_failed.connect(_on_connection_failed)
	
	var err = udp_peer.bind(DISCOVERY_PORT)
	if err != OK:
		print("INFO : Port UDP occupé, tentative de hosting forcé.")
		_start_hosting()
		return

	print("RECHERCHE : Scan du réseau local...")
	# Timer de 2 secondes
	get_tree().create_timer(2.0).timeout.connect(_on_scan_timeout)

func _process(_delta: float) -> void:
	if not searching: return

	if udp_peer.get_available_packet_count() > 0:
		var server_ip = udp_peer.get_packet_ip()
		var packet_data = udp_peer.get_packet().get_string_from_utf8()
		
		if server_ip != "" and server_ip != "0.0.0.0" and packet_data == "MASKARD_SERVER":
			print("SERVEUR TROUVÉ : IP -> ", server_ip)
			_stop_searching_and_join(server_ip)

func _on_scan_timeout():
	if searching:
		print("RECHERCHE : Délai dépassé. Aucun serveur trouvé.")
		_start_hosting_if_needed()

func _start_hosting_if_needed():
	searching = false
	# Debug : On regarde l'état actuel du peer
	print("DEBUG : État du peer avant hosting : ", multiplayer.multiplayer_peer)
	
	# On force le hosting même si le peer n'est pas strictement null (sécurité)
	print("ACTION : Lancement forcé du serveur...")
	_start_hosting()

func _start_hosting() -> void:
	# On s'assure que le port UDP de scan est fermé avant de devenir serveur
	udp_peer.close()
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT)
	
	if error == OK:
		multiplayer.multiplayer_peer = peer
		print("SERVEUR : Créé avec succès (ID 1).")
		
		# On lance l'annonce pour les autres
		_start_broadcasting()
		
		# Vérification du chemin de la scène
		var scene_path = "res://world.tscn"
		if FileAccess.file_exists(scene_path):
			print("SERVEUR : Chargement de la scène...")
			get_tree().change_scene_to_file(scene_path)
		else:
			print("ERREUR CRITIQUE : Le fichier res://world.tscn est introuvable !")
	else:
		print("ERREUR SERVEUR : Code d'erreur -> ", error)

func _start_broadcasting() -> void:
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = 1.0
	timer.timeout.connect(func():
		udp_peer.set_dest_address(BROADCAST_ADDRESS, DISCOVERY_PORT)
		udp_peer.put_packet("MASKARD_SERVER".to_utf8_buffer())
	)
	timer.autostart = true
	timer.start()
	print("BROADCAST : Le serveur envoie son signal.")

func _join_server(ip: String) -> void:
	print("CLIENT : Connexion vers ", ip)
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, PORT)
	if error == OK:
		multiplayer.multiplayer_peer = peer
	else:
		print("ERREUR CLIENT : ", error)

func _stop_searching_and_join(ip: String):
	searching = false
	udp_peer.close()
	_join_server(ip)

func _on_join_button_pressed() -> void:
	searching = false
	var target_ip = ip_input.text if ip_input.text != "" else "127.0.0.1"
	_join_server(target_ip)

func _on_connection_success():
	print("RESEAU : Connecté !")
	get_tree().change_scene_to_file("res://world.tscn")

func _on_connection_failed():
	print("RESEAU : Échec.")
