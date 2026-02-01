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
@onready var btn_check = $UI/ActionButtons/HBoxContainer/CheckButton

# --- VARIABLES LOGIQUES ---
var my_stack = 0
var current_to_call = 0
var can_check = false
var timer_label: Label = null
var name_label_3d: Label3D = null
var player_pseudo: String = "Joueur"
var is_local_player = false
var is_my_turn = false

# --- CARTES EN MAIN (pour détection clic) ---
var hand_cards: Array = []  # Références aux cartes Node3D en main
var is_blinded: bool = false # État aveuglé (Black King)

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
		if btn_check:
			btn_check.text = "CHECK"
			btn_check.pressed.connect(_on_btn_check_pressed)
		
		# UI initiale
		action_ui.hide()
		info_label.text = "En attente de joueurs..."
		
		# Créer le label du Timer
		_create_timer_label()
		
		# Afficher le bouton START si on est le premier joueur
		if multiplayer.get_unique_id() == 1:
			_create_start_button()
	else:
		# Désactiver pour les autres joueurs
		if camera: camera.current = false
		set_physics_process(false)
		set_process_unhandled_input(false)
		if has_node("UI"): $UI.queue_free()
		
		# Créer le label 3D pour le pseudo
		_create_name_label_3d()

@rpc("any_peer", "call_local", "reliable")
func set_player_name(pseudo: String):
	"""Définit le pseudo du joueur"""
	player_pseudo = pseudo
	
	if name_label_3d:
		name_label_3d.text = pseudo
	
	if is_local_player:
		# Afficher mon propre nom quelque part ? (Optionnel)
		pass

func _create_name_label_3d():
	"""Crée un label 3D au-dessus du joueur"""
	if name_label_3d: return
	
	name_label_3d = Label3D.new()
	name_label_3d.name = "NameLabel3D"
	name_label_3d.text = player_pseudo
	name_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED

	name_label_3d.position = Vector3(0, 2.3, 0) # Ajustement hauteur
	name_label_3d.pixel_size = 0.005
	name_label_3d.font_size = 48
	name_label_3d.modulate = Color(1, 1, 1)
	name_label_3d.outline_render_priority = 0
	name_label_3d.outline_modulate = Color(0, 0, 0)
	add_child(name_label_3d)

@rpc("any_peer", "call_local", "reliable")
func mark_card_used(card_id: int):
	"""Marque une carte comme ayant utilisé son effet"""
	print("🃏 Carte ", card_id, " marquée comme utilisée")
	
	# Chercher la carte dans les mains
	# Note: hand_cards contient les noeuds cartes
	for card in hand_cards:
		if card.card_id == card_id:
			card.effect_used = true
			# Feedback visuel (griser la carte)
			if card.mesh_face and card.mesh_face.material_override:
				card.mesh_face.material_override.albedo_color = Color(0.5, 0.5, 0.5) # Griser
			if is_local_player:
				info_label.text = "🎭 Effet utilisé!"
			return

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

# --- VISUAL FX & HORROR ---

