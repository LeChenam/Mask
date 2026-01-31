extends Control

const PORT = 42069
const ADDRESS = "127.0.0.1"

func _on_host_button_pressed() -> void:
	# 1. On crée le serveur DIRECTEMENT ici
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT)
	
	if error != OK:
		print("Erreur création serveur: " + str(error))
		return
		
	multiplayer.multiplayer_peer = peer
	print("Serveur lancé ! Chargement du monde...")
	
	# 2. Maintenant on charge la VRAIE scène World qui contient les noeuds
	get_tree().change_scene_to_file("res://world.tscn")

func _on_join_button_pressed() -> void:
	# 1. On crée le client DIRECTEMENT ici
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ADDRESS, PORT)
	
	if error != OK:
		print("Erreur connexion client")
		return
		
	multiplayer.multiplayer_peer = peer
	print("Connexion en cours...")
	
	get_tree().change_scene_to_file("res://world.tscn")
