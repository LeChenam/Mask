extends CharacterBody3D
# ============================================================================
# PLAYER - Contrôle du personnage + UI Poker
# ============================================================================

# --- VARIABLES DE MOUVEMENT & CAMERA ---
@export var sensitivity = 0.003
@onready var camera = $Head/Camera3D

# -- Variables Son ---
@onready var heartbeat_player = $HeartBeatPlayer

# --- VARIABLES DE POKER & UI ---
@onready var action_ui = $UI/ActionButtons
@onready var info_label = $UI/Label_Info
@onready var announcement_label = $UI/AnnouncementLabel
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
	
	# IMPORTANT: Désactiver immédiatement la caméra si ce n'est pas notre joueur
	# Cela évite la désynchronisation quand plusieurs joueurs sont spawnés
	if not is_local_player:
		var cam = get_node_or_null("Head/Camera3D")
		if cam:
			cam.current = false

func _ready():
	# Désactiver d'abord TOUTES les caméras des autres joueurs
	if not is_local_player:
		if camera:
			camera.current = false
		_setup_remote_player()
		return  # Sortir tôt pour les non-locaux
	
	await get_tree().process_frame
	
	# À ce stade, on est sûr que c'est le joueur local
	print("✓ Joueur local initialisé (ID ", multiplayer.get_unique_id(), ")")
	
	# Caméra - S'assurer qu'elle est bien active
	if camera: 
		camera.current = true
		camera.make_current()
		print("✓ Caméra activée pour joueur local")
	
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


# Appelé pour les joueurs distants seulement - désactive leur processing
func _setup_remote_player():
	if camera:
		camera.current = false
	set_physics_process(false)
	set_process_unhandled_input(false)
	if has_node("UI"):
		$UI.queue_free()

# ==============================================================================
# ANIMATIONS
# ==============================================================================

@rpc("any_peer", "call_local", "reliable")
func _play_player_idle_animation():
	"""Lance l'animation idle_joueur pour ce joueur (visible par tous)"""
	var human_node = get_node_or_null("MeshInstance3D2/human")
	if human_node:
		var animation_player = null
		for child in human_node.get_children():
			if child is AnimationPlayer:
				animation_player = child
				break
		
		if animation_player:
			if animation_player.has_animation("idle_joueur"):
				animation_player.play("idle_joueur")
				print("→ Animation idle_joueur lancée pour joueur ", name)
			else:
				print("⚠ Animation 'idle_joueur' non trouvée pour joueur ", name)
				print("   Animations disponibles:", animation_player.get_animation_list())

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
	AudioManager.play("ui_click")
	
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
		AudioManager.play("dealer_talk")
		heartbeat_player.pitch_scale = 0.9
		heartbeat_player.play()
		
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
		heartbeat_player.stop()

@rpc("any_peer", "call_local", "reliable")
func update_stack(amount: int):
	"""Met à jour notre stack"""
	if is_local_player:
		my_stack = amount
		stack_label.text = "💰 Stack : " + str(my_stack) + "$"
		
		AudioManager.play("chips_stack")
		
		if has_node("UI/ActionButtons/HBoxContainer/BetInput"):
			bet_input.max_value = my_stack

@rpc("any_peer", "call_local", "reliable")
func update_pot(amount: int):
	"""Met à jour l'affichage du pot"""
	if is_local_player:
		pot_label.text = "🎲 POT : " + str(amount) + "$"
		AudioManager.play("ting_money")

@rpc("any_peer", "call_local", "reliable")
func show_announcement(message: String):
	"""Affiche une annonce importante au centre de l'écran"""
	if is_local_player:
		announcement_label.text = message
		announcement_label.visible = true
		print("📢 Annonce: ", message)
		
		# Faire disparaître après 3 secondes
		await get_tree().create_timer(3.0).timeout
		announcement_label.visible = false