@rpc("any_peer", "call_local", "reliable")
func show_revealed_card_ui(target_id: int, card_id: int):
	"""Affiche une carte révélée (effet Observateur)"""
	print("👁️ Carte révélée : ", card_id, " de ", target_id)
	
	# Créer une UI temporaire
	var overlay = PanelContainer.new()
	overlay.name = "RevealOverlay"
	
	# Style sombre
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.9)
	style.border_color = Color(1, 0, 0, 1) # Bordure rouge
	style.border_width_left = 4
	style.border_width_right = 4
	style.border_width_top = 4
	style.border_width_bottom = 4
	overlay.add_theme_stylebox_override("panel", style)
	
	overlay.custom_minimum_size = Vector2(250, 350)
	# Position centrale (approximative)
	overlay.position = Vector2(400, 200) 
	
	var vbox = VBoxContainer.new()
	overlay.add_child(vbox)
	
	# Titre
	var lbl = Label.new()
	lbl.text = "JE TE VOIS..."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(1, 0, 0))
	lbl.add_theme_font_size_override("font_size", 24)
	vbox.add_child(lbl)
	
	# Nom du joueur
	# Nom du joueur
	var name_lbl = Label.new()
	var p_name = "Joueur " + str(target_id)
	var neighbor = get_parent().get_node_or_null(str(target_id))
	if neighbor and "player_pseudo" in neighbor:
		p_name = neighbor.player_pseudo
		
	name_lbl.text = "Carte de " + p_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)
	
	# Texture Carte (approximative ou chargée)
	var tex_rect = TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(140, 200)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	# Charger texture via logique card.gd (simplifiée ici)
	var rank_index = card_id % 13
	var suit_index = int(float(card_id) / 13)
	var suits = ["pique", "coeur", "carreau", "trefle"]
	var suit_prefixes = ["pique", "coeurs", "carreau", "trefle"]
	var ranks = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "valet", "reine", "roi", "as"]
	var path = "res://assets/cartes_sprite/" + suits[suit_index] + "/" + suit_prefixes[suit_index] + "_" + ranks[rank_index] + ".png"
	if FileAccess.file_exists(path):
		tex_rect.texture = load(path)
	
	vbox.add_child(tex_rect)
	
	$UI.add_child(overlay)
	
	# Auto-destruction
	await get_tree().create_timer(4.0).timeout
	if is_instance_valid(overlay):
		overlay.queue_free()

@rpc("any_peer", "call_local", "reliable")
func trigger_horror_effect(effect_name: String):
	"""Déclenche un effet d'horreur visuel/sonore"""
	match effect_name:
		"jack_red_eye":
			# Flash rouge + son
			var flash = ColorRect.new()
			flash.color = Color(1, 0, 0, 0.3)
			flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			$UI.add_child(flash)
			
			var lbl = Label.new()
			lbl.text = "👁️"
			lbl.add_theme_font_size_override("font_size", 100)
			lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			flash.add_child(lbl)
			
			# Animation simple
			var tween = create_tween()
			tween.tween_property(flash, "modulate:a", 0.0, 2.0)
			tween.tween_callback(flash.queue_free)

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

func _create_timer_label():
	"""Crée le label pour le timer"""
	if timer_label: return
	
	timer_label = Label.new()
	timer_label.name = "TimerLabel"
	timer_label.text = "30"
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 32)
	timer_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))  # Or
	
	# Position en haut au centre (sous l'info)
	timer_label.position = Vector2(0, 80)
	timer_label.size = Vector2(1152, 40)  # Largeur écran (ou ajuster)
	
	$UI.add_child(timer_label)

@rpc("any_peer", "call_local", "reliable")
func update_timer(time_left: int):
	"""Met à jour l'affichage du timer"""
	if not timer_label:
		return
	
	timer_label.text = str(time_left)
	
	# Afficher uniquement si c'est notre tour (visible pour le joueur actif)
	# Ou si on veut le cacher aux autres
	timer_label.visible = is_my_turn
	
	# Changer couleur selon urgence
	if time_left <= 5:
		timer_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2)) # Rouge
	elif time_left <= 10:
		timer_label.add_theme_color_override("font_color", Color(1, 0.5, 0)) # Orange
	else:
		timer_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2)) # Or

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
# CONTRÔLES CAMÉRA ET CLIC SUR CARTES
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
		
		# Clic Gauche = Detection clic sur carte masquée
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
				_check_card_click()

	# Rotation caméra
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * sensitivity)
		camera.rotate_x(-event.relative.y * sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))

