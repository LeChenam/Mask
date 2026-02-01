extends Node3D
# ============================================================================
# GAME MANAGER - MASKARD - Poker Horror avec système de masques
# ============================================================================
# À attacher au nœud Dealer dans world.tscn

const HandEvaluator = preload("res://scripts/Game/HandEvaluator.gd")
const MaskEffects = preload("res://scripts/Game/MaskEffects.gd")

# --- PHASES DE JEU MASKARD ---
enum GamePhase { 
	WAITING,
	DEALER_MASK_ANNOUNCE,  # Annonce du masque du croupier
	SHOP_PHASE,            # Phase d'achat de masques
	PRE_FLOP, 
	FLOP, 
	TURN, 
	RIVER, 
	SHOWDOWN 
}
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
const INITIAL_SMALL_BLIND = 10
const INITIAL_BIG_BLIND = 20
var current_small_blind = INITIAL_SMALL_BLIND
var current_big_blind = INITIAL_BIG_BLIND
var dealer_button_index = 0  # Position du bouton dealer

# --- MISES ---
var pot = 0
var side_pots = []         # Pour gérer les all-ins multiples (optionnel pour v1)
var current_bets = {}      # {peer_id: montant_misé_ce_TOUR}
var highest_bet = 0        # Plus grosse mise de ce tour
var min_raise = INITIAL_BIG_BLIND  # Relance minimum
var bet_multiplier = 1.0   # Modifié par le masque de l'Usurier

# --- TOUR DE PAROLE ---
var current_player_index = 0
var last_aggressor_index = 0  # Dernier à avoir relancé
var action_count = 0

# --- ÉTAT ---
var game_started = false
var waiting_for_player_action = false

# ============================================================================
# SYSTÈME MASKARD
# ============================================================================
var current_round_number = 0

# --- MASQUE DU CROUPIER ---
var dealer_current_mask: int = MaskEffects.DealerMask.NONE
var fold_disabled = false      # Masque du Geôlier
var community_hidden = false   # Masque de l'Aveugle

# --- MASQUES DES JOUEURS ---
var player_masks = {}          # {peer_id: MaskEffects.PlayerMask}
var player_last_masks = {}     # {peer_id: MaskEffects.PlayerMask} - pour éviter re-achat
var player_protection_used = {} # {peer_id: bool} - Masque Voilé utilisé

# --- CARTES MASQUÉES ---
var masked_cards = {}          # {card_id: bool} - quelles cartes sont masquées
var player_masked_cards = {}   # {peer_id: [masked_card_ids]}

# --- EFFETS ACTIFS ---
var active_pacts = []          # [{from: peer_id, to: peer_id}] - Pactes du Roi Rouge
var players_blinded = []       # [peer_id] - Joueurs aveuglés par le Roi Noir

# --- TIMER & TÉNÈBRES (Black King Table Effect) ---
var turn_timer: float = 0.0
var timer_active: bool = false
var current_turn_duration: float = 30.0  # Durée standard d'un tour
var darkness_active: bool = false        # Effet Ténèbres Absolues

# --- SHOP SYNC ---
signal shop_phase_completed
var finished_shop_players = []  # Liste des joueurs ayant fini le shop

# --- DATA JOUEURS & EFFETS (Single Use) ---
var player_names = {}          # {peer_id: "Pseudo"}
var used_hand_effects = {}     # {peer_id: [card_id]} - Cartes déjà utilisées ce tour

# ==============================================================================
# INITIALISATION
# ==============================================================================

func _ready():
	# Enregistrer le nom (Client & Serveur)
	await get_tree().create_timer(0.5).timeout # Attendre un peu que tout soit prêt
	
	if multiplayer.is_server():
		register_player_name(NetworkManager.player_name)
	else:
		register_player_name.rpc_id(1, NetworkManager.player_name)
		return

	await get_tree().create_timer(0.5).timeout
	
	# Lancer l'animation du croupier sur tous les clients
	_play_dealer_idle_animation.rpc()
	
	print("\n╔══════════════════════════════╗")
	print("║   DEALER PRÊT - POKER v1.0   ║")
	print("╚══════════════════════════════╝\n")
	
	_initialize_players()

@rpc("any_peer", "call_local", "reliable")
func _play_dealer_idle_animation():
	"""Lance l'animation idle_croupier pour le croupier"""
	print("\n=== DEBUG Croupier ===")
	
	# Le Dealer est le nœud actuel (self)
	# Le human est un enfant direct
	var human_node = get_node_or_null("human")
	if human_node:
		print("✓ Nœud human du croupier trouvé")
		print("Enfants de human:")
		for child in human_node.get_children():
			print("  - ", child.name, " (", child.get_class(), ")")
			if child is AnimationPlayer:
				print("    Animations disponibles:")
				for anim_name in child.get_animation_list():
					print("      * ", anim_name)
		
		# Chercher l'AnimationPlayer
		var animation_player = null
		for child in human_node.get_children():
			if child is AnimationPlayer:
				animation_player = child
				break
		
		if animation_player:
			print("✓ AnimationPlayer trouvé pour le croupier")
			if animation_player.has_animation("idle_croupier"):
				animation_player.play("idle_croupier")
				print("→ Animation idle_croupier lancée pour le croupier")
			else:
				print("⚠ Animation 'idle_croupier' non trouvée. Animations disponibles:", animation_player.get_animation_list())
		else:
			print("⚠ AnimationPlayer non trouvé dans human du croupier")
	else:
		print("⚠ Nœud human non trouvé pour le croupier")

@rpc("any_peer", "call_local", "reliable")
func _play_dealer_animation(anim_name: String):
	"""Joue une animation du croupier"""
	var human_node = get_node_or_null("human")
	if human_node:
		var animation_player = null
		for child in human_node.get_children():
			if child is AnimationPlayer:
				animation_player = child
				break
		
		if animation_player and animation_player.has_animation(anim_name):
			animation_player.play(anim_name)
			print("→ Animation '", anim_name, "' lancée pour le croupier")

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
		
		# Sync le nom si connu (fix host name bug)
		if player_names.has(peer_id):
			player_node.set_player_name.rpc(player_names[peer_id])
		
		print("→ Joueur ", peer_id, " ajouté (Stack: 1000)")
	
	print("✓ Table initialisée : ", all_players.size(), " joueur(s)")
	
	if can_start_game():
		print("✓ Prêt à démarrer (", all_players.size(), " joueurs)")
		_notify_all_ready()
	else:
		print("⚠ Pas assez de joueurs (", all_players.size(), "/2 min)")

