extends Node3D
# ============================================================================
# GAME MANAGER - Gestion complète d'une partie de poker Texas Hold'em
# ============================================================================
# À attacher au nœud Dealer dans world.tscn

const HandEvaluator = preload("res://scripts/Game/HandEvaluator.gd")

enum GamePhase { WAITING, PRE_FLOP, FLOP, TURN, RIVER, SHOWDOWN }
var current_phase = GamePhase.WAITING

# --- DECK ET CARTES ---
var deck = []
var community_cards = []

# --- JOUEURS ---
var active_players = []    # IDs des joueurs encore dans la manche
var all_players = []       # IDs de tous les joueurs à la table
var folded_players = []    # IDs des joueurs qui ont fold
var player_hands = {}      # {peer_id: [card1, card2]}
var player_stacks = {}     # {peer_id: stack_amount}

# --- BLINDS & DEALER ---
const SMALL_BLIND = 10
const BIG_BLIND = 20
var dealer_button_index = 0  # Position du bouton dealer

# --- MISES ---
var pot = 0
var side_pots = []         # Pour gérer les all-ins multiples (optionnel pour v1)
var current_bets = {}      # {peer_id: montant_misé_ce_TOUR}
var highest_bet = 0        # Plus grosse mise de ce tour
var min_raise = BIG_BLIND  # Relance minimum

# --- TOUR DE PAROLE ---
var current_player_index = 0
var last_aggressor_index = 0  # Dernier à avoir relancé
var action_count = 0

# --- ÉTAT ---
var game_started = false
var waiting_for_player_action = false

# ==============================================================================
# INITIALISATION
# ==============================================================================

func _ready():
	if not multiplayer.is_server():
		return
	
	await get_tree().create_timer(0.5).timeout
	print("\n╔══════════════════════════════╗")
	print("║   DEALER PRÊT - POKER v1.0   ║")
	print("╚══════════════════════════════╝\n")
	
	_initialize_players()

func _initialize_players():
	"""Initialise tous les joueurs présents avec leur stack"""
	var player_container = get_node("../PlayerContainer")
	
	# VIDER d'abord pour éviter les doublons
	all_players.clear()
	player_stacks.clear()
	
	for player_node in player_container.get_children():
		var peer_id = player_node.name.to_int()
		all_players.append(peer_id)
		player_stacks[peer_id] = 1000
		
		# Sync le stack initial
		player_node.update_stack.rpc(1000)
		
		print("→ Joueur ", peer_id, " ajouté (Stack: 1000)")
	
	print("✓ Table initialisée : ", all_players.size(), " joueur(s)")
	
	if can_start_game():
		print("✓ Prêt à démarrer (", all_players.size(), " joueurs)")
		_notify_all_ready()
	else:
		print("⚠ Pas assez de joueurs (", all_players.size(), "/2 min)")

func can_start_game() -> bool:
	return all_players.size() >= 2 and all_players.size() <= 5

func _notify_all_ready():
	"""Notifie tous les joueurs que le bouton START peut s'afficher"""
	for peer_id in all_players:
		var player_node = get_node("../PlayerContainer/" + str(peer_id))
		player_node.show_start_button.rpc()

# ==============================================================================
# DÉMARRAGE DE LA PARTIE (Appelé par le premier joueur qui clique START)
# ==============================================================================

@rpc("any_peer", "call_local", "reliable")
func request_start_game():
	_initialize_players()
	print("DEBUG: game_started = ", game_started)
	print("DEBUG: can_start = ", can_start_game())
	print("DEBUG: nb joueurs = ", all_players.size())
	if not multiplayer.is_server():
		return
	
	if game_started or not can_start_game():
		print("⚠ Impossible de démarrer")
		return
	
	print("\n╔══════════════════════════════╗")
	print("║    PARTIE LANCÉE !           ║")
	print("╚══════════════════════════════╝")
	
	game_started = true
	# Cacher le bouton START chez tout le monde
	for peer_id in all_players:
		var player_node = get_node("../PlayerContainer/" + str(peer_id))
		player_node.hide_start_button.rpc()

	start_new_hand()

# ==============================================================================
# NOUVELLE MAIN
# ==============================================================================

func start_new_hand():
	"""Démarre une nouvelle main de poker"""
	if not multiplayer.is_server():
		return
	
	print("\n┌─────────────────────────────┐")
	print("│   NOUVELLE MAIN - PRE-FLOP  │")
	print("└─────────────────────────────┘")
	
	# Reset
	current_phase = GamePhase.PRE_FLOP
	pot = 0
	community_cards.clear()
	player_hands.clear()
	folded_players.clear()
	active_players = all_players.duplicate()
	
	# Création du deck
	deck = range(52)
	deck.shuffle()
	
	# Avancer le bouton dealer
	dealer_button_index = (dealer_button_index + 1) % all_players.size()
	
	# Distribution des cartes
	_deal_hole_cards()
	
	# Poster les blinds
	_post_blinds()
	
	# Démarrer le tour de parole PRE-FLOP
	await get_tree().create_timer(1.0).timeout
	_start_betting_round()