func _check_card_click():
	"""Vérifie si on clique sur une carte masquée en main"""
	if hand_cards.is_empty():
		return
	
	# Obtenir la position de la souris
	var mouse_pos = get_viewport().get_mouse_position()
	
	# Créer un raycast depuis la caméra
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 5.0
	
	# Query physique
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	
	var result = space_state.intersect_ray(query)
	
	if result:
		print("🎯 Raycast hit: ", result.collider.get_parent().name if result.collider.get_parent() else "?")
		
		# Vérifier si c'est une carte en main
		for card in hand_cards:
			if card and is_instance_valid(card):
				# Vérifier si le collider appartient à cette carte
				if result.collider.get_parent() == card or result.collider == card:
					if card.is_masked and not card.effect_used:
						print("🎭 CLIC sur carte masquée ID: ", card.card_id)
						_try_activate_card_effect(card)
						return

var hovered_card = null
var hover_tooltip: Label = null

func _process(_delta):
	if not is_local_player or hand_cards.is_empty():
		return
	
	# Seulement quand souris visible
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		_hide_card_tooltip()
		return
	
	# Raycast pour détecter la carte sous la souris
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 2.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	
	var result = space_state.intersect_ray(query)
	
	var found_card = null
	if result:
		for card in hand_cards:
			if card and is_instance_valid(card):
				if result.collider.get_parent() == card or result.collider == card:
					found_card = card
					break
	
	# Mettre à jour le tooltip
	if found_card and found_card.is_masked:
		if found_card != hovered_card:
			hovered_card = found_card
			_show_card_tooltip(found_card)
	else:
		if hovered_card:
			hovered_card = null
			_hide_card_tooltip()

func _show_card_tooltip(card):
	"""Affiche le tooltip avec l'effet de la carte masquée"""
	if not hover_tooltip:
		hover_tooltip = Label.new()
		hover_tooltip.name = "CardTooltip"
		hover_tooltip.add_theme_font_size_override("font_size", 14)
		hover_tooltip.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
		$UI.add_child(hover_tooltip)
	
	var effect_text = _get_mask_effect_description(card.card_id)
	var status = " ✓" if card.effect_used else " (Clic pour activer)"
	hover_tooltip.text = "🎭 " + effect_text + status
	hover_tooltip.position = Vector2(200, 500)
	hover_tooltip.visible = true

func _hide_card_tooltip():
	"""Cache le tooltip"""
	if hover_tooltip:
		hover_tooltip.visible = false

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
		
		# Configurer le bouton CHECK
		if btn_check:
			btn_check.visible = can_check
			btn_check.disabled = not can_check
		
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
	"""Reçoit nos 2 cartes privées et les affiche en 3D (compatibilité)"""
	# Appeler la version masquée avec aucun masque
	receive_cards_masked(cards, [false, false])

@rpc("any_peer", "call_local", "reliable")
func receive_cards_masked(cards: Array, cards_masked: Array):
	"""Reçoit nos 2 cartes privées avec info de masque et les affiche en 3D"""
	print("🃏 Cartes reçues : ", cards, " masquées: ", cards_masked, " - is_local: ", is_local_player)
	
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
	var my_masked_cards = []
	hand_cards.clear()  # Vider les anciennes références
	
	for i in range(cards.size()):
		var card = preload("res://scenes/card.tscn").instantiate()
		hand_container.add_child(card)
		print("🃏 Carte ", i, " instanciée: ", cards[i], " masquée: ", cards_masked[i])
		
		# Position et rotation - incliné vers le joueur pour bien voir
		card.position = offsets[i]
		card.rotation_degrees = Vector3(-60, 0, 5 if i == 0 else -5)  # X négatif pour voir la face
		card.scale = Vector3(0.25, 0.25, 0.25)  # Taille augmentée
		
		# Appliquer la texture (avec masque si applicable)
		if card.has_method("set_card_visuals"):
			card.set_card_visuals(cards[i], cards_masked[i])
		
		# Configurer comme carte en main pour l'interaction
		if card.has_method("set_as_hand_card"):
			card.set_as_hand_card(is_local_player)
		
		# Si le joueur est aveuglé, cacher la carte
		var local_id = multiplayer.get_unique_id()
		var player_node = get_node_or_null("../PlayerContainer/" + str(local_id))
		if player_node and "is_blinded" in player_node and player_node.is_blinded:
			if card.has_method("set_blind_view"):
				card.set_blind_view(true)
		
		# Révéler uniquement pour le joueur local
		if is_local_player and card.has_method("reveal"):
			card.reveal()

		await get_tree().create_timer(0.1).timeout
		AudioManager.play("card_slide", true, 0.9)
		
		# Ajouter à la liste des cartes en main pour la détection de clic
		if is_local_player:
			hand_cards.append(card)
		
		# Si masquée, connecter les signaux pour l'interaction
		if cards_masked[i] and is_local_player:
			my_masked_cards.append(card)
			print("🎭 Carte masquée détectée! Connexion signaux pour carte ", cards[i])
			if card.has_signal("mask_effect_activated"):
				card.mask_effect_activated.connect(_on_mask_effect_activated)
				print("   ✓ Signal mask_effect_activated connecté")
			if card.has_signal("mask_hovered"):
				card.mask_hovered.connect(_on_mask_hovered)
				print("   ✓ Signal mask_hovered connecté")
	
	if is_local_player:
		var card_text = _card_to_string(cards[0]) + " " + _card_to_string(cards[1])
		var mask_text = ""
		if cards_masked[0] or cards_masked[1]:
			mask_text = " 🎭"
		info_label.text = "🃏 Cartes : " + card_text + mask_text