func _process(delta):
	"""Gestion du Timer de tour"""
	if not multiplayer.is_server() or not timer_active:
		return
	
	turn_timer -= delta
	
	# Sync le timer avec les clients chaque seconde (arrondi)
	if int(turn_timer + delta) != int(turn_timer):
		_sync_timer_to_all()
	
	if turn_timer <= 0:
		timer_active = false
		_handle_timeout()

func _reset_timer():
	"""Réinitialise le timer pour le joueur actuel"""
	turn_timer = current_turn_duration
	timer_active = true
	_sync_timer_to_all()
	print("⏳ Timer démarré: ", current_turn_duration, "s")

func _stop_timer():
	"""Arrête le timer"""
	timer_active = false
	turn_timer = 0
	_sync_timer_to_all()

func _handle_timeout():
	"""Gère la fin du temps imparti"""
	print("⌛ Temps écoulé pour joueur ", current_player_index)
	# Si peut check, check. Sinon fold.
	if current_player_index < active_players.size():
		var current_player = active_players[current_player_index]
		
		# Auto-action
		var to_call = highest_bet - current_bets.get(current_player, 0)
		if to_call == 0:
			_execute_player_action(current_player, "CHECK", 0)
		else:
			# Vérifier si Geôlier empêche le fold
			if dealer_current_mask == MaskEffects.DealerMask.GEOLIER:
				# Si peut pas fold, call auto (si a les sous) ou all-in
				var stack = player_stacks[current_player]
				var amount = min(stack, to_call)
				_execute_player_action(current_player, "CALL", amount)
			else:
				_execute_player_action(current_player, "FOLD", 0)

func _sync_timer_to_all():
	"""Envoie le temps restant à tous les joueurs"""
	for peer_id in all_players:
		var player_node = get_node_or_null("../PlayerContainer/" + str(peer_id))
		if player_node and player_node.has_method("update_timer"):
			player_node.update_timer.rpc(int(ceil(turn_timer)))

func can_start_game() -> bool:
	return all_players.size() >= 2 and all_players.size() <= 5

func _notify_all_ready():
	"""Notifie tous les joueurs que le bouton START peut s'afficher"""
	for peer_id in all_players:
		var player_node = get_node("../PlayerContainer/" + str(peer_id))
		player_node.show_start_button.rpc()

func _play_idle_animations():
	"""Lance l'animation idle_joueur pour tous les joueurs"""
	var player_container = get_node("../PlayerContainer")
	
	for player_node in player_container.get_children():
		# Appeler le RPC sur chaque joueur pour qu'ils jouent l'animation sur tous les clients
		player_node._play_player_idle_animation.rpc()

# ==============================================================================
# DÉMARRAGE DE LA PARTIE (Appelé par le premier joueur qui clique START)
# ==============================================================================

@rpc("any_peer", "call_local", "reliable")
func register_player_name(pseudo: String):
	"""Enregistre le pseudo d'un joueur"""
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	
	player_names[sender_id] = pseudo
	print("👤 Joueur ", sender_id, " enregistré sous le nom : ", pseudo)
	
	# Sync name to UI (si le joueur existe déjà)
	var player_node = get_node_or_null("../PlayerContainer/" + str(sender_id))
	if player_node and player_node.has_method("set_player_name"):
		player_node.set_player_name.rpc(pseudo)

func _get_player_name(peer_id: int) -> String:
	"""Retourne le pseudo du joueur ou 'Joueur ID' par défaut"""
	return player_names.get(peer_id, "Joueur " + str(peer_id))

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
	# Lancer l'animation idle_joueur pour tous les joueurs
	_play_idle_animations()
		# Cacher le bouton START chez tout le monde
	for peer_id in all_players:
		var player_node = get_node("../PlayerContainer/" + str(peer_id))
		player_node.hide_start_button.rpc()
	
	_broadcast_sound("scary_laugh", 0.85)
	start_new_hand()

# ==============================================================================
# NOUVELLE MAIN
# ==============================================================================

func start_new_hand():
	"""Démarre une nouvelle main de poker MASKARD"""
	if not multiplayer.is_server():
		return
	
	current_round_number += 1
	
	_broadcast_sound("shuffle", 0.75)
	await get_tree().create_timer(0.5).timeout
	_broadcast_sound("scary_letsplay", 0.9)
	
	# Reset
	current_phase = GamePhase.PRE_FLOP
	pot = 0
	community_cards.clear()
	player_hands.clear()
	folded_players.clear()
	active_players = all_players.duplicate()
	masked_cards.clear()
	player_masked_cards.clear()
	active_pacts.clear()
	players_blinded.clear()
	used_hand_effects.clear()  # Reset des effets utilisés
	
	# Reset des effets de masques de croupier
	bet_multiplier = 1.0
	fold_disabled = false
	community_hidden = false
	
	# Reset protection Voilé pour chaque joueur
	for peer_id in all_players:
		player_protection_used[peer_id] = false
	
	# Création du deck
	deck = range(52)
	deck.shuffle()
	
	# Avancer le bouton dealer
	dealer_button_index = (dealer_button_index + 1) % all_players.size()
	
	# ======= PHASES MASKARD =======
	
	# Phase 1: Annonce du masque du croupier (sauf manche 1)
	if current_round_number > 1:
		await _announce_dealer_mask()
		await get_tree().create_timer(2.0).timeout
		
		# Phase 2: Shop des masques
		await _start_shop_phase()
		# Attendre que tous les joueurs aient fini (achat ou skip)
		print("⏳ Attente fin shop...")
		await self.shop_phase_completed
		print("✓ Shop terminé")
	else:
		print("\n🎭 Manche 1 - Pas de masques")
		_announce_to_all("🎭 Round 1 - No masks yet...")
	
	# Phase 3: Appliquer les effets du masque du croupier
	if dealer_current_mask != MaskEffects.DealerMask.NONE:
		_apply_dealer_mask_effects()
	
	# Phase 4: Distribution des cartes
	current_phase = GamePhase.PRE_FLOP
	_deal_hole_cards()
	
	# Poster les blinds (avec multiplicateur si Usurier)
	_post_blinds()
	
	# Démarrer le tour de parole PRE-FLOP
	await get_tree().create_timer(1.0).timeout
	_start_betting_round()

# ============================================================================
# PHASES MASKARD - Annonce Croupier & Shop
# ============================================================================

func _announce_dealer_mask():
	"""Le croupier choisit et annonce son masque pour cette manche"""
	current_phase = GamePhase.DEALER_MASK_ANNOUNCE
	
	# Sélectionner un masque aléatoire (25% chaque ou aucun)
	dealer_current_mask = MaskEffects.select_random_dealer_mask()
	
	if dealer_current_mask == MaskEffects.DealerMask.NONE:
		print("\n👹 CROUPIER: Je ne porte pas de masque cette manche...")
		_announce_to_all("👹 The Dealer wears... nothing.")
		await get_tree().create_timer(1.0).timeout
		_announce_to_all("'Play fairly... for now.'")
	else:
		var mask_info = MaskEffects.get_dealer_mask_info(dealer_current_mask)
		print("\n👹 CROUPIER: J'arbore le ", mask_info.name)
		print("   Effet: ", mask_info.description)
		
		# Annoncer à tous les joueurs
		_announce_to_all("👹 The Dealer wears: " + mask_info.name_en)
		await get_tree().create_timer(1.0).timeout
		_announce_to_all(mask_info.announcement)

