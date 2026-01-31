extends Node3D

const PokerHandEvaluator = preload("res://scripts/Game/HandEvaluator.gd")

enum GamePhase { WAITING, PRE_FLOP, FLOP, TURN, RIVER, SHOWDOWN }
var current_phase = GamePhase.WAITING

var deck = []
var active_players = [] 
var player_stacks = {} 
var player_hands = {}   # {peer_id: [card1, card2]}
var community_cards = []
var folded_players = []  # Joueurs couchés cette manche

# Gestion des mises
var pot = 0
var current_round_bets = {} # {peer_id: mise_actuelle_dans_ce_tour}
var highest_bet = 0
var turn_index = 0
var last_raiser_index = -1 # Pour savoir quand le tour de table est fini

# Système de Blinds
var dealer_button_index = 0  # Position du dealer (tourne à chaque manche)
var small_blind = 10
var big_blind = 20
var starting_stack = 1000

# ============================================================================
# DÉMARRAGE DU JEU (appelé par le bouton Start Game)
# ============================================================================

func request_start_game():
	"""Appelé par le serveur pour démarrer la partie"""
	if not multiplayer.is_server(): return
	if current_phase != GamePhase.WAITING: return
	
	var players_in_world = get_node("../PlayerContainer").get_children()
	if players_in_world.size() < 3:
		print("DEALER : Besoin d'au moins 3 joueurs pour commencer (max 5)")
		return
	
	print("DEALER : Démarrage de la partie !")
	start_game()

func start_game():
	if not multiplayer.is_server(): return
	
	# Reset global
	pot = 0
	community_cards.clear()
	player_hands.clear()
	folded_players.clear()
	
	# Nettoyer les cartes communes affichées
	for c in get_node("../CardContainer").get_children():
		c.queue_free()
	
	# Setup Joueurs
	active_players.clear()
	for p in get_node("../PlayerContainer").get_children():
		var id = p.name.to_int()
		active_players.append(id)
		if not player_stacks.has(id):
			player_stacks[id] = starting_stack
		sync_stack(id)
	
	# Rotation du dealer button
	dealer_button_index = (dealer_button_index + 1) % active_players.size()
	
	start_phase_pre_flop()

# ============================================================================
# PHASES DU JEU
# ============================================================================

func start_phase_pre_flop():
	current_phase = GamePhase.PRE_FLOP
	
	# Création et mélange du deck
	deck = range(52)
	deck.shuffle()
	
	# Distribution des cartes (2 par joueur)
	for id in active_players:
		var card1 = deck.pop_back()
		var card2 = deck.pop_back()
		player_hands[id] = [card1, card2]
		# Envoi secret au joueur concerné
		get_node("../PlayerContainer/" + str(id)).receive_cards.rpc_id(id, [card1, card2])
	
	# Prise des blinds
	collect_blinds()
	
	# Le joueur après la Big Blind commence
	var sb_index = (dealer_button_index + 1) % active_players.size()
	var bb_index = (dealer_button_index + 2) % active_players.size()
	turn_index = (bb_index + 1) % active_players.size()
	last_raiser_index = bb_index  # La BB compte comme une relance
	
	announce_turn()

func collect_blinds():
	"""Collecte les Small et Big Blinds"""
	var sb_index = (dealer_button_index + 1) % active_players.size()
	var bb_index = (dealer_button_index + 2) % active_players.size()
	
	var sb_player = active_players[sb_index]
	var bb_player = active_players[bb_index]
	
	# Small Blind
	var sb_amount = min(small_blind, player_stacks[sb_player])
	player_stacks[sb_player] -= sb_amount
	current_round_bets[sb_player] = sb_amount
	pot += sb_amount
	print("DEALER : Small Blind de ", sb_amount, "$ par joueur ", sb_player)
	
	# Big Blind
	var bb_amount = min(big_blind, player_stacks[bb_player])
	player_stacks[bb_player] -= bb_amount
	current_round_bets[bb_player] = bb_amount
	pot += bb_amount
	highest_bet = bb_amount
	print("DEALER : Big Blind de ", bb_amount, "$ par joueur ", bb_player)
	
	# Sync les stacks
	sync_stack(sb_player)
	sync_stack(bb_player)
	sync_pot()

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
	"""Distribue les cartes communes sur la table"""
	for i in range(count):
		var card_val = deck.pop_back()
		community_cards.append(card_val)
		spawn_community_card.rpc(card_val, community_cards.size() - 1)