func _on_mask_effect_activated(card_id: int):
	"""Appelé par le signal de la carte - redirige vers notre nouveau système"""
	for card in hand_cards:
		if card and is_instance_valid(card) and card.card_id == card_id:
			_try_activate_card_effect(card)
			return

# --- SYSTÈME DE SÉLECTION DE CIBLE ---
var pending_card_effect = null  # Carte en attente de sélection de cible
var target_selection_ui: Control = null

func _try_activate_card_effect(card):
	"""Essaie d'activer l'effet d'une carte - ouvre le menu si ciblé"""
	if card.effect_used:
		info_label.text = "⚠ Effet déjà utilisé!"
		return
	
	# Vérifier si cet effet nécessite une cible
	var needs_target = _effect_needs_target(card.card_id)
	var needs_card_selection = _effect_needs_card_selection(card.card_id)
	
	if needs_target:
		# Ouvrir le menu de sélection de cible (joueur)
		pending_card_effect = card
		_show_target_selection_ui(card.card_id)
	elif needs_card_selection:
		# Ouvrir le menu de sélection de carte (soi-même)
		pending_card_effect = card
		_show_card_selection_ui(card.card_id)
	else:
		# Effet sans cible - activer directement
		# card.effect_used = true # Ne pas marquer utilisé tant que le serveur n'a pas validé !
		_send_effect_activation(card.card_id, -1)

func _effect_needs_target(card_id: int) -> bool:
	"""Détermine si l'effet de cette carte nécessite une cible"""
	var rank_index = card_id % 13
	var suit_index = int(float(card_id) / 13)
	var is_red = suit_index == 1 or suit_index == 2
	var rank_type = rank_index - 9  # 0=Valet, 1=Dame, 2=Roi
	
	# Effets qui nécessitent une cible:
	# - Valet Rouge: Inspecter une carte d'un joueur
	# - Dame Rouge: Voler 50$ à un joueur
	# - Roi Rouge: Forcer un pacte avec un joueur
	# - Dame Noire: Forcer révélation d'un joueur
	# - Roi Noir: Aveugler un joueur
	
	if is_red:
		return rank_type in [0, 1, 2]  # Tous les rouges ciblent
	else:
		return rank_type in [1, 2]  # Dame et Roi noirs ciblent

func _effect_needs_card_selection(card_id: int) -> bool:
	"""Détermine si l'effet nécessite de choisir une de ses propres cartes"""
	var rank_index = card_id % 13
	var suit_index = int(float(card_id) / 13)
	var is_red = suit_index == 1 or suit_index == 2
	var rank_type = rank_index - 9
	
	# Valet Noir : Échanger une carte
	if not is_red and rank_type == 0:
		return true
		
	return false

