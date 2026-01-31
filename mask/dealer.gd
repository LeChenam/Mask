extends Node3D

enum GamePhase { WAITING, PRE_FLOP, FLOP, TURN, RIVER, SHOWDOWN }
var current_phase = GamePhase.WAITING

var deck = []
var turn_index = 0
var active_players = [] # IDs des joueurs encore dans le coup
var player_stacks = {}  # {id: argent_restant}

func start_game():
	if not multiplayer.is_server(): return
	
	print("LOGIQUE: Démarrage de la partie...")
	active_players = []
	player_stacks.clear()
	
	# Initialisation des joueurs
	for p in get_node("../PlayerContainer").get_children():
		var id = p.name.to_int()
		active_players.append(id)
		player_stacks[id] = 1000 # On donne 1000$ à tout le monde
	
	if active_players.size() < 1:
		print("Erreur: Pas assez de joueurs.")
		return

	prepare_deck()
	distribute_mains()

func prepare_deck():
	deck = range(52)
	deck.shuffle()

func distribute_mains():
	current_phase = GamePhase.PRE_FLOP
	
	for id in active_players:
		var hand = [deck.pop_back(), deck.pop_back()]
		# On envoie les cartes en secret au joueur via son script Player
		var player_node = get_node("../PlayerContainer/" + str(id))
		player_node.receive_cards.rpc_id(id, hand)
	
	turn_index = 0
	announce_turn()

# --- Gestion des Tours ---
func announce_turn():
	var current_id = active_players[turn_index]
	print("C'est au tour de : ", current_id)
	
	for id in active_players:
		var is_his_turn = (id == current_id)
		var player_node = get_node("../PlayerContainer/" + str(id))
		player_node.notify_turn.rpc_id(id, is_his_turn)

func next_turn():
	turn_index = (turn_index + 1) % active_players.size()
	announce_turn()

# --- Réception des Actions ---
@rpc("any_peer", "call_local", "reliable")
func server_receive_action(type: String, value: int):
	if not multiplayer.is_server(): return
	
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Sécurité: Est-ce bien son tour ?
	if sender_id != active_players[turn_index]:
		print("Triche/Erreur: Joueur ", sender_id, " a joué hors de son tour.")
		return
		
	if type == "BET":
		if player_stacks[sender_id] >= value:
			player_stacks[sender_id] -= value
			print("Joueur ", sender_id, " mise ", value, ". Nouveau stack: ", player_stacks[sender_id])
		else:
			print("Pas assez d'argent, mise annulée.")
			# On pourrait renvoyer une notification d'erreur ici
	
	elif type == "FOLD":
		print("Joueur ", sender_id, " se couche.")
		# Note: Idéalement, il faudrait retirer le joueur de active_players
	
	next_turn()