func _start_shop_phase():
	"""Ouvre le shop de masques pour tous les joueurs"""
	current_phase = GamePhase.SHOP_PHASE
	print("\n🛍️ SHOP DES MASQUES OUVERT")
	
	_announce_to_all("🛍️ Mask Shop is open! (100 chips)")
	
	# Envoyer les infos du shop à chaque joueur
	for peer_id in all_players:
		var last_mask = player_last_masks.get(peer_id, MaskEffects.PlayerMask.NONE)
		var available_masks = MaskEffects.get_available_shop_masks(last_mask)
		var player_chips = player_stacks[peer_id]
		
		var player_node = get_node("../PlayerContainer/" + str(peer_id))

		player_node.show_shop_ui.rpc_id(peer_id, available_masks, player_chips)
		print("  → Joueur ", peer_id, " peut acheter: ", available_masks)

	# Reset liste synchronisation
	finished_shop_players.clear()

@rpc("any_peer", "call_local", "reliable")
func player_finished_shop_phase():
	"""Un joueur signale qu'il a fini ses achats (ou skip)"""
	if current_phase != GamePhase.SHOP_PHASE: return
	
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	
	if sender_id not in finished_shop_players:
		finished_shop_players.append(sender_id)
		print("🛒 Shop fini pour joueur ", sender_id, " (", finished_shop_players.size(), "/", active_players.size(), ")")
		
		# Vérifier si tous les joueurs actifs ont fini
		if finished_shop_players.size() >= active_players.size():
			shop_phase_completed.emit()

func _apply_dealer_mask_effects():
	"""Applique les effets globaux du masque du croupier"""
	print("\n👹 Application des effets du croupier...")
	
	match dealer_current_mask:
		MaskEffects.DealerMask.USURIER:
			bet_multiplier = 2.0
			print("   💰 Toutes les mises sont DOUBLÉES!")
			_announce_to_all("💰 All bets are DOUBLED!")
			
		MaskEffects.DealerMask.GEOLIER:
			fold_disabled = true
			print("   ⛓️ Impossible de se coucher!")
			_announce_to_all("⛓️ FOLDING IS FORBIDDEN!")
			
		MaskEffects.DealerMask.AVEUGLE:
			community_hidden = true
			print("   👁️ Cartes communes cachées!")
			_announce_to_all("👁️ Community cards are HIDDEN!")

# ============================================================================
# EFFETS DES CARTES MASQUÉES (12 effets)
# ============================================================================

func _apply_table_effect(card_id: int):
	"""Applique l'effet de TABLE d'une carte masquée qui apparaît sur le board"""
	var info = MaskEffects.get_face_card_info(card_id)
	if info.is_empty():
		return
	
	var is_red = info.color == MaskEffects.HeadCardColor.RED
	var rank = info.rank  # 0=Jack, 1=Queen, 2=King
	
	print("\n🎭 EFFET DE TABLE: ", info.name)
	_announce_to_all("🎭 TABLE EFFECT: " + info.name)
	await get_tree().create_timer(1.0).timeout
	
	if is_red:
		match rank:
			MaskEffects.HeadCardRank.JACK:
				await _table_effect_red_jack()  # L'Observateur
			MaskEffects.HeadCardRank.QUEEN:
				await _table_effect_red_queen()  # La Parasyte
			MaskEffects.HeadCardRank.KING:
				await _table_effect_red_king()  # Le Banquier Corrompu
	else:
		match rank:
			MaskEffects.HeadCardRank.JACK:
				await _table_effect_black_jack()  # Le Trickster
			MaskEffects.HeadCardRank.QUEEN:
				await _table_effect_black_queen()  # L'Inquisitrice
			MaskEffects.HeadCardRank.KING:
				await _table_effect_black_king()  # Le Néant

# --- EFFETS DE TABLE ROUGES ---

func _table_effect_red_jack():
	"""Valet Rouge - Chaque joueur doit montrer une carte au choix"""
	print("   👁️ Révélation partielle - Chaque joueur montre une carte")
	_announce_to_all("👁️ 'I see you...' - Everyone reveals one card!")
	
	# Pour l'instant, révéler automatiquement la première carte de chaque joueur
	for peer_id in active_players:
		if peer_id in player_hands:
			var cards = player_hands[peer_id]
			if cards.size() > 0:
				# Montrer la première carte à tout le monde
				_reveal_player_card_to_all.rpc(peer_id, cards[0])
	
	await get_tree().create_timer(2.0).timeout

func _table_effect_red_queen():
	"""Dame Rouge - Le plus riche donne 50 jetons au plus pauvre"""
	print("   🩸 Transfusion - Le riche donne au pauvre")
	
	var richest_id = -1
	var richest_amount = -1
	var poorest_id = -1
	var poorest_amount = 999999
	
	for peer_id in active_players:
		var stack = player_stacks[peer_id]
		if stack > richest_amount:
			richest_amount = stack
			richest_id = peer_id
		if stack < poorest_amount:
			poorest_amount = stack
			poorest_id = peer_id
	
	if richest_id != -1 and poorest_id != -1 and richest_id != poorest_id:
		var transfer = min(MaskEffects.STEAL_AMOUNT, player_stacks[richest_id])
		player_stacks[richest_id] -= transfer
		player_stacks[poorest_id] += transfer
		
		_update_player_display(richest_id)
		_update_player_display(poorest_id)
		
		_announce_to_all("🩸 Transfusion: Player " + str(richest_id) + " gives " + str(transfer) + "$ to Player " + str(poorest_id))
	
	await get_tree().create_timer(1.5).timeout

func _table_effect_red_king():
	"""Roi Rouge - Pot empoisonné - Chaque joueur mise 50% de plus"""
	print("   🔥 Pot empoisonné - Chaque joueur mise 50% de plus")
	_announce_to_all("🔥 'Poisoned pot!' - Everyone bets 50% more!")
	
	for peer_id in active_players:
		var current_bet = current_bets.get(peer_id, 0)
		var extra_bet = int(current_bet * 0.5)
		if extra_bet > 0 and player_stacks[peer_id] >= extra_bet:
			player_stacks[peer_id] -= extra_bet
			current_bets[peer_id] = current_bet + extra_bet
			pot += extra_bet
			_update_player_display(peer_id)
			print("   → Joueur ", peer_id, " paie ", extra_bet, "$ de plus")
	
	_sync_pot_to_all()
	await get_tree().create_timer(1.5).timeout