func _show_target_selection_ui(card_id: int):
	"""Affiche le menu de sélection de cible"""
	# Nettoyer ancien menu
	if target_selection_ui:
		target_selection_ui.queue_free()
	
	target_selection_ui = PanelContainer.new()
	target_selection_ui.name = "TargetSelectionUI"
	
	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.05, 0.15, 0.95)
	style.border_color = Color(0.8, 0.2, 0.2, 1.0)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	target_selection_ui.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	target_selection_ui.add_child(vbox)
	
	# Titre
	var title = Label.new()
	title.text = "🎯 Choisir une cible"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1, 0.8, 0.6))
	vbox.add_child(title)
	
	# Effet description
	var desc = Label.new()
	desc.text = _get_mask_effect_description(card_id)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(desc)
	
	# Boutons pour chaque joueur (basé sur les noeuds présents = fiable)
	var my_id = multiplayer.get_unique_id()
	
	# Parcourir les voisins dans PlayerContainer
	for neighbor in get_parent().get_children():
		if neighbor.name == str(my_id): continue # Skip self
		if not neighbor.has_method("set_player_name"): continue # Skip non-players
		
		var pid = neighbor.name.to_int()
		var pseudo = "Joueur " + str(pid)
		
		# Récupérer le pseudo si disponible
		if "player_pseudo" in neighbor:
			pseudo = neighbor.player_pseudo
			
		var btn = Button.new()
		btn.text = "👤 " + pseudo
		btn.custom_minimum_size = Vector2(150, 35)
		btn.pressed.connect(_on_target_selected.bind(pid))
		vbox.add_child(btn)
	
	# Bouton Annuler
	var cancel_btn = Button.new()
	cancel_btn.text = "✗ Annuler"
	cancel_btn.custom_minimum_size = Vector2(150, 30)
	cancel_btn.pressed.connect(_on_target_cancelled)
	vbox.add_child(cancel_btn)
	
	# Positionner
	target_selection_ui.position = Vector2(280, 200)
	$UI.add_child(target_selection_ui)
	
	info_label.text = "🎯 Sélectionnez votre cible..."

func _on_target_selected(target_id: int):
	"""Une cible a été sélectionnée"""
	if pending_card_effect:
		# pending_card_effect.effect_used = true # Ne pas marquer utilisé tant que le serveur n'a pas validé !
		_send_effect_activation(pending_card_effect.card_id, target_id)
		pending_card_effect = null
	
	if target_selection_ui:
		target_selection_ui.queue_free()
		target_selection_ui = null
	
	info_label.text = "🎭 Effet lancé sur Joueur " + str(target_id) + "!"

func _on_target_cancelled():
	"""Annulation de la sélection"""
	pending_card_effect = null
	
	if target_selection_ui:
		target_selection_ui.queue_free()
		target_selection_ui = null
	
	info_label.text = "❌ Effet annulé"

func _show_card_selection_ui(card_id: int):
	"""Affiche le menu de sélection de carte à échanger (Valet Noir)"""
	if target_selection_ui:
		target_selection_ui.queue_free()
	
	target_selection_ui = PanelContainer.new()
	target_selection_ui.name = "CardSelectionUI"
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.05, 0.15, 0.95)
	style.border_color = Color(0.4, 0.2, 0.8, 1.0) # Violet pour Trickster
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	target_selection_ui.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	target_selection_ui.add_child(vbox)
	
	var title = Label.new()
	title.text = "CHOISIR CARTE À ÉCHANGER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.6, 0.4, 1.0))
	vbox.add_child(title)
	
	# Lister nos cartes
	for i in range(hand_cards.size()):
		var c = hand_cards[i]
		# On peut échanger n'importe laquelle, même celle qui active l'effet
		# (Si on échange le Valet Noir, l'effet part avec lui ?)
		# Le user n'a pas précisé restriction.
		
		var btn = Button.new()
		var card_name = _get_card_name(c.card_id)
		btn.text = card_name
		btn.custom_minimum_size = Vector2(180, 40)
		btn.pressed.connect(_on_card_to_swap_selected.bind(c.card_id))
		vbox.add_child(btn)
			
	var cancel_btn = Button.new()
	cancel_btn.text = "✗ Annuler"
	cancel_btn.pressed.connect(_on_target_cancelled)
	vbox.add_child(cancel_btn)
	
	target_selection_ui.position = Vector2(280, 200)
	$UI.add_child(target_selection_ui)
	info_label.text = "🔄 Quelle carte échanger ?"

