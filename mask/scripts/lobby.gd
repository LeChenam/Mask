extends Control

const PORT = 42069
const ADDRESS = "127.0.0.1"

func _ready() -> void:
	# On tente de créer le serveur
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT)
	
	if error == OK:
		multiplayer.multiplayer_peer = peer
		print("SERVEUR : Je suis l'hôte. Lancement du monde...")
		# On attend un tout petit peu avant de changer de scène
		await get_tree().create_timer(0.1).timeout
		get_tree().change_scene_to_file("res://world.tscn")
	else:
		# L'erreur "Couldn't create host" vient d'ici, c'est normal si 
		# un serveur tourne déjà sur ton PC.
		print("MODE CLIENT : Serveur déjà présent, prêt à rejoindre.")

func _on_join_button_pressed() -> void:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ADDRESS, PORT)
	
	if error != OK:
		print("ERREUR : Impossible de contacter le serveur.")
		return
		
	multiplayer.multiplayer_peer = peer
	print("CLIENT : Connexion en cours...")
	get_tree().change_scene_to_file("res://world.tscn")