func reset_betting_round():
	"""Reset pour un nouveau tour de mises"""
	current_round_bets.clear()
	highest_bet = 0
	
	# Init des mises à 0 pour les joueurs actifs (non-couchés)
	for id in active_players:
		if id not in folded_players:
			current_round_bets[id] = 0
	
	# Premier joueur après le dealer
	turn_index = (dealer_button_index + 1) % active_players.size()
	
	# Trouver un joueur actif
	while active_players[turn_index] in folded_players:
		turn_index = (turn_index + 1) % active_players.size()
	
	last_raiser_index = -1  # Personne n'a encore misé
	
	announce_turn()

# ============================================================================
# GESTION DES ACTIONS JOUEUR
# ============================================================================

@rpc("any_peer", "call_local", "reliable")
func server_receive_action(type: String, value: int):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Vérification : est-ce bien le tour de ce joueur ?
	if sender_id != active_players[turn_index]: 
		print("DEALER : Action rejetée - Pas le tour du joueur ", sender_id)
		return
	
	print("DEALER : Action reçue de ", sender_id, " : ", type, " (", value, ")")
	
	if type == "FOLD":
		handle_fold(sender_id)
	elif type == "BET":
		handle_bet(sender_id, value)
	elif type == "CHECK":
		handle_check(sender_id)

func handle_fold(player_id: int):
	"""Gère un joueur qui se couche"""
	folded_players.append(player_id)
	get_node("../PlayerContainer/" + str(player_id)).notify_turn.rpc_id(player_id, false)

	
	# Compter les joueurs encore actifs
	var remaining = []
	for id in active_players:
		if id not in folded_players:
			remaining.append(id)
	
	if remaining.size() == 1:
		# Victoire par forfait
		end_game_forfeit(remaining[0])
		return
	
	advance_to_next_player()

func handle_bet(player_id: int, amount: int):
	"""Gère une mise/relance"""
	var to_call = highest_bet - current_round_bets.get(player_id, 0)
	
	# Vérification de la mise minimum
	if amount < to_call and amount < player_stacks[player_id]:
		print("DEALER : Mise invalide - doit au moins suivre")
		return
	
	# Limiter au stack du joueur
	amount = min(amount, player_stacks[player_id])
	
	player_stacks[player_id] -= amount
	current_round_bets[player_id] = current_round_bets.get(player_id, 0) + amount
	pot += amount
	
	# Est-ce une relance ?
	if current_round_bets[player_id] > highest_bet:
		highest_bet = current_round_bets[player_id]
		last_raiser_index = turn_index
	
	sync_stack(player_id)
	sync_pot()
	
	advance_to_next_player()

func handle_check(player_id: int):
	"""Gère un check (parole)"""
	if highest_bet > current_round_bets.get(player_id, 0):
		print("DEALER : Check impossible - il y a une mise à suivre")
		return
	
	advance_to_next_player()

func advance_to_next_player():
	"""Passe au joueur suivant ou termine le tour"""
	var start_index = turn_index
	
	# Trouver le prochain joueur actif
	turn_index = (turn_index + 1) % active_players.size()
	while active_players[turn_index] in folded_players:
		turn_index = (turn_index + 1) % active_players.size()
		if turn_index == start_index:
			break  # Éviter boucle infinie
	
	# Vérifier si le tour de mises est terminé
	if is_betting_round_complete():
		proceed_to_next_phase()
	else:
		announce_turn()

func is_betting_round_complete() -> bool:
	"""Vérifie si tous les joueurs ont égalisé ou sont all-in"""
	var active_remaining = []
	for id in active_players:
		if id not in folded_players:
			active_remaining.append(id)
	
	# Si personne n'a misé et on est revenu au premier joueur
	if last_raiser_index == -1:
		# Tout le monde a check
		var first_active_index = (dealer_button_index + 1) % active_players.size()
		while active_players[first_active_index] in folded_players:
			first_active_index = (first_active_index + 1) % active_players.size()
		return turn_index == first_active_index
	
	# Si on revient au dernier relanceur
	return turn_index == last_raiser_index

func proceed_to_next_phase():
	"""Passe à la phase suivante du jeu"""
	match current_phase:
		GamePhase.PRE_FLOP: start_phase_flop()
		GamePhase.FLOP: start_phase_turn()
		GamePhase.TURN: start_phase_river()
		GamePhase.RIVER: determine_winner()

# ============================================================================
# FIN DE PARTIE
# ============================================================================