# --- EFFETS DE TABLE NOIRS ---

func _table_effect_black_jack():
	"""Valet Noir - Chaos mineur - Une carte de la table est remplacée"""
	print("   🌀 Chaos mineur - Une carte est remplacée")
	_announce_to_all("🌀 'Chaos!' - A table card is replaced!")
	
	if community_cards.size() > 0 and deck.size() > 0:
		# Choisir une carte au hasard à remplacer
		var replace_index = randi() % community_cards.size()
		var old_card = community_cards[replace_index]
		var new_card = deck.pop_back()
		
		community_cards[replace_index] = new_card
		
		# Vérifier si la nouvelle carte est une tête masquée
		if MaskEffects.is_face_card(new_card) and MaskEffects.should_card_be_masked():
			masked_cards[new_card] = true
			print("   🎭 La nouvelle carte est aussi masquée!")
		
		_announce_to_all("🌀 Card " + _card_to_string(old_card) + " replaced by " + _card_to_string(new_card))
		
		# Re-afficher les cartes
		await _show_community_cards()
	
	await get_tree().create_timer(1.5).timeout

func _table_effect_black_queen():
	"""Dame Noire - Tribunal - Impossible de fold, mise minimum 50"""
	print("   ⚖️ Tribunal - Impossible de fold, mise minimum 50")
	_announce_to_all("⚖️ 'TRIBUNAL!' - No folding, 50$ minimum per action!")
	
	fold_disabled = true  # Comme le Geôlier
	min_raise = max(min_raise, 50)  # Mise minimum augmentée
	
	await get_tree().create_timer(1.5).timeout

func _table_effect_black_king():
	"""Roi Noir - Ténèbres absolues - Écrans sombres, timer réduit"""
	print("   🌑 Ténèbres absolues!")
	_announce_to_all("🌑 'Absolute darkness...' - Timer -20s!")
	
	# Activer l'état
	darkness_active = true
	current_turn_duration = 10.0  # Réduire le temps de tour (30s -> 10s)
	
	# Appliquer l'effet de ténèbres à tous les joueurs
	for peer_id in active_players:
		var player_node = get_node("../PlayerContainer/" + str(peer_id))
		if player_node.has_method("apply_darkness_effect"):
			player_node.apply_darkness_effect.rpc_id(peer_id, true)
	
	await get_tree().create_timer(1.5).timeout

@rpc("authority", "call_local", "reliable")
func _reveal_player_card_to_all(player_id: int, card_id: int):
	"""Révèle une carte d'un joueur à tout le monde"""
	print("👁️ Joueur ", player_id, " montre: ", _card_to_string(card_id))
	# Visual feedback GLOBAL
	for peer_id in active_players:
		var player_node = get_node("../PlayerContainer/" + str(peer_id))
		# On envoie l'info uniquement au client concerné sur SON noeud joueur (qui a l'UI)
		if player_node:
			if player_node.has_method("show_revealed_card_ui"):
				player_node.show_revealed_card_ui.rpc_id(peer_id, player_id, card_id)
			if player_node.has_method("trigger_horror_effect"):
				player_node.trigger_horror_effect.rpc_id(peer_id, "jack_red_eye")

# ============================================================================
# EFFETS DEPUIS LA MAIN (activés par clic du joueur)
# ============================================================================

@rpc("any_peer", "call_local", "reliable")
func request_activate_mask_effect(card_id: int):
	"""Un joueur demande à activer l'effet de sa carte masquée (ancien RPC sans cible)"""
	request_activate_mask_effect_targeted(card_id, -1)

@rpc("any_peer", "call_local", "reliable")
func request_activate_mask_effect_targeted(card_id: int, target_id: int):
	"""Un joueur demande à activer l'effet de sa carte masquée avec cible"""
	if not multiplayer.is_server():
		return
	
	var activator_id = multiplayer.get_remote_sender_id()
	
	# Vérifier que le joueur possède cette carte
	var player_cards = player_hands.get(activator_id, [])
	if card_id not in player_cards:
		print("⚠ Joueur ", activator_id, " n'a pas la carte ", card_id)
		_send_effect_result(activator_id, "⚠ Carte invalide!")
		return
	
	# Vérifier que la carte est masquée
	if not masked_cards.get(card_id, false):
		print("⚠ Carte ", card_id, " n'est pas masquée")
		_send_effect_result(activator_id, "⚠ Cette carte n'est pas masquée!")
		return
	
	# VÉRIFICATION TOUR DE JEU
	# On doit être en phase de pari (FLOP, TURN, RIVER, ou PREFLOP si on veut)
	var allowed_phases = [GamePhase.PRE_FLOP, GamePhase.FLOP, GamePhase.TURN, GamePhase.RIVER]
	if current_phase not in allowed_phases:
		_send_effect_result(activator_id, "⚠ Attendez une phase de pari !")
		return

	# Vérifier si c'est le tour du joueur (Sauf si Masque Affamé ?)
	# Note: active_players contient les joueurs non couchés.
	var current_actor_id = -1
	if active_players.size() > 0 and current_player_index < active_players.size():
		current_actor_id = active_players[current_player_index]
	
	if activator_id != current_actor_id:
		_send_effect_result(activator_id, "⚠ Ce n'est pas votre tour !")
		return

	# Vérifier protection
	if _check_voile_protection(activator_id, activator_id): # Auto-protection? Non, Voile protege contre CIBLAGE externe
		pass # Le Voile ne bloque pas ses propres effets
	
	# VÉRIFICATION USAGE UNIQUE
	if not used_hand_effects.has(activator_id):
		used_hand_effects[activator_id] = []
		
	if card_id in used_hand_effects[activator_id]:
		print("⚠ Effet déjà utilisé pour cette carte !")
		_send_effect_result(activator_id, "⚠ Already used this effect!")
		return
		
	# Marquer comme utilisé
	used_hand_effects[activator_id].append(card_id)
	
	# Marquer côté client
	var player_node = get_node("../PlayerContainer/" + str(activator_id))
	if player_node.has_method("mark_card_used"):
		player_node.mark_card_used.rpc(card_id)
	
	var info = MaskEffects.get_face_card_info(card_id)
	if info.is_empty():
		return
	
	print("\n🎭 ACTIVATION EFFET MAIN: ", info.name, " par joueur ", activator_id, " cible: ", target_id)
	_announce_to_all("🎭 " + info.name + " activated!")
	
	var is_red = info.color == MaskEffects.HeadCardColor.RED
	var rank = info.rank
	
	if is_red:
		match rank:
			MaskEffects.HeadCardRank.JACK:
				await _hand_effect_red_jack(activator_id, target_id)
			MaskEffects.HeadCardRank.QUEEN:
				await _hand_effect_red_queen(activator_id, target_id)
			MaskEffects.HeadCardRank.KING:
				await _hand_effect_red_king(activator_id, target_id)
	else:
		match rank:
			MaskEffects.HeadCardRank.JACK:
				await _hand_effect_black_jack(activator_id, target_id)
			MaskEffects.HeadCardRank.QUEEN:
				await _hand_effect_black_queen(activator_id, target_id)
			MaskEffects.HeadCardRank.KING:
				await _hand_effect_black_king(activator_id, target_id)