func _on_card_to_swap_selected(card_to_swap_id: int):
	"""Une carte à échanger a été choisie"""
	if pending_card_effect:
		# On envoie l'ID de la carte à échanger comme 'target_id'
		# Le serveur saura interpréter car c'est un effet Valet Noir
		_send_effect_activation(pending_card_effect.card_id, card_to_swap_id)
		pending_card_effect = null
	
	if target_selection_ui:
		target_selection_ui.queue_free()
		target_selection_ui = null
		
	info_label.text = "🔄 Échange envoyé..."

func _get_card_name(card_id: int) -> String:
	var ranks = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "Valet", "Dame", "Roi", "As"]
	var suits = ["♠", "♥", "♦", "♣"]
	var r = card_id % 13
	var s = int(card_id / 13)
	return ranks[r] + " " + suits[s]

func _send_effect_activation(card_id: int, target_id: int):
	"""Envoie l'activation de l'effet au serveur"""
	print("🎭 Envoi activation: carte=", card_id, " cible=", target_id)
	
	var dealer = get_node_or_null("/root/World/Dealer")
	if dealer:
		dealer.request_activate_mask_effect_targeted.rpc_id(1, card_id, target_id)
	else:
		print("⚠ Dealer introuvable")

# --- RPC POUR RECEVOIR LES RÉSULTATS ---

@rpc("any_peer", "call_local", "reliable")
func show_effect_result(message: String):
	"""Affiche le résultat d'un effet de carte"""
	print("🎭 Résultat effet: ", message)
	info_label.text = "🎭 " + message
	
	# Aussi afficher dans l'annonce
	show_announcement(message)

func _on_mask_hovered(card_id: int, is_hovering: bool):
	"""Appelé quand la souris survole une carte masquée"""
	if is_hovering:
		# Afficher le tooltip avec la description de l'effet
		var mask_info = _get_mask_effect_description(card_id)
		if mask_info != "":
			info_label.text = "🎭 " + mask_info
	else:
		# Restaurer le texte par défaut
		if is_my_turn:
			info_label.text = "🎯 À VOUS DE JOUER !"
		else:
			info_label.text = "⏳ En attente..."

func _get_mask_effect_description(card_id: int) -> String:
	"""Retourne la description de l'effet de masque pour une carte"""
	var rank_index = card_id % 13
	var suit_index = int(float(card_id) / 13)
	
	# Vérifier que c'est bien une tête
	if rank_index < 9 or rank_index > 11:
		return ""
	
	var is_red = suit_index == 1 or suit_index == 2
	var rank_type = rank_index - 9  # 0=Valet, 1=Dame, 2=Roi
	
	# Descriptions courtes pour l'affichage
	if is_red:
		match rank_type:
			0: return "Observer: Inspect one card from a player"
			1: return "Parasite: Steal 50 chips from a player"
			2: return "Banker: Force a pact to share gains"
	else:
		match rank_type:
			0: return "Trickster: Swap one card with deck"
			1: return "Inquisitor: Force reveal highest card"
			2: return "Void: Blind a random player"
	
	return ""

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
	"""Bouton Miser/Call/Relancer (plus de check ici)"""
	if not is_my_turn:
		return
	
	var bet_amount = int(bet_input.value)
	var dealer = get_node("/root/World/Dealer")
	
	if not dealer:
		print("❌ Dealer introuvable")
		return
	
	# Déterminer l'action
	if bet_amount <= current_to_call:
		# CALL (suivre)
		print("→ Je CALL ", current_to_call, "$")
		dealer.player_action.rpc_id(1, "CALL", current_to_call)
	else:
		# BET / RAISE
		print("→ Je RAISE à ", bet_amount, "$")
		dealer.player_action.rpc_id(1, "BET", bet_amount)
	
	heartbeat_player.stop()
	AudioManager.play("ui_click", false)
	action_ui.hide()
	info_label.text = "⏳ Action envoyée..."