func end_game_forfeit(winner_id: int):
	"""Fin de manche par forfait (tout le monde s'est couché)"""
	print("DEALER : Victoire par forfait pour le joueur ", winner_id)
	
	player_stacks[winner_id] += pot
	sync_stack(winner_id)
	
	# Notifier tout le monde
	announce_winner.rpc([winner_id], pot)
	
	# Nouvelle manche après délai
	await get_tree().create_timer(4.0).timeout
	cleanup_and_restart()

func determine_winner():
	"""Détermine le gagnant au showdown"""
	current_phase = GamePhase.SHOWDOWN
	
	var scores = {}  # {player_id: score}
	var best_score = -1
	var winners = []
	
	print("--- SHOWDOWN ---")
	
	# Calculer le score de chaque joueur actif
	for id in active_players:
		if id in folded_players:
			continue
		
		var hand = player_hands[id]
		var score = PokerHandEvaluator.evaluate(hand, community_cards)
		scores[id] = score
		
		print("Joueur ", id, " : score = ", score)
		
		# Révéler les cartes à tout le monde
		var player_node = get_node("../PlayerContainer/" + str(id))
		player_node.show_hand_to_all.rpc(hand)
		
		if score > best_score:
			best_score = score
			winners = [id]
		elif score == best_score:
			winners.append(id)
	
	# Suspense
	await get_tree().create_timer(3.0).timeout
	
	# Distribution du pot
	var share = pot / winners.size()
	for winner_id in winners:
		player_stacks[winner_id] += share
		sync_stack(winner_id)
	
	print("DEALER : Gagnant(s) : ", winners, " - Pot partagé : ", share, "$ chacun")
	
	# Notifier les joueurs
	announce_winner.rpc(winners, pot)
	
	# Attendre et relancer
	await get_tree().create_timer(5.0).timeout
	cleanup_and_restart()

func cleanup_and_restart():
	"""Nettoie et prépare une nouvelle manche"""
	# Nettoyer les visuels
	for id in active_players:
		var player_node = get_node_or_null("../PlayerContainer/" + str(id))
		if player_node:
			player_node.clear_hand_visuals.rpc()
	
	# Reset et nouvelle manche
	current_phase = GamePhase.WAITING
	pot = 0
	
	# Vérifier si assez de joueurs ont encore des jetons
	var players_with_chips = []
	for id in active_players:
		if player_stacks.get(id, 0) > 0:
			players_with_chips.append(id)
	
	if players_with_chips.size() >= 2:
		start_game()
	else:
		print("DEALER : Fin de la session - pas assez de joueurs avec des jetons")
		announce_game_over.rpc()

# ============================================================================
# SYNCHRONISATION ET AFFICHAGE
# ============================================================================

func announce_turn():
	"""Informe les joueurs de qui doit jouer"""
	var current_id = active_players[turn_index]
	var to_call = highest_bet - current_round_bets.get(current_id, 0)
	
	for id in active_players:
		if id in folded_players:
			continue
		var is_turn = (id == current_id)
		get_node("../PlayerContainer/" + str(id)).notify_turn.rpc_id(id, is_turn, to_call)

func sync_pot():
	"""Synchronise le pot avec tous les joueurs"""
	for id in active_players:
		if id not in folded_players:
			get_node("../PlayerContainer/" + str(id)).update_pot.rpc_id(id, pot)

func sync_stack(player_id: int):
	"""Synchronise le stack d'un joueur"""
	var player_node = get_node_or_null("../PlayerContainer/" + str(player_id))
	if player_node:
		player_node.update_stack.rpc_id(player_id, player_stacks[player_id])

@rpc("authority", "call_local", "reliable")
func spawn_community_card(card_val: int, index: int):
	"""Affiche une carte commune sur la table"""
	var card = preload("res://scenes/card.tscn").instantiate()
	get_node("../CardContainer").add_child(card)
	
	# Position sur la table
	var spacing = 0.25
	var start_x = -0.5
	card.position = Vector3(start_x + index * spacing, 0.8, 0)
	card.rotation_degrees = Vector3(90, 0, 0)  # Face visible
	
	# Appliquer les visuels
	if card.has_method("set_card_visuals"):
		card.set_card_visuals(card_val)
	if card.has_method("reveal"):
		card.reveal()

@rpc("authority", "call_local", "reliable")
func announce_winner(winner_ids: Array, pot_amount: int):
	"""Notification du gagnant à tous les clients"""
	print("CLIENT : Les gagnants sont ", winner_ids, " - Pot : ", pot_amount)

@rpc("authority", "call_local", "reliable")
func announce_game_over():
	"""Notification de fin de session"""
	print("CLIENT : La session de poker est terminée")