func _send_effect_result(player_id: int, message: String):
	"""Envoie le résultat d'un effet au joueur"""
	var player_node = get_node_or_null("../PlayerContainer/" + str(player_id))
	if player_node:
		player_node.show_effect_result.rpc_id(player_id, message)

# --- EFFETS DE MAIN ROUGES ---

func _hand_effect_red_jack(activator_id: int, target_id: int = -1):
	"""Valet Rouge - Inspecter une carte d'un joueur"""
	print("   👁️ L'Observateur - Inspection d'une carte")
	
	# Si pas de cible spécifiée, prendre au hasard
	if target_id == -1:
		var targets = active_players.filter(func(id): return id != activator_id)
		if targets.size() > 0:
			target_id = targets.pick_random()
	
	if target_id == -1 or target_id == activator_id:
		_send_effect_result(activator_id, "Aucune cible valide!")
		return
	
	# Vérifier protection Voilé
	if _check_voile_protection(target_id, activator_id):
		_send_effect_result(activator_id, "Cible protégée par le Voile!")
		return
	
	var target_cards = player_hands.get(target_id, [])
	if target_cards.size() > 0:
		var revealed_card = target_cards.pick_random()
		var card_str = _card_to_string(revealed_card)
		
		# Envoyer la carte révélée uniquement à l'activateur
		# _send_effect_result(activator_id, "👁️ Joueur " + str(target_id) + " a: " + card_str)
		
		var activator_node = get_node("../PlayerContainer/" + str(activator_id))
		if activator_node:
			activator_node.show_revealed_card_ui.rpc_id(activator_id, target_id, revealed_card)
			activator_node.trigger_horror_effect.rpc_id(activator_id, "jack_red_eye")
			
		_announce_to_all("👁️ " + _get_player_name(activator_id) + " a inspecté une carte de " + _get_player_name(target_id))

func _hand_effect_red_queen(activator_id: int, target_id: int = -1):
	"""Dame Rouge - Voler 50 jetons à un joueur"""
	print("   🩸 La Parasyte - Vol de jetons")
	
	# Si pas de cible spécifiée, prendre au hasard
	if target_id == -1:
		var targets = active_players.filter(func(id): return id != activator_id)
		if targets.size() > 0:
			target_id = targets.pick_random()
	
	if target_id == -1 or target_id == activator_id:
		_send_effect_result(activator_id, "Aucune cible valide!")
		return
	
	# Vérifier protection Voilé
	if _check_voile_protection(target_id, activator_id):
		_send_effect_result(activator_id, "Cible protégée par le Voile!")
		return
	
	var steal_amount = min(MaskEffects.STEAL_AMOUNT, player_stacks[target_id])
	player_stacks[target_id] -= steal_amount
	player_stacks[activator_id] += steal_amount
	
	_update_player_display(target_id)
	_update_player_display(activator_id)
	
	var msg = "🩸 Vous avez volé " + str(steal_amount) + "$ à " + _get_player_name(target_id)
	_send_effect_result(activator_id, msg)
	_announce_to_all("🩸 " + _get_player_name(activator_id) + " vole " + str(steal_amount) + "$ à " + _get_player_name(target_id))

func _hand_effect_red_king(activator_id: int, target_id: int = -1):
	"""Roi Rouge - Forcer un pacte de partage des gains"""
	print("   🤝 Le Banquier Corrompu - Pacte forcé")
	
	# Si pas de cible spécifiée, prendre au hasard
	if target_id == -1:
		var targets = active_players.filter(func(id): return id != activator_id)
		if targets.size() > 0:
			target_id = targets.pick_random()
	
	if target_id == -1 or target_id == activator_id:
		_send_effect_result(activator_id, "Aucune cible valide!")
		return
	
	# Vérifier protection Voilé
	if _check_voile_protection(target_id, activator_id):
		_send_effect_result(activator_id, "Cible protégée par le Voile!")
		return
	
	active_pacts.append({"from": activator_id, "to": target_id})
	
	var msg = "🤝 Pacte forcé avec " + _get_player_name(target_id) + " - Gains partagés!"
	_send_effect_result(activator_id, msg)
	_announce_to_all("🤝 PACTE: " + _get_player_name(activator_id) + " et " + _get_player_name(target_id) + " partagent les gains!")

# --- EFFETS DE MAIN NOIRS ---

func _hand_effect_black_jack(activator_id: int, card_to_swap_id: int = -1):
	"""Valet Noir - Échanger une carte (choisie ou random) avec le deck"""
	print("   🌀 Le Trickster - Échange de carte")
	
	if deck.size() > 0:
		var player_cards = player_hands.get(activator_id, [])
		if player_cards.size() > 0:
			# Trouver l'index de la carte à échanger
			var swap_index = 0
			if card_to_swap_id != -1:
				var found_index = player_cards.find(card_to_swap_id)
				if found_index != -1:
					swap_index = found_index
			
			# Échanger la carte choisie
			var old_card = player_cards[swap_index]
			var new_card = deck.pop_back()
			
			player_hands[activator_id][swap_index] = new_card
			deck.append(old_card)
			deck.shuffle()
			
			# Envoyer les nouvelles cartes au joueur
			var player_node = get_node("../PlayerContainer/" + str(activator_id))
			var new_cards = player_hands[activator_id]
			var new_masked = [masked_cards.get(new_cards[0], false), masked_cards.get(new_cards[1], false)]
			player_node.receive_cards_masked.rpc_id(activator_id, new_cards, new_masked)
			
			_send_effect_result(activator_id, "🌀 Carte échangée! Nouvelle carte: " + _card_to_string(new_card))
			_announce_to_all("🌀 " + _get_player_name(activator_id) + " a échangé une carte!")
	else:
		_send_effect_result(activator_id, "❌ Le deck est vide!")