func _on_btn_check_pressed():
	"""Bouton CHECK"""
	if not is_my_turn or not can_check:
		return
	
	print("→ Je CHECK")
	
	var dealer = get_node("/root/World/Dealer")
	if dealer:
		dealer.player_action.rpc_id(1, "CHECK", 0)
	
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
# ==============================================================================
# SHOP UI - ACHAT DE MASQUES
# ==============================================================================

const MaskEffects = preload("res://scripts/Game/MaskEffects.gd")

var shop_container: Control = null
var current_mask: int = 0  # 0 = aucun masque

@rpc("any_peer", "call_local", "reliable")
func show_shop_ui(available_masks: Array, player_chips: int):
	"""Affiche l'interface du shop de masques"""
	if not is_local_player:
		return
	
	print("🛍️ Ouverture du shop - Masques disponibles: ", available_masks)
	
	# Nettoyer ancien shop si présent
	if shop_container:
		shop_container.queue_free()
		await get_tree().process_frame
	
	# Créer le conteneur principal
	shop_container = PanelContainer.new()
	shop_container.name = "ShopUI"
	
	# Style du panel - thème horror
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.02, 0.08, 0.95)
	style.border_color = Color(0.6, 0.1, 0.1, 1.0)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 15
	style.corner_radius_top_right = 15
	style.corner_radius_bottom_left = 15
	style.corner_radius_bottom_right = 15
	shop_container.add_theme_stylebox_override("panel", style)
	
	# Layout vertical
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	shop_container.add_child(vbox)
	
	# Titre
	var title = Label.new()
	title.text = "🎭 MASK SHOP 🎭"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2, 1.0))
	vbox.add_child(title)
	
	# Sous-titre avec jetons
	var subtitle = Label.new()
	subtitle.text = "💰 Your chips: " + str(player_chips) + "$ | Cost: 100$"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5, 1.0))
	vbox.add_child(subtitle)
	
	# Conteneur horizontal pour les masques
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)
	
	# Créer les boutons de masque
	for mask_type in available_masks:
		var mask_btn = _create_mask_button(mask_type, player_chips >= 100)
		hbox.add_child(mask_btn)
	
	# Bouton "Skip"
	var skip_btn = Button.new()
	skip_btn.text = "✗ SKIP"
	skip_btn.custom_minimum_size = Vector2(100, 40)
	skip_btn.add_theme_font_size_override("font_size", 16)
	skip_btn.pressed.connect(_on_skip_shop_pressed)
	vbox.add_child(skip_btn)
	
	# Positionner le shop
	shop_container.position = Vector2(120, 150)
	shop_container.size = Vector2(400, 350)
	
	$UI.add_child(shop_container)
	
	info_label.text = "🛍️ Choisissez un masque!"

func _create_mask_button(mask_type: int, can_afford: bool) -> Control:
	"""Crée un bouton de masque pour le shop"""
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 5)
	
	var mask_info = MaskEffects.get_player_mask_info(mask_type)
	
	# Icône / Nom du masque
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(110, 100)
	
	# Icône selon le masque
	match mask_type:
		MaskEffects.PlayerMask.CORBEAU:
			btn.text = "🪶\nRaven"
		MaskEffects.PlayerMask.VOILE:
			btn.text = "🛡️\nVeiled"
		MaskEffects.PlayerMask.AFFAME:
			btn.text = "😈\nHungry"
	
	btn.add_theme_font_size_override("font_size", 18)
	
	# Style du bouton
	if can_afford:
		btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
		btn.pressed.connect(_on_mask_button_pressed.bind(mask_type))
	else:
		btn.modulate = Color(0.5, 0.5, 0.5, 0.7)
		btn.disabled = true
	
	container.add_child(btn)
	
	# Description courte
	var desc = Label.new()
	desc.text = mask_info.description.substr(0, 30) + "..."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	desc.custom_minimum_size = Vector2(110, 40)
	container.add_child(desc)
	
	return container