func _deal_hole_cards():
	"""Distribue 2 cartes à chaque joueur"""
	print("\n📇 Distribution des cartes...")
	
	for peer_id in active_players:
		var card1 = deck.pop_back()
		var card2 = deck.pop_back()
		player_hands[peer_id] = [card1, card2]
		
		# Envoi sécurisé des cartes AU JOUEUR UNIQUEMENT
		var player_node = get_node("../PlayerContainer/" + str(peer_id))
		player_node.receive_cards.rpc_id(peer_id, [card1, card2])
		
		print("  → Joueur ", peer_id, " reçoit 2 cartes")

func _post_blinds():
	"""Fait payer les blinds (small + big)"""
	var sb_index = (dealer_button_index + 1) % all_players.size()
	var bb_index = (dealer_button_index + 2) % all_players.size()
	
	var sb_id = all_players[sb_index]
	var bb_id = all_players[bb_index]
	
	# Small Blind
	_force_bet(sb_id, SMALL_BLIND)
	print("💵 Small Blind (", SMALL_BLIND, "$) → Joueur ", sb_id)
	
	# Big Blind
	_force_bet(bb_id, BIG_BLIND)
	print("💵 Big Blind (", BIG_BLIND, "$) → Joueur ", bb_id)
	
	highest_bet = BIG_BLIND
	last_aggressor_index = bb_index

func _force_bet(peer_id: int, amount: int):
	"""Force un joueur à miser (pour les blinds)"""
	var actual_bet = min(amount, player_stacks[peer_id])
	
	player_stacks[peer_id] -= actual_bet
	current_bets[peer_id] = actual_bet
	pot += actual_bet
	
	# Update UI
	var player_node = get_node("../PlayerContainer/" + str(peer_id))
	player_node.update_stack.rpc(player_stacks[peer_id])
	_sync_pot_to_all()

# ==============================================================================
# TOURS DE MISES
# ==============================================================================

func _start_betting_round():
	"""Démarre un tour de mises"""
	waiting_for_player_action = true
	action_count = 0
	
	# Reset des mises pour ce nouveau tour
	current_bets.clear()
	for peer_id in active_players:
		current_bets[peer_id] = 0
	
	# On recommence après les blinds au pré-flop, sinon après le dealer
	if current_phase == GamePhase.PRE_FLOP:
		var first_to_act = (dealer_button_index + 3) % all_players.size()
		current_player_index = first_to_act
	else:
		highest_bet = 0
		var first_to_act = (dealer_button_index + 1) % all_players.size()
		current_player_index = first_to_act
		last_aggressor_index = first_to_act
	
	_ask_current_player()

func _ask_current_player():
	"""Demande au joueur actuel de jouer"""
	if active_players.size() <= 1:
		_end_hand_early()
		return
	
	var peer_id = all_players[current_player_index]
	
	# Si ce joueur a fold, on passe au suivant
	if peer_id in folded_players:
		_next_player()
		return
	
	var to_call = highest_bet - current_bets.get(peer_id, 0)
	var can_check = (to_call == 0)
	
	print("\n→ Tour de : Joueur ", peer_id)
	print("  Pot: ", pot, "$ | À suivre: ", to_call, "$ | Peut check: ", can_check)
	
	# NOTIFIER TOUT LE MONDE
	for player_id in all_players:
		var player_node = get_node("../PlayerContainer/" + str(player_id))
		
		if player_id == peer_id:
			# C'est son tour
			player_node.notify_turn.rpc(true, to_call, can_check)
		else:
			# Pas son tour
			player_node.notify_turn.rpc(false, 0, false)

func _next_player():
	"""Passe au joueur suivant"""
	action_count += 1
	current_player_index = (current_player_index + 1) % all_players.size()
	print("DEBUG _next_player: current_index = ", current_player_index)
	print("DEBUG _next_player: peer_id = ", all_players[current_player_index])
	
	# Si on a fait le tour complet depuis le dernier relanceur
	if current_player_index == last_aggressor_index and action_count >= active_players.size():
		_end_betting_round()
	else:
		_ask_current_player()

func _end_betting_round():
	"""Termine le tour de mises et passe à la phase suivante"""
	waiting_for_player_action = false
	
	print("\n✓ Fin du tour de mises")
	
	match current_phase:
		GamePhase.PRE_FLOP:
			_deal_flop()
		GamePhase.FLOP:
			_deal_turn()
		GamePhase.TURN:
			_deal_river()
		GamePhase.RIVER:
			_showdown()

# ==============================================================================
# RÉVÉLATION DES CARTES COMMUNES
# ==============================================================================

func _deal_flop():
	"""Révèle le flop (3 cartes)"""
	current_phase = GamePhase.FLOP
	print("\n🃏 FLOP")
	
	deck.pop_back()  # Burn card
	for i in range(3):
		community_cards.append(deck.pop_back())
	
	_show_community_cards()
	await get_tree().create_timer(1.5).timeout
	_start_betting_round()

func _deal_turn():
	"""Révèle le turn (1 carte)"""
	current_phase = GamePhase.TURN
	print("\n🃏 TURN")
	
	deck.pop_back()  # Burn
	community_cards.append(deck.pop_back())
	
	_show_community_cards()
	await get_tree().create_timer(1.5).timeout
	_start_betting_round()