func _hand_effect_black_queen(activator_id: int, target_id: int = -1):
	"""Dame Noire - Forcer un joueur à révéler sa carte la plus haute"""
	print("   ⚖️ L'Inquisitrice - Révélation forcée")
	
	# Si pas de cible spécifiée, prendre au hasard
	if target_id == -1:
		var targets = active_players.filter(func(id): return id != activator_id)
		if targets.size() > 0:
			target_id = targets.pick_random()
	
	if target_id == -1 or target_id == activator_id:
		_send_effect_result(activator_id, "Aucune cible valide!")
		return
	
	# Vérifier protection Voilé
	if _check_voile_protection(target_id, activator_id):
		_send_effect_result(activator_id, "Cible protégée par le Voile!")
		return
	
	var target_cards = player_hands.get(target_id, [])
	if target_cards.size() > 0:
		# Trouver la carte la plus haute
		var highest_card = target_cards[0]
		for card in target_cards:
			if (card % 13) > (highest_card % 13):
				highest_card = card
		
		var card_str = _card_to_string(highest_card)
		_send_effect_result(activator_id, "⚖️ " + _get_player_name(target_id) + " a comme carte haute: " + card_str)
		_announce_to_all("⚖️ " + _get_player_name(target_id) + " révèle sa carte haute: " + card_str)

func _hand_effect_black_king(activator_id: int, target_id: int = -1):
	"""Roi Noir - Aveugler un joueur (ne voit plus les cartes communes)"""
	print("   🌑 Le Néant - Aveuglement")
	
	# Si pas de cible spécifiée, prendre au hasard
	if target_id == -1:
		var targets = active_players.filter(func(id): return id != activator_id)
		if targets.size() > 0:
			target_id = targets.pick_random()
	
	if target_id == -1 or target_id == activator_id:
		_send_effect_result(activator_id, "Aucune cible valide!")
		return
	
	# Vérifier protection Voilé
	if _check_voile_protection(target_id, activator_id):
		_send_effect_result(activator_id, "Cible protégée par le Voile!")
		return
	
	players_blinded.append(target_id)
	
	var player_node = get_node("../PlayerContainer/" + str(target_id))
	if player_node.has_method("set_blinded"):
		player_node.set_blinded.rpc_id(target_id, true)
	
	_send_effect_result(activator_id, "🌑 " + _get_player_name(target_id) + " est aveuglé!")
	_announce_to_all("🌑 " + _get_player_name(target_id) + " a été AVEUGLÉ!")

func _check_voile_protection(target_id: int, attacker_id: int) -> bool:
	"""Vérifie si la cible a le Masque Voilé actif"""
	var mask = player_masks.get(target_id, MaskEffects.PlayerMask.NONE)
	var already_used = player_protection_used.get(target_id, false)
	
	if mask == MaskEffects.PlayerMask.VOILE and not already_used:
		# Le Voile protège du PREMIER effet de tête ciblé
		player_protection_used[target_id] = true # Marquer comme utilisé
		_announce_to_all("🛡️ Le Masque Voilé de " + _get_player_name(target_id) + " bloque l'effet!")
		print("   🛡️ Le Masque Voilé protège le joueur ", target_id)
		return true
	
	return false

@rpc("any_peer", "call_local", "reliable")
func request_buy_mask(mask_type: int):
	"""Un joueur demande à acheter un masque"""
	if not multiplayer.is_server():
		return
	
	var buyer_id = multiplayer.get_remote_sender_id()
	var cost = MaskEffects.MASK_SHOP_COST
	
	# Vérifications
	if player_stacks[buyer_id] < cost:
		print("⚠ Joueur ", buyer_id, " n'a pas assez de jetons")
		return
	
	var last_mask = player_last_masks.get(buyer_id, MaskEffects.PlayerMask.NONE)
	if mask_type == last_mask:
		print("⚠ Joueur ", buyer_id, " ne peut pas racheter le même masque")
		return
	
	# Achat réussi
	player_stacks[buyer_id] -= cost
	player_masks[buyer_id] = mask_type
	player_last_masks[buyer_id] = mask_type
	
	var mask_info = MaskEffects.get_player_mask_info(mask_type)
	print("🎭 Joueur ", buyer_id, " achète: ", mask_info.name)
	
	# Sync UI
	var player_node = get_node("../PlayerContainer/" + str(buyer_id))
	player_node.update_stack.rpc(player_stacks[buyer_id])
	
	# Annoncer à tous (pour la stratégie)
	_announce_to_all("🎭 Player " + str(buyer_id) + " wears: " + mask_info.name_en)

func _deal_hole_cards():
	"""Distribue 2 cartes à chaque joueur avec probabilité de masques"""
	print("\n📇 Distribution des cartes...")
	
	# Jouer l'animation de distribution du croupier sur tous les clients
	_play_dealer_animation.rpc("distribution")
	
	for peer_id in active_players:
		var card1 = deck.pop_back()
		var card2 = deck.pop_back()
		var cards = [card1, card2]
		var cards_masked = [false, false]
		var player_has_masked_cards = []
		
		# Vérifier le bonus du Masque du Corbeau
		var has_corbeau = player_masks.get(peer_id, MaskEffects.PlayerMask.NONE) == MaskEffects.PlayerMask.CORBEAU
		
		# Pour chaque carte, vérifier si c'est une tête et si elle devient masquée
		for i in range(2):
			var card = cards[i]
			if MaskEffects.is_face_card(card):
				# Probabilité de masque: 33% (+ bonus Corbeau = 30% => 63%)
				var mask_chance = MaskEffects.MASK_PROBABILITY
				if has_corbeau:
					mask_chance += 0.30  # Bonus Corbeau
				
				if randf() < mask_chance:
					cards_masked[i] = true
					masked_cards[card] = true
					player_has_masked_cards.append(card)
					print("  🎭 Carte masquée pour joueur ", peer_id, ": ", _card_to_string(card))
		
		player_hands[peer_id] = cards
		player_masked_cards[peer_id] = player_has_masked_cards
		
		# Envoi sécurisé des cartes avec info de masque
		var player_node = get_node("../PlayerContainer/" + str(peer_id))
		player_node.receive_cards_masked.rpc_id(peer_id, cards, cards_masked)
		
		print("  → Joueur ", peer_id, " reçoit 2 cartes")

func _card_to_string(card_id: int) -> String:
	"""Convertit un ID de carte en texte lisible"""
	var suits = ["♠", "♥", "♦", "♣"]
	var ranks = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "V", "D", "R", "A"]
	var rank = card_id % 13
	var suit = int(float(card_id) / 13)
	return ranks[rank] + suits[suit]

