extends CharacterBody3D
# ============================================================================
# PLAYER - Contrôle du personnage + UI Poker
# ============================================================================

# --- VARIABLES DE MOUVEMENT & CAMERA ---
@export var sensitivity = 0.003
@onready var camera = $Head/Camera3D

# --- VARIABLES DE POKER & UI ---
@onready var action_ui = $UI/ActionButtons
@onready var info_label = $UI/Label_Info
@onready var stack_label = $UI/StackLabel
@onready var pot_label = $UI/PotLabel
@onready var call_label = $UI/ActionButtons/Label_ToCall
@onready var bet_input = $UI/ActionButtons/HBoxContainer/BetInput
@onready var btn_bet = $UI/ActionButtons/HBoxContainer/Btn_Miser
@onready var btn_fold = $UI/ActionButtons/HBoxContainer/Btn_Coucher

# --- VARIABLES LOGIQUES ---
var my_stack = 0
var current_to_call = 0
var can_check = false
var is_local_player = false
var is_my_turn = false

# ==============================================================================
# INITIALISATION RÉSEAU
# ==============================================================================

func _enter_tree():
	var player_id = name.to_int()
	set_multiplayer_authority(player_id)
	is_local_player = (player_id == multiplayer.get_unique_id())

func _ready():
	await get_tree().process_frame
	
	if is_local_player:
		print("✓ Joueur local initialisé (ID ", multiplayer.get_unique_id(), ")")
		
		# Caméra
		if camera: 
			camera.make_current()
		
		# Souris
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
		# Connexion boutons
		btn_bet.pressed.connect(_on_btn_bet_pressed)
		btn_fold.pressed.connect(_on_btn_fold_pressed)
		
		# UI initiale
		action_ui.hide()
		info_label.text = "En attente de joueurs..."
		
		# Afficher le bouton START si on est le premier joueur
		if multiplayer.get_unique_id() == 1:
			_create_start_button()
	else:
		# Désactiver pour les autres joueurs
		if camera: camera.current = false
		set_physics_process(false)
		set_process_unhandled_input(false)
		if has_node("UI"): $UI.queue_free()

# ==============================================================================
# BOUTON START (Uniquement pour le joueur 1 au début)
# ==============================================================================

func _create_start_button():
	"""Crée le bouton de démarrage de partie"""
	if not has_node("UI"):
		return
	
	var start_btn = Button.new()
	start_btn.name = "StartButton"
	start_btn.text = "▶ LANCER LA PARTIE"
	start_btn.custom_minimum_size = Vector2(300, 60)
	
	# Style
	start_btn.add_theme_font_size_override("font_size", 24)
	
	# Position centrale
	start_btn.position = Vector2(320 - 150, 400)
	
	start_btn.pressed.connect(_on_start_button_pressed)
	$UI.add_child(start_btn)
	
	print("→ Bouton START créé")

func _on_start_button_pressed():
	"""Envoie la demande de démarrage au serveur"""
	print("📢 Demande de démarrage envoyée")
	
	# Cacher le bouton
	if has_node("UI/StartButton"):
		$UI/StartButton.queue_free()
	
	info_label.text = "Démarrage de la partie..."
	
	# Appel RPC au GameManager (vérifier que le script est bien chargé)
	var dealer = get_node_or_null("/root/World/Dealer")
	if dealer and dealer.has_method("request_start_game"):
		dealer.request_start_game.rpc_id(1)
	else:
		print("❌ ERREUR : Le Dealer n'a pas le script game_manager.gd attaché !")
		info_label.text = "ERREUR : Dealer non configuré"

@rpc("any_peer", "call_local", "reliable")
func show_start_button():
	"""Appelé par le serveur quand assez de joueurs"""
	if not is_local_player or has_node("UI/StartButton"):
		return
	
	_create_start_button()
	info_label.text = "Prêt ! Cliquez START pour lancer"

# ==============================================================================
# CONTRÔLES CAMÉRA
# ==============================================================================

func _unhandled_input(event):
	if not is_local_player: return

	# Clic Droit = Mode FPS
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Rotation caméra
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * sensitivity)
		camera.rotate_x(-event.relative.y * sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))

# ==============================================================================
# RPC - RÉCEPTION DES INFOS DU SERVEUR
# ==============================================================================

