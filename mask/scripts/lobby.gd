extends Control
# ============================================================================
# LOBBY - Interface de connexion simple avec boutons Host / Join
# ============================================================================

@onready var ip_input = $CenterContainer/VBoxContainer/IPInput
@onready var name_input = $CenterContainer/VBoxContainer/NameInput

func _ready():
	# Connexion aux signaux du NetworkManager
	NetworkManager.connection_established.connect(_on_connection_established)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	
	AudioManager.play("base_music", false, 0.6)
	AudioManager.play("ambiance_loop", false, 1)

# ============================================================================
# BOUTONS
# ============================================================================

func _on_host_button_pressed():
	"""Bouton : Créer une partie (devenir serveur)"""
	print("LOBBY : Création du serveur...")
	
	AudioManager.play("ui_click")
	_save_player_name()
	
	if NetworkManager.host_game():
		print("LOBBY : Serveur créé avec succès !")
		_load_world()
	else:
		print("LOBBY : Erreur lors de la création du serveur")

func _on_join_button_pressed():
	"""Bouton : Rejoindre une partie via IP"""
	var ip = ip_input.text.strip_edges()
	
	AudioManager.play("ui_click")
	
	# IP par défaut si vide
	if ip == "":
		ip = "127.0.0.1"
	
	_save_player_name()
	print("LOBBY : Connexion vers ", ip, "...")
	NetworkManager.join_game(ip)

func _on_ip_input_text_changed(new_text: String) -> void:
	AudioManager.play("ui_click")


func _save_player_name():
	"""Sauvegarde le nom du joueur dans le NetworkManager"""
	if name_input.text.strip_edges() != "":
		NetworkManager.player_name = name_input.text.strip_edges()
	print("LOBBY : Nom défini -> ", NetworkManager.player_name)

# ============================================================================
# CALLBACKS RÉSEAU
# ============================================================================

func _on_connection_established():
	"""Connexion réussie au serveur"""
	print("LOBBY : Connecté au serveur !")
	_load_world()

func _on_connection_failed():
	"""Échec de connexion"""
	print("LOBBY : Échec de la connexion")
	# Tu peux afficher un message d'erreur ici si tu veux

# ============================================================================
# NAVIGATION
# ============================================================================

func _load_world():
	"""Charge la scène du monde"""
	get_tree().change_scene_to_file("res://scenes/world.tscn")