func _on_mask_button_pressed(mask_type: int):
	"""Achète un masque"""
	print("🎭 Achat du masque type ", mask_type)
	
	var dealer = get_node_or_null("/root/World/Dealer")
	if dealer:
		dealer.request_buy_mask.rpc_id(1, mask_type)
	
	current_mask = mask_type
	
	# Fermer le shop
	if shop_container:
		shop_container.queue_free()
		shop_container = null
	
	var mask_info = MaskEffects.get_player_mask_info(mask_type)
	info_label.text = "🎭 Vous portez: " + mask_info.name_en
	
	# Notifier le serveur qu'on a fini
	if dealer:
		dealer.player_finished_shop_phase.rpc_id(1)

func _on_skip_shop_pressed():
	"""Le joueur choisit de ne pas acheter de masque"""
	print("⏭️ Shop ignoré")
	
	if shop_container:
		shop_container.queue_free()
		shop_container = null
	
	info_label.text = "⏭️ Pas de masque cette manche (En attente...)"
	
	# Notifier le serveur qu'on a fini
	var dealer = get_node_or_null("/root/World/Dealer")
	if dealer:
		dealer.player_finished_shop_phase.rpc_id(1)

@rpc("any_peer", "call_local", "reliable")
func hide_shop_ui():
	"""Cache l'UI du shop"""
	if shop_container:
		shop_container.queue_free()
		shop_container = null

# ==============================================================================
# EFFETS VISUELS ADDITIONNELS
# ==============================================================================

@rpc("any_peer", "call_local", "reliable")
func apply_darkness_effect(enabled: bool):
	"""Applique l'effet de ténèbres (Roi Noir)"""
	if not is_local_player:
		return
	
	if enabled:
		# Créer un overlay sombre
		var darkness = ColorRect.new()
		darkness.name = "DarknessOverlay"
		darkness.color = Color(0, 0, 0, 0.92)  # Opacité très forte (Ténèbres absolues)
		darkness.set_anchors_preset(Control.PRESET_FULL_RECT)
		darkness.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$UI.add_child(darkness)
		print("🌑 Ténèbres appliquées!")
	else:
		if has_node("UI/DarknessOverlay"):
			$UI/DarknessOverlay.queue_free()

@rpc("any_peer", "call_local", "reliable")
func set_blinded(enabled: bool):
	"""Empêche le joueur de voir les cartes communes"""
	if not is_local_player:
		return
	
	is_blinded = enabled
	
	# Mettre à jour les cartes sur la table
	var card_container = get_node_or_null("../CardContainer")
	if card_container:
		for card in card_container.get_children():
			if card.has_method("set_blind_view"):
				card.set_blind_view(enabled)
	
	if enabled:
		info_label.text = "🌑 VOUS ÊTES AVEUGLÉ!"
		# Visual overlay
		var blind_overlay = ColorRect.new()
		blind_overlay.name = "BlindOverlay"
		blind_overlay.color = Color(0.1, 0, 0.1, 0.4) # Moins opaque car les cartes sont cachées
		blind_overlay.position = Vector2(200, 400)
		blind_overlay.size = Vector2(240, 100)
		$UI.add_child(blind_overlay)
		
		var blind_label = Label.new()
		blind_label.text = "👁️ BLINDED"
		blind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		blind_label.position = Vector2(20, 20)
		blind_overlay.add_child(blind_label)
		blind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		blind_label.position = Vector2(20, 20)
		blind_overlay.add_child(blind_label)
	else:
		if has_node("UI/BlindOverlay"):
			$UI/BlindOverlay.queue_free()