func _deal_river():
	"""Révèle le river (1 carte)"""
	current_phase = GamePhase.RIVER
	print("\n🃏 RIVER")
	
	deck.pop_back()  # Burn
	community_cards.append(deck.pop_back())
	
	_show_community_cards()
	await get_tree().create_timer(1.5).timeout
	_start_betting_round()

func _show_community_cards():
	"""Affiche les cartes communes dans le terminal (à améliorer visuellement plus tard)"""
	print("  Cartes: ", community_cards)
	
	# TODO: Spawn visuel des cartes sur la table
	# Pour l'instant juste print

# ==============================================================================
# ACTIONS JOUEUR (RPC)
# ==============================================================================

@rpc("any_peer", "call_local", "reliable")
func player_action(action_type: String, amount: int = 0):
	if not multiplayer.is_server():
		return
	
	var sender_id = multiplayer.get_remote_sender_id()
	var expected_id = all_players[current_player_index]
	
	# Vérification sécurité
	if sender_id != expected_id or not waiting_for_player_action:
		print("⚠ Action refusée de ", sender_id)
		return
	
	print("\n📢 Joueur ", sender_id, " : ", action_type, " (", amount, "$)")
	
	match action_type:
		"FOLD":
			_handle_fold(sender_id)
		"CHECK":
			_handle_check(sender_id)
		"CALL":
			_handle_call(sender_id)
		"BET", "RAISE":
			_handle_bet(sender_id, amount)
	
	_next_player()

func _handle_fold(peer_id: int):
	folded_players.append(peer_id)
	active_players.erase(peer_id)
	print("  → Joueur ", peer_id, " se couche")

func _handle_check(peer_id: int):
	print("  → Joueur ", peer_id, " check")

func _handle_call(peer_id: int):
	var to_call = highest_bet - current_bets.get(peer_id, 0)
	var actual_call = min(to_call, player_stacks[peer_id])
	
	player_stacks[peer_id] -= actual_call
	current_bets[peer_id] += actual_call
	pot += actual_call
	
	print("  → Joueur ", peer_id, " suit pour ", actual_call, "$")
	
	_update_player_display(peer_id)

func _handle_bet(peer_id: int, amount: int):
	var current_bet_player = current_bets.get(peer_id, 0)
	var additional_amount = min(amount, player_stacks[peer_id])
	
	player_stacks[peer_id] -= additional_amount
	current_bets[peer_id] += additional_amount
	pot += additional_amount
	
	if current_bets[peer_id] > highest_bet:
		highest_bet = current_bets[peer_id]
		last_aggressor_index = current_player_index
		print("  → Joueur ", peer_id, " relance à ", highest_bet, "$")
	else:
		print("  → Joueur ", peer_id, " mise ", additional_amount, "$")
	
	_update_player_display(peer_id)

func _update_player_display(peer_id: int):
	var player_node = get_node("../PlayerContainer/" + str(peer_id))
	player_node.update_stack.rpc(player_stacks[peer_id])
	_sync_pot_to_all()

func _sync_pot_to_all():
	for peer_id in all_players:
		var player_node = get_node("../PlayerContainer/" + str(peer_id))
		player_node.update_pot.rpc(pot)

# ==============================================================================
# FIN DE MAIN
# ==============================================================================

func _end_hand_early():
	"""Fin prématurée (tout le monde a fold sauf un)"""
	var winner_id = active_players[0]
	print("\n🏆 GAGNANT PAR FORFAIT : Joueur ", winner_id)
	
	player_stacks[winner_id] += pot
	_update_player_display(winner_id)
	
	await get_tree().create_timer(3.0).timeout
	start_new_hand()

func _showdown():
	"""Révélation des mains et détermination du gagnant"""
	current_phase = GamePhase.SHOWDOWN
	print("\n🎴 SHOWDOWN !")
	
	var best_score = -1
	var winners = []
	
	for peer_id in active_players:
		var hand = player_hands[peer_id]
		var score = HandEvaluator.evaluate(hand, community_cards)
		
		print("  Joueur ", peer_id, " : ", hand, " → Score: ", score)
		
		# Révéler les cartes à tous
		var player_node = get_node("../PlayerContainer/" + str(peer_id))
		player_node.show_hand_to_all.rpc(hand)
		
		if score > best_score:
			best_score = score
			winners = [peer_id]
		elif score == best_score:
			winners.append(peer_id)
	
	await get_tree().create_timer(3.0).timeout
	
	# Partage du pot
	var winnings = pot / winners.size()
	for winner_id in winners:
		player_stacks[winner_id] += int(winnings)
		print("\n🏆 Joueur ", winner_id, " gagne ", int(winnings), "$")
		_update_player_display(winner_id)
	
	await get_tree().create_timer(4.0).timeout
	
	# Nettoyer les visuels
	for peer_id in all_players:
		var player_node = get_node("../PlayerContainer/" + str(peer_id))
		player_node.clear_hand_visuals.rpc()
	
	start_new_hand()