@rpc("any_peer", "call_local", "reliable")
func notify_turn(my_turn: bool, to_call: int, can_check_flag: bool):
	"""Le serveur nous dit si c'est notre tour"""
	if not is_local_player:
		return
	
	is_my_turn = my_turn
	current_to_call = to_call
	can_check = can_check_flag
	
	if my_turn:
		action_ui.show()
		info_label.text = "🎯 À VOUS DE JOUER !"
		
		# Configurer l'input de mise
		bet_input.editable = true
		bet_input.min_value = to_call if to_call > 0 else BIG_BLIND
		bet_input.max_value = my_stack
		bet_input.value = to_call if to_call > 0 else 0
		
		# Adapter le texte du label
		if can_check:
			call_label.text = "✓ Vous pouvez checker"
		else:
			call_label.text = "À suivre : " + str(to_call) + "$"
		
		# Adapter les boutons
		if can_check:
			btn_bet.text = "CHECK / MISER"
		elif to_call >= my_stack:
			btn_bet.text = "ALL-IN (" + str(my_stack) + "$)"
		else:
			btn_bet.text = "SUIVRE / RELANCER"
		
	else:
		action_ui.hide()
		info_label.text = "⏳ En attente..."

@rpc("any_peer", "call_local", "reliable")
func update_stack(amount: int):
	"""Met à jour notre stack"""
	if is_local_player:
		my_stack = amount
		stack_label.text = "💰 Stack : " + str(my_stack) + "$"
		
		if has_node("UI/ActionButtons/HBoxContainer/BetInput"):
			bet_input.max_value = my_stack

@rpc("any_peer", "call_local", "reliable")
func update_pot(amount: int):
	"""Met à jour l'affichage du pot"""
	if is_local_player:
		pot_label.text = "🎲 POT : " + str(amount) + "$"

@rpc("any_peer", "call_local", "reliable")
func receive_cards(cards: Array):
	"""Reçoit nos 2 cartes privées"""
	print("🃏 Cartes reçues : ", cards)
	
	# Nettoyer anciennes cartes
	if has_node("HandContainer"):
		$HandContainer.queue_free()
	
	var hand_container = Node3D.new()
	hand_container.name = "HandContainer"
	add_child(hand_container)
	
	# TODO: Spawn visuel des cartes devant la caméra
	# Pour l'instant juste afficher dans le terminal
	
	if is_local_player:
		info_label.text = "🃏 Cartes : " + _card_to_string(cards[0]) + " " + _card_to_string(cards[1])

func _card_to_string(card_id: int) -> String:
	"""Convertit un ID de carte en texte lisible"""
	var suits = ["♠", "♥", "♦", "♣"]
	var ranks = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "V", "D", "R", "A"]
	
	var rank = card_id % 13
	var suit = int(card_id / 13)  # Conversion explicite en int
	
	return ranks[rank] + suits[suit]

@rpc("any_peer", "call_local", "reliable")
func show_hand_to_all(cards: Array):
	"""Showdown - Affiche les cartes de ce joueur à tous"""
	# TODO: Spawn visuel au-dessus de la tête
	print("📢 Joueur ", name, " montre : ", cards)

@rpc("any_peer", "call_local", "reliable")
func clear_hand_visuals():
	"""Nettoie les visuels de cartes"""
	if has_node("HandContainer"):
		$HandContainer.queue_free()
	if has_node("ShowdownDisplay"):
		$ShowdownDisplay.queue_free()

# ==============================================================================
# ACTIONS JOUEUR
# ==============================================================================

const BIG_BLIND = 20  # Doit matcher le GameManager

func _on_btn_bet_pressed():
	"""Bouton Miser/Check/Call/Relancer"""
	if not is_my_turn:
		return
	
	var bet_amount = int(bet_input.value)
	var dealer = get_node("/root/World/Dealer")
	
	if not dealer:
		print("❌ Dealer introuvable")
		return
	
	# Déterminer l'action
	if can_check and bet_amount == 0:
		# CHECK
		print("→ Je CHECK")
		dealer.player_action.rpc_id(1, "CHECK", 0)
	
	elif bet_amount == current_to_call:
		# CALL (suivre)
		print("→ Je CALL ", bet_amount, "$")
		dealer.player_action.rpc_id(1, "CALL", bet_amount)
	
	else:
		# BET / RAISE
		print("→ Je RAISE à ", bet_amount, "$")
		dealer.player_action.rpc_id(1, "BET", bet_amount)
	
	action_ui.hide()
	info_label.text = "⏳ Action envoyée..."

func _on_btn_fold_pressed():
	"""Bouton Se Coucher"""
	if not is_my_turn:
		return
	
	print("→ Je FOLD")
	
	var dealer = get_node("/root/World/Dealer")
	if dealer:
		dealer.player_action.rpc_id(1, "FOLD", 0)
	
	action_ui.hide()
	info_label.text = "💔 Vous vous êtes couché"

@rpc("any_peer", "call_local", "reliable")
func hide_start_button():
	if has_node("UI/StartButton"):
		$UI/StartButton.queue_free()
