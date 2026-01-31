extends Control

const GAME_PORT = 42069

@onready var ip_input = $CenterContainer/VBoxContainer/IPInput
# Optionnel : Un label pour afficher ton IP à donner aux amis
@onready var ip_label = $CenterContainer/VBoxContainer/IPLabel 

func _ready() -> void:
	# 1. Signaux réseau
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_lost)
	
	# 2. Afficher mon IP locale pour la donner aux amis
	var my_ip = _get_local_ip()
	if ip_label:
		ip_label.text = "Mon IP : " + my_ip
	print("LOBBY : Mon IP est " + my_ip)

# --- ACTIONS DES BOUTONS ---

func _on_host_button_pressed():
	# CRÉER UNE PARTIE PRIVÉE
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(GAME_PORT)
	
	if err == OK:
		multiplayer.multiplayer_peer = peer
		print("SERVEUR : Partie créée. En attente de joueurs...")
		_load_world()
	else:
		print("ERREUR : Impossible de créer le serveur (Port occupé ?).")

func _on_join_button_pressed():
	# REJOINDRE UNE PARTIE PRIVÉE
	var ip = ip_input.text.strip_edges()
	if ip == "": 
		print("ERREUR : Veuillez entrer une IP.")
		return
		
	print("CLIENT : Tentative de connexion vers ", ip, "...")
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, GAME_PORT)
	multiplayer.multiplayer_peer = peer

# --- GESTION DU RÉSEAU ---

func _on_connected_ok():
	print("RÉSEAU : Connecté au serveur avec succès !")
	_load_world()

func _on_connected_fail():
	print("RÉSEAU : Échec de la connexion. Vérifiez l'IP ou le Pare-feu.")
	multiplayer.multiplayer_peer = null # On reset

func _on_server_lost():
	print("RÉSEAU : Le serveur a fermé la partie.")
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _load_world():
	get_tree().change_scene_to_file("res://scenes/world.tscn")

# --- UTILITAIRE ---
func _get_local_ip() -> String:
	var addresses = IP.get_local_addresses()
	for ip in addresses:
		# On cherche une IP locale classique (192.168... ou 10...)
		if ip.begins_with("192.168.") or ip.begins_with("10."):
			return ip
	return "127.0.0.1"
