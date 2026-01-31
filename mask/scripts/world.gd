extends Node

const IP_ADRESS: String = "localhost"
const PORT: int =42069

var peer: ENetMultiplayerPeer

func start_server() -> void:
	peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT)
	multiplayer.multiplayer_peer = peer
	
func start_client() -> void: 
	peer = ENetMultiplayerPeer.new()
	peer.create_cleint(IP_ADRESS, PORT)
	multiplayer.multiplayer_peer = peer

func _on_player_connected(peer_id):
	if not multiplayer.is_server():
		return
	
	print("Le joueur " + str(peer_id) + " arrive. Je le spawn")
	
	var player = preload("res://player.tscn").instantiate()
	
	player.name = str(peer_id)
	
	$PlayerContainer.add_child(player)
	
func setup_player_position(player):
	var player_count = $PlayerContainer.get_child_count()
	player.position = Vector3(player_count * 2.0,0,0)
		
	setup_player_position(player)
