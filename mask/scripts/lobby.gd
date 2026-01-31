extends Control

const PORT = 42069
# On ne met plus d'adresse par défaut ici pour permettre le LAN
@onready var ip_input = $IPInput 

func _ready() -> void:
	# Système de serveur automatique pour le premier PC lancé
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT)
	
	if error == OK:
		multiplayer.multiplayer_peer = peer
		print("SERVEUR : Je suis l'hôte LAN. IP : 192.168.1.195")
		await get_tree().create_timer(0.1).timeout
		get_tree().change_scene_to_file("res://world.tscn")
	else:
		# Si le port est déjà pris ou si on veut juste être client
		print("MODE CLIENT : Prêt à entrer une IP pour rejoindre.")

func _on_join_button_pressed() -> void:
	# On récupère l'IP tapée dans le LineEdit
	var target_ip = ip_input.text
	
	# Sécurité : si le champ est vide, on tente le local
	if target_ip == "":
		target_ip = "127.0.0.1"

	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(target_ip, PORT)
	
	if error != OK:
		print("ERREUR : Impossible d'initier la connexion vers " + target_ip)
		return
		
	multiplayer.multiplayer_peer = peer
	print("CLIENT : Tentative de connexion vers " + target_ip + "...")
	get_tree().change_scene_to_file("res://world.tscn")