func _post_blinds():
	"""Fait payer les blinds (small + big) avec multiplicateur du croupier"""
	var sb_index = (dealer_button_index + 1) % all_players.size()
	var bb_index = (dealer_button_index + 2) % all_players.size()
	
	var sb_id = all_players[sb_index]
	var bb_id = all_players[bb_index]
	
	# Appliquer le multiplicateur (Masque de l'Usurier = x2)
	var sb_amount = int(current_small_blind * bet_multiplier)
	var bb_amount = int(current_big_blind * bet_multiplier)
	
	# Small Blind
	_force_bet(sb_id, sb_amount)
	print("💵 Small Blind (", sb_amount, "$) → Joueur ", sb_id)
	
	# Big Blind
	_force_bet(bb_id, bb_amount)
	print("💵 Big Blind (", bb_amount, "$) → Joueur ", bb_id)
	
	highest_bet = bb_amount
	last_aggressor_index = bb_index
	min_raise = bb_amount

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
		
	# Démarrer le timer pour ce joueur
	_reset_timer()
	
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
	_stop_timer()
	
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
	"""Révèle le flop (3 cartes) avec possibilité de masques"""
	current_phase = GamePhase.FLOP
	print("\n🃏 FLOP")
	
	# Jouer l'animation de distribution du croupier sur tous les clients
	_play_dealer_animation.rpc("distribution")
	
	deck.pop_back()  # Burn card
	var new_cards = []
	for i in range(3):
		var card = deck.pop_back()
		community_cards.append(card)
		new_cards.append(card)
		
		# Vérifier si la carte devient masquée (33% si tête)
		if MaskEffects.is_face_card(card) and MaskEffects.should_card_be_masked():
			masked_cards[card] = true
			print("  🎭 Carte TABLE masquée: ", _card_to_string(card))
	
	await _show_community_cards()

	
	# Appliquer les effets de table des cartes masquées (Séquentiel)
	await _process_table_effects_sequential(new_cards)
	
	await get_tree().create_timer(1.0).timeout
	_start_betting_round()

func _deal_turn():
	"""Révèle le turn (1 carte) avec possibilité de masque"""
	current_phase = GamePhase.TURN
	print("\n🃏 TURN")
	
	# Jouer l'animation de distribution du croupier sur tous les clients
	_play_dealer_animation.rpc("distribution")
	
	deck.pop_back()  # Burn
	var card = deck.pop_back()
	community_cards.append(card)
	
	# Vérifier si la carte devient masquée
	if MaskEffects.is_face_card(card) and MaskEffects.should_card_be_masked():
		masked_cards[card] = true
		print("  🎭 Carte TABLE masquée: ", _card_to_string(card))
	
	await _show_community_cards()
	
	# Appliquer l'effet de table si masquée (Séquentiel)
	await _process_table_effects_sequential([card])
	
	await get_tree().create_timer(1.0).timeout
	_start_betting_round()

func _deal_river():
	"""Révèle le river (1 carte) avec possibilité de masque"""
	current_phase = GamePhase.RIVER
	print("\n🃏 RIVER")
	
	# Jouer l'animation de distribution du croupier sur tous les clients
	_play_dealer_animation.rpc("distribution")
	
	deck.pop_back()  # Burn
	var card = deck.pop_back()
	community_cards.append(card)
	
	# Vérifier si la carte devient masquée
	if MaskEffects.is_face_card(card) and MaskEffects.should_card_be_masked():
		masked_cards[card] = true
		print("  🎭 Carte TABLE masquée: ", _card_to_string(card))
	
	await _show_community_cards()
	
	# Appliquer l'effet de table si masquée
	await _process_table_effects_sequential([card])
	
	await get_tree().create_timer(1.0).timeout
	_start_betting_round()

func _process_table_effects_sequential(cards: Array):
	"""Traite les effets de table un par un avec délai"""
	for card in cards:
		if masked_cards.get(card, false):
			var info = MaskEffects.get_face_card_info(card)
			if not info.is_empty():
				_announce_to_all("🎭 Activation effet : " + info.name)
				# await get_tree().create_timer(5.0).timeout
				
				await _apply_table_effect(card)
				
				# Petite pause après l'effet
				await get_tree().create_timer(2.0).timeout

func _show_community_cards():
	"""Affiche les cartes communes sur la table (avec masques)"""
	print("  Cartes: ", community_cards)
	
	# Nettoyer les anciennes cartes
	var card_container = get_node("../CardContainer")
	for child in card_container.get_children():
		child.queue_free()
	
	# Attendre un frame pour que le nettoyage soit effectif
	await get_tree().process_frame
	
	# Spawner les nouvelles cartes avec info de masque
	for i in range(community_cards.size()):
		var card_val = community_cards[i]
		var is_masked = masked_cards.get(card_val, false)
		_spawn_table_card_masked.rpc(card_val, i, is_masked)

@rpc("authority", "call_local", "reliable")
func _spawn_table_card_masked(card_val: int, index: int, is_masked: bool):
	"""Spawn une carte sur la table avec support masque"""
	var card_container = get_node("../CardContainer")
	var card = preload("res://scenes/card.tscn").instantiate()
	card_container.add_child(card)
	
	# Appliquer la texture (avec masque si applicable)
	if card.has_method("set_card_visuals"):
		card.set_card_visuals(card_val, is_masked)
	
	# Configurer comme carte de table
	if card.has_method("set_as_table_card"):
		card.set_as_table_card()
	
	# Révéler la carte (sauf si Masque de l'Aveugle actif)
	if not community_hidden and card.has_method("reveal"):
		card.reveal()
	
	# Position sur la table (centré, espacé horizontalement)
	var card_width = 0.7 * 0.25
	var spacing = card_width + 0.05
	var start_x = -spacing * 2
	
	card.position = Vector3(start_x + index * spacing, 0, 0)
	card.rotation_degrees = Vector3(-90, 0, 0)
	card.scale = Vector3(0.25, 0.25, 0.25)
	
	AudioManager.play("card_slide", true, 0.8)
	
	print("🃏 Carte table spawned: ", card_val, " index: ", index, " pos: ", card.position)
	if is_masked:
		print("🎭 Carte TABLE masquée spawned: ", card_val)
	else:
		print("🃏 Carte table spawned: ", card_val)

# Garder l'ancienne fonction pour compatibilité
@rpc("authority", "call_local", "reliable")
func _spawn_table_card(card_val: int, index: int):
	_spawn_table_card_masked(card_val, index, false)

# ==============================================================================
# ACTIONS JOUEUR (RPC)
# ==============================================================================

@rpc("any_peer", "call_local", "reliable")
func player_action(action_type: String, amount: int = 0):
	if not multiplayer.is_server():
		return
	
	var sender_id = multiplayer.get_remote_sender_id()
	# Si appel local (client qui héberge), get_remote_sender_id() retourne 0 ou 1
	if sender_id == 0:
		sender_id = 1
		
	var expected_id = all_players[current_player_index]
	
	# Vérification sécurité
	if sender_id != expected_id or not waiting_for_player_action:
		print("⚠ Action refusée de ", sender_id)
		return
	
	_execute_player_action(sender_id, action_type, amount)

