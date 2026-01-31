extends Control

const PORT = 42069
# On utilise le chemin corrigé vers ton LineEdit
@onready var ip_input = $VBoxContainer/IPInput 

func _ready() -> void:
	# 1. On connecte les signaux RÉSEAU une seule fois ici
	multiplayer.connected_to_server.connect(_on_connection_success)
	multiplayer.connection_failed.connect(_on_connection_failed)
	
	# 2. On tente de créer le serveur (Logique habituelle)
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT)
	
	if error == OK:
		multiplayer.multiplayer_peer = peer
		print("SERVEUR : Lancé sur 192.168.1.195")
		await get_tree().create_timer(0.1).timeout
		get_tree().change_scene_to_file("res://world.tscn")
	else:
		print("MODE CLIENT : Prêt à rejoindre.")

func _on_join_button_pressed() -> void:
	# On récupère l'IP (ex: 192.168.1.195)
	var target_ip = ip_input.text
	if target_ip == "":
		target_ip = "127.0.0.1"

	print("Tentative de connexion vers : ", target_ip)
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(target_ip, PORT)
	
	if error != OK:
		print("Erreur de création du client : ", error)
		return
		
	multiplayer.multiplayer_peer = peer

# --- Fonctions de rappel (Callbacks) ---

func _on_connection_success():
	print("SUCCÈS : Connecté au serveur !")
	get_tree().change_scene_to_file("res://world.tscn")

func _on_connection_failed():
	print("ÉCHEC : La connexion a échoué. Vérifiez l'IP ou le Pare-feu.")