@rpc("any_peer", "call_local", "reliable")
func receive_cards(cards: Array):
	"""Reçoit nos 2 cartes privées et les affiche en 3D"""
	print("🃏 Cartes reçues : ", cards, " - is_local: ", is_local_player)
	
	# Nettoyer anciennes cartes (peut être dans Head ou directement sur le player)
	if has_node("Head/HandContainer"):
		$Head/HandContainer.queue_free()
		await get_tree().process_frame
	elif has_node("HandContainer"):
		$HandContainer.queue_free()
		await get_tree().process_frame
	
	# Créer le conteneur pour les cartes de la main
	var hand_container = Node3D.new()
	hand_container.name = "HandContainer"
	
	# Attacher au Head pour que les cartes suivent la vue du joueur
	if has_node("Head"):
		$Head.add_child(hand_container)
		# Position devant la caméra - ajusté pour QuadMesh 0.7x1.0
		hand_container.position = Vector3(0, -0.25, -0.5)
		print("🃏 HandContainer attaché au Head")
	else:
		add_child(hand_container)
		hand_container.position = Vector3(0, 1.0, -0.5)
		print("🃏 HandContainer attaché au Player (pas de Head)")
	
	# Spawn des 2 cartes - espacement ajusté pour nouvelle taille
	var offsets = [Vector3(-0.08, 0, 0), Vector3(0.08, 0, 0)]
	
	for i in range(cards.size()):
		var card = preload("res://scenes/card.tscn").instantiate()
		hand_container.add_child(card)
		print("🃏 Carte ", i, " instanciée: ", cards[i])
		
		# Position et rotation - incliné vers le joueur pour bien voir
		card.position = offsets[i]
		card.rotation_degrees = Vector3(-60, 0, 5 if i == 0 else -5)  # X négatif pour voir la face
		card.scale = Vector3(0.25, 0.25, 0.25)  # Taille augmentée
		
		# Appliquer la texture
		if card.has_method("set_card_visuals"):
			card.set_card_visuals(cards[i])
		
		# Révéler uniquement pour le joueur local
		if is_local_player and card.has_method("reveal"):
			card.reveal()

		await get_tree().create_timer(0.1).timeout
		AudioManager.play("card_slide", true, 0.9)
	
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
	"""Showdown - Affiche les cartes de ce joueur au-dessus de sa tête"""
	print("📢 Joueur ", name, " montre : ", cards)
	
	# Nettoyer ancien affichage
	if has_node("ShowdownDisplay"):
		$ShowdownDisplay.queue_free()
	
	# Créer conteneur au-dessus de la tête
	var container = Node3D.new()
	container.name = "ShowdownDisplay"
	add_child(container)
	container.position = Vector3(0, 2.0, 0)  # 2m au-dessus du joueur
	
	# Spawn des cartes côte à côte
	var spacing = 0.2
	var start_x = -spacing / 2.0
	
	for i in range(cards.size()):
		var card = preload("res://scenes/card.tscn").instantiate()
		container.add_child(card)
		
		card.position = Vector3(start_x + i * spacing, 0, 0)
		card.rotation_degrees = Vector3(0, 180, 0)  # Face vers l'extérieur
		card.scale = Vector3(1.2, 1.2, 1.2)
		
		if card.has_method("set_card_visuals"):
			card.set_card_visuals(cards[i])
		if card.has_method("reveal"):
			card.reveal()

@rpc("any_peer", "call_local", "reliable")
func clear_hand_visuals():
	"""Nettoie les visuels de cartes"""
	# HandContainer peut être dans Head ou directement sur le player
	if has_node("Head/HandContainer"):
		$Head/HandContainer.queue_free()
	elif has_node("HandContainer"):
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
	
	heartbeat_player.stop()
	AudioManager.play("ui_click", false)
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
	
	heartbeat_player.stop()
	AudioManager.play("ui_click", false)
	action_ui.hide()
	info_label.text = "💔 Vous vous êtes couché"

@rpc("any_peer", "call_local", "reliable")
func hide_start_button():
	if has_node("UI/StartButton"):
		$UI/StartButton.queue_free()

@rpc("any_peer", "call_local", "reliable")
func play_remote_sound(sound_name: String, pitch: float = 1.0):
	# On utilise ton AudioManager existant
	AudioManager.play(sound_name, true, pitch)