func _execute_player_action(player_id: int, action_type: String, amount: int):
	"""Exécute l'action d'un joueur après validation"""
	print("\n📢 Joueur ", player_id, " : ", action_type, " (", amount, "$)")
	
	# MASQUE DU GEÔLIER: Impossible de se coucher!
	if action_type == "FOLD" and fold_disabled:
		print("⛓️ INTERDIT DE SE COUCHER! (Masque du Geôlier)")
		_announce_to_all("⛓️ " + str(player_id) + " tried to fold but NOBODY LEAVES!")
		# Forcer un call à la place
		action_type = "CALL"
		# Recalculer le montant du call si nécessaire ou laisser tel quel
		# Ici on assume que le joueur doit payer le call
		var to_call = highest_bet - current_bets.get(player_id, 0)
		amount = min(player_stacks[player_id], to_call)
	
	match action_type:
		"FOLD":
			_handle_fold(player_id)
		"CHECK":
			_handle_check(player_id)
		"CALL":
			_handle_call(player_id)
		"BET", "RAISE":
			_handle_bet(player_id, amount)
	
	_next_player()

func _handle_fold(peer_id: int):
	"""Gère le fold d'un joueur, avec support Masque Affamé"""
	folded_players.append(peer_id)
	active_players.erase(peer_id)
	print("  → Joueur ", peer_id, " se couche")
	_broadcast_sound("fold_rustle", 0.9)
	
	# Vérifier si le joueur a le Masque Affamé
	var has_affame = player_masks.get(peer_id, MaskEffects.PlayerMask.NONE) == MaskEffects.PlayerMask.AFFAME
	
	if has_affame:
		print("  → Joueur ", peer_id, " se couche (mais reste AFFAMÉ!)")
		_announce_to_all("👹 Player " + str(peer_id) + " folds but remains HUNGRY...")
	else:
		print("  → Joueur ", peer_id, " se couche")

func _handle_check(peer_id: int):
	print("  → Joueur ", peer_id, " check")
	_broadcast_sound("check_knock", 0.7)

func _handle_call(peer_id: int):
	var to_call = highest_bet - current_bets.get(peer_id, 0)
	var actual_call = min(to_call, player_stacks[peer_id])
	
	player_stacks[peer_id] -= actual_call
	current_bets[peer_id] += actual_call
	pot += actual_call
	
	print("  → Joueur ", peer_id, " suit pour ", actual_call, "$")
	
	_broadcast_sound("chips_stack", 0.85)
	
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
		_broadcast_sound("chips_stack", 0.7)
	else:
		print("  → Joueur ", peer_id, " mise ", additional_amount, "$")
		_broadcast_sound("chips_stack", 0.8)

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
	
	# Annoncer le gagnant à tous les joueurs
	_announce_to_all("🏆 Joueur " + str(winner_id) + " gagne " + str(pot) + "$ par forfait !")
	
	player_stacks[winner_id] += pot
	_update_player_display(winner_id)
	
	await get_tree().create_timer(3.0).timeout
	
	# Nettoyer les cartes sur la table (RPC pour tous les clients)
	_clear_table_cards.rpc()
	
	# Annoncer la nouvelle manche
	_announce_to_all("🎲 Nouvelle manche...")
	await get_tree().create_timer(1.5).timeout
	
	start_new_hand()

func _showdown():
	"""Révélation des mains et détermination du gagnant"""
	current_phase = GamePhase.SHOWDOWN
	_stop_timer()  # Arrêter le timer
	
	# Reset des effets de table (Darkness, etc.)
	if darkness_active:
		darkness_active = false
		current_turn_duration = 30.0
		for peer_id in all_players:
			var player_node = get_node("../PlayerContainer/" + str(peer_id))
			if player_node.has_method("apply_darkness_effect"):
				player_node.apply_darkness_effect.rpc_id(peer_id, false)
	
	print("\n🏆 SHOWDOWN")
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
	
	# Annoncer le(s) gagnant(s)
	# Annoncer le(s) gagnant(s)
	if winners.size() == 1:
		_announce_to_all("🏆 " + _get_player_name(winners[0]) + " gagne " + str(int(winnings)) + "$ !")
	else:
		_announce_to_all("🏆 Égalité ! Pot partagé entre " + str(winners.size()) + " joueurs")
	
	await get_tree().create_timer(4.0).timeout
	
	# Nettoyer les visuels des joueurs
	for peer_id in all_players:
		var player_node = get_node("../PlayerContainer/" + str(peer_id))
		player_node.clear_hand_visuals.rpc()
	
	# Nettoyer les cartes sur la table (RPC pour tous les clients)
	_clear_table_cards.rpc()
	
	# MASKARD: Augmenter les blinds pour la prochaine manche (x1.5)
	_increase_blinds()
	
	# Annoncer la nouvelle manche
	_announce_to_all("🎲 Nouvelle manche...")
	await get_tree().create_timer(1.5).timeout
	
	start_new_hand()

func _increase_blinds():
	"""Augmente les blinds de 1.5x à chaque manche (anti-longueurs)"""
	current_small_blind = int(current_small_blind * MaskEffects.BLIND_MULTIPLIER)
	current_big_blind = int(current_big_blind * MaskEffects.BLIND_MULTIPLIER)
	
	print("\n📈 BLINDS AUGMENTÉES: SB=", current_small_blind, "$ / BB=", current_big_blind, "$")
	_announce_to_all("📈 Blinds increased! SB=" + str(current_small_blind) + "$ / BB=" + str(current_big_blind) + "$")

func _announce_to_all(message: String):
	"""Envoie une annonce à tous les joueurs"""
	for peer_id in all_players:
		var player_node = get_node("../PlayerContainer/" + str(peer_id))
		player_node.show_announcement.rpc(message)

@rpc("authority", "call_local", "reliable")
func _clear_table_cards():
	"""Nettoie toutes les cartes du CardContainer (synchronisé)"""
	var card_container = get_node("../CardContainer")
	for child in card_container.get_children():
		child.queue_free()
	print("🧹 Table nettoyée")

func _broadcast_sound(sound_name: String, pitch: float = 1.0):
	"""Ordonne à tous les clients de jouer un son via leur AudioManager local"""
	for peer_id in all_players:
		# On cherche le nœud du joueur dans le monde
		var player_node = get_node_or_null("../PlayerContainer/" + str(peer_id))

		# Si le joueur existe, on appelle sa fonction RPC (qu'on a ajoutée dans Player.gd)
		if player_node and player_node.has_method("play_remote_sound"):
			player_node.play_remote_sound.rpc(sound_name, pitch)
