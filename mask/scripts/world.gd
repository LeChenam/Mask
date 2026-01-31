extends Node

const IP_ADRESS: String = "127.0.0.1"
const PORT: int = 42069

var peer: ENetMultiplayerPeer

func _ready():
	# Signal déclenché quand quelqu'un se connecte au serveur
	multiplayer.peer_connected.connect(_on_player_connected)

func start_server() -> void:
	peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT)
	multiplayer.multiplayer_peer = peer
	print("Serveur lancé sur le port ", PORT)
	# L'host doit aussi spawner son propre personnage (ID 1)
	_on_player_connected(1)
	
func start_client() -> void: 
	peer = ENetMultiplayerPeer.new()
	# Correction de la faute de frappe : create_client
	peer.create_client(IP_ADRESS, PORT) 
	multiplayer.multiplayer_peer = peer
	print("Connexion au serveur...")

func _on_player_connected(peer_id):
	# Seul le serveur a le droit de spawner des joueurs
	if not multiplayer.is_server():
		return
	
	print("Le joueur " + str(peer_id) + " arrive. Spawn en cours...")
	
	var player = preload("res://player.tscn").instantiate()
	# On nomme le node avec l'ID pour que set_multiplayer_authority fonctionne
	player.name = str(peer_id)
	$PlayerContainer.add_child(player)
	
	# Positionnement sans boucle infinie
	setup_player_position(player)

func setup_player_position(player):
	var player_count = $PlayerContainer.get_child_count()
	# Décale chaque joueur de 2 mètres sur l'axe X
	player.position = Vector3(player_count * 2.0, 0, 0)
