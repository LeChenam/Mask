extends Node3D

const HandEvaluator = preload("res://scripts/Game/HandEvaluator.gd")

enum GamePhase { PRE_FLOP, FLOP, TURN, RIVER, SHOWDOWN }
var current_phase = GamePhase.PRE_FLOP

var deck = []
var active_players = [] 
var player_stacks = {} 
var player_hands = {}   # {peer_id: [card1, card2]}
var community_cards = []

# Gestion des mises
var pot = 0
var current_round_bets = {} # {peer_id: mise_actuelle_dans_ce_tour}
var highest_bet = 0
var turn_index = 0
var last_raiser_index = 0 # Pour savoir quand le tour de table est fini

func start_game():
	if not multiplayer.is_server(): return
	
	# Reset global
	pot = 0
	community_cards.clear()
	player_hands.clear()
	get_node("../CardContainer").get_children().map(func(c): c.queue_free())
	
	# Setup Joueurs
	active_players.clear()
	for p in get_node("../PlayerContainer").get_children():
		var id = p.name.to_int()
		active_players.append(id)
		player_stacks[id] = player_stacks.get(id, 1000) # Garde le stack ou met 1000
		sync_data(id)

	start_phase_pre_flop()

# Gère la fin de manche prématurée (tout le monde Fold sauf un)
func end_game(winner_id: int):
	print("Fin de manche ! Vainqueur par forfait : ", winner_id)
	
	# 1. Le vainqueur rafle le pot
	player_stacks[winner_id] += pot
	
	# 2. On met à jour l'affichage de tout le monde
	sync_data(winner_id)
	
	# 3. Petit message dans la console ou UI (Optionnel)
	# send_global_message.rpc("Le joueur " + str(winner_id) + " gagne " + str(pot) + "$")
	
	# 4. On redémarre une manche après 4 secondes
	print("Nouvelle manche dans 4 secondes...")
	await get_tree().create_timer(4.0).timeout
	start_game()

func start_phase_pre_flop():
	current_phase = GamePhase.PRE_FLOP
	deck = range(52)
	deck.shuffle()
	
	# Distribution
	for id in active_players:
		var card1 = deck.pop_back()
		var card2 = deck.pop_back()
		player_hands[id] = [card1, card2]
		# Envoi secret
		get_node("../PlayerContainer/" + str(id)).receive_cards.rpc_id(id, [card1, card2])
	
	reset_betting_round()

func start_phase_flop():
	current_phase = GamePhase.FLOP
	deal_community(3)
	reset_betting_round()

func start_phase_turn():
	current_phase = GamePhase.TURN
	deal_community(1)
	reset_betting_round()

func start_phase_river():
	current_phase = GamePhase.RIVER
	deal_community(1)
	reset_betting_round()

func deal_community(count):
	for i in range(count):
		var card_val = deck.pop_back()
		community_cards.append(card_val)
		spawn_community_card.rpc(card_val)

func reset_betting_round():
	current_round_bets.clear()
	highest_bet = 0
	last_raiser_index = 0 # Le premier joueur commence
	turn_index = 0
	
	# Init des mises à 0 pour ce tour
	for id in active_players:
		current_round_bets[id] = 0
		
	announce_turn()

# --- Logique des Tours et Mises ---

@rpc("any_peer", "call_local", "reliable")
func server_receive_action(type: String, value: int):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Sécurité Tour
	if sender_id != active_players[turn_index]: return

	if type == "FOLD":
		active_players.erase(sender_id)
		get_node("../PlayerContainer/" + str(sender_id)).notify_turn.rpc_id(sender_id, false)
		if active_players.size() == 1:
			end_game(active_players[0]) # Victoire par forfait
			return
		# Ajustement index si on retire quelqu'un
		if turn_index >= active_players.size(): turn_index = 0
		
	elif type == "BET":
		var cost = value # Le joueur envoie le total qu'il veut mettre
		var actual_bet = cost - current_round_bets.get(sender_id, 0)
		
		if player_stacks[sender_id] >= actual_bet:
			player_stacks[sender_id] -= actual_bet
			current_round_bets[sender_id] = cost
			pot += actual_bet
			
			# Si on relance (Raise), on reset le tour de table
			if cost > highest_bet:
				highest_bet = cost
				last_raiser_index = turn_index 
			
			sync_data(sender_id)
			sync_pot()
			turn_index = (turn_index + 1) % active_players.size()
	
	check_round_end()

func check_round_end():
	# Si on est revenu au joueur qui a relancé en dernier, le tour est fini
	if turn_index == last_raiser_index:
		proceed_to_next_phase()
	else:
		announce_turn()

func proceed_to_next_phase():
	match current_phase:
		GamePhase.PRE_FLOP: start_phase_flop()
		GamePhase.FLOP: start_phase_turn()
		GamePhase.TURN: start_phase_river()
		GamePhase.RIVER: determine_winner()

func determine_winner():
	var best_score = -1
	var winners = []
	
	print("SHOWDOWN !")
	
	for id in active_players:
		var hand = player_hands[id]
	# On dit à TOUS les clients de révéler les cartes du joueur 'id'
		get_node("../PlayerContainer").rpc("show_player_hand", id, hand)
		var score = HandEvaluator.evaluate(player_hands[id], community_cards)
		print("Joueur ", id, " Score: ", score)
		
		if score > best_score:
			best_score = score
			winners = [id]
		elif score == best_score:
			winners.append(id)
	
	# Partage du pot si égalité
	var share = pot / winners.size()
	for w in winners:
		player_stacks[w] += share
		print("Gagnant : ", w, " gagne ", share)
		sync_data(w)
	
	# Restart auto après 5 sec
	await get_tree().create_timer(5.0).timeout
	start_game()

# --- Affichage et Sync ---

func announce_turn():
	var current_id = active_players[turn_index]
	var to_call = highest_bet - current_round_bets.get(current_id, 0)
	
	for id in active_players:
		var is_turn = (id == current_id)
		get_node("../PlayerContainer/" + str(id)).notify_turn.rpc_id(id, is_turn, to_call)

func sync_pot():
	for id in active_players:
		get_node("../PlayerContainer/" + str(id)).update_pot.rpc_id(id, pot)

func sync_data(id):
	get_node("../PlayerContainer/" + str(id)).update_stack.rpc_id(id, player_stacks[id])

@rpc("authority", "call_local", "reliable")
func spawn_community_card(card_val):
	var card = preload("res://card.tscn").instantiate()
	# Configuration visuelle de la carte ici (Texture, etc)
	# ...
	get_node("../CardContainer").add_child(card)
	# Animation simple pour la placer au centre
	var offset = get_node("../CardContainer").get_child_count() * 0.2
	card.position = Vector3(offset - 0.5, 0, 0) # Ajuste selon ta table
