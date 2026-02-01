extends CharacterBody3D

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

# --- VARIABLES LOGIQUES ---
var my_stack = 0
var current_to_call = 0
var is_local_player = false

# ==============================================================================
# INITIALISATION RÉSEAU
# ==============================================================================

func _enter_tree():
	# Définit l'autorité réseau dès la création du nœud
	var player_id = name.to_int()
	set_multiplayer_authority(player_id)
	
	# Vérifie si c'est NOTRE personnage sur NOTRE ordinateur
	is_local_player = (player_id == multiplayer.get_unique_id())
	print("PLAYER : Spawn du joueur ", player_id, " - Est local: ", is_local_player)

func _ready():
	# Attendre un frame pour que la synchro physique soit prête
	await get_tree().process_frame
	
	if is_local_player:
		# --- C'EST MON PERSONNAGE ---
		print("PLAYER : Configuration locale (ID ", multiplayer.get_unique_id(), ")")
		
		# 1. Caméra
		if camera: camera.make_current()
		
		# 2. Souris (Visible par défaut pour cliquer sur l'UI)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
		# 3. Connexion des boutons UI (Poker)
		$UI/ActionButtons/HBoxContainer/Btn_Miser.pressed.connect(_on_btn_miser_pressed)
		$UI/ActionButtons/HBoxContainer/Btn_Coucher.pressed.connect(_on_btn_coucher_pressed)
		
		# 4. État initial de l'UI
		action_ui.hide()
		info_label.text = "En attente du début de partie..."
		
	else:
		# --- C'EST LE PERSONNAGE D'UN AUTRE ---
		print("PLAYER : Configuration distante")
		
		# 1. Désactiver les contrôles et la caméra
		if camera: camera.current = false
		set_physics_process(false)
		set_process_unhandled_input(false)
		
		# 2. SUPPRIMER L'UI (On ne veut pas voir les boutons des autres)
		if has_node("UI"):
			$UI.queue_free()

# ==============================================================================
# GESTION DES ENTRÉES (SOURIS / MOUVEMENT)
# ==============================================================================

func _unhandled_input(event):
	if not is_local_player: return

	# Clic Droit maintenu = Mode Caméra (FPS)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Rotation de la tête
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * sensitivity)
		camera.rotate_x(-event.relative.y * sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))

# ==============================================================================
# LOGIQUE POKER - RPC (Reçus du Serveur)
# ==============================================================================

@rpc("any_peer", "call_local", "reliable")
func notify_turn(is_my_turn: bool, amount_to_call: int = 0):
	print("PLAYER RPC : notify_turn reçu - is_local_player=", is_local_player, " is_my_turn=", is_my_turn)
	if not is_local_player: return
	if not is_instance_valid(action_ui): return

	action_ui.visible = is_my_turn
	current_to_call = amount_to_call
	
	if is_my_turn:
		if is_instance_valid(info_label):
			info_label.text = "À VOUS DE JOUER !"
		
		if amount_to_call > 0:
			if is_instance_valid(call_label):
				call_label.text = "Mise à suivre : " + str(amount_to_call) + "$"
			if is_instance_valid(bet_input):
				bet_input.value = amount_to_call
				bet_input.min_value = amount_to_call
		else:
			if is_instance_valid(call_label):
				call_label.text = "Parole (Check)"
			if is_instance_valid(bet_input):
				bet_input.value = 0
				bet_input.min_value = 0
	else:
		if is_instance_valid(info_label):
			info_label.text = "Le voisin réfléchit..."

@rpc("any_peer", "call_local", "reliable")
func update_stack(new_amount: int):
	print("PLAYER RPC : update_stack reçu - is_local_player=", is_local_player, " amount=", new_amount)
	if not is_local_player: return
	
	my_stack = new_amount
	if is_instance_valid(stack_label):
		stack_label.text = "Argent : " + str(my_stack) + "$"
	if is_instance_valid(bet_input):
		bet_input.max_value = my_stack

@rpc("any_peer", "call_local", "reliable")
func update_pot(amount: int):
	print("PLAYER RPC : update_pot reçu - is_local_player=", is_local_player, " pot=", amount)
	if not is_local_player: return
	
	if is_instance_valid(pot_label):
		pot_label.text = "POT : " + str(amount) + "$"

@rpc("any_peer", "call_local", "reliable")
func receive_cards(cards: Array):
	print("Cartes reçues : ", cards)
	
	# Nettoyer les vieilles cartes s'il y en a
	if has_node("HandContainer"): $HandContainer.queue_free()
	
	var hand_node = Node3D.new()
	hand_node.name = "HandContainer"
	add_child(hand_node)
	
	# Positionner les cartes devant la caméra (Ajuste selon ton modèle)
	# Les cartes sont attachées au Player, donc elles bougent avec lui
	var offsets = [Vector3(-0.2, -0.2, -0.5), Vector3(0.2, -0.2, -0.5)]
	
	for i in range(cards.size()):
		# Assure-toi que card.tscn existe bien à cet endroit
		var card_obj = preload("res://scenes/card.tscn").instantiate()
		hand_node.add_child(card_obj)
		
		# On place la carte relative au joueur
		card_obj.position = offsets[i] 
		# On la tourne pour qu'elle soit face au joueur
		card_obj.rotation_degrees.x = 70 
		
		# On applique la texture
		if card_obj.has_method("set_card_visuals"):
			card_obj.set_card_visuals(cards[i])
		
		# On force la face visible pour le joueur local
		if card_obj.has_method("reveal"):
			card_obj.reveal()

@rpc("any_peer", "call_local", "reliable")
func show_hand_to_all(cards: Array):
	# Affiche les cartes au-dessus de la tête du joueur pour le Showdown
	if has_node("ShowdownDisplay"): get_node("ShowdownDisplay").queue_free()
	
	var container = Node3D.new()
	container.name = "ShowdownDisplay"
	add_child(container)
	container.position = Vector3(0, 2.2, 0) # 2.2m au dessus du sol
	
	var spacing = 0.4
	var current_x = -spacing / 2.0
	
	for card_id in cards:
		var card_obj = preload("res://scenes/card.tscn").instantiate()
		container.add_child(card_obj)
		card_obj.position = Vector3(current_x, 0, 0)
		
		if card_obj.has_method("set_card_visuals"):
			card_obj.set_card_visuals(card_id)
			
		current_x += spacing

@rpc("any_peer", "call_local", "reliable")
func clear_hand_visuals():
	if has_node("ShowdownDisplay"): get_node("ShowdownDisplay").queue_free()
	if has_node("HandContainer"): get_node("HandContainer").queue_free()

# ==============================================================================
# BOUTONS UI (ACTIONS JOUEUR)
# ==============================================================================

func _on_btn_miser_pressed():
	var amount = int(bet_input.value)
	
	if amount < current_to_call and amount < my_stack:
		print("Mise invalide : Vous devez au moins suivre.")
		return

	if amount <= my_stack:
		var dealer = get_node("/root/World/Dealer")
		if dealer:
			dealer.server_receive_action.rpc_id(1, "BET", amount)
			action_ui.hide()
		else:
			print("ERREUR : Dealer introuvable dans la scène !")

func _on_btn_coucher_pressed():
	var dealer = get_node("/root/World/Dealer")
	if dealer:
		dealer.server_receive_action.rpc_id(1, "FOLD", 0)
		action_ui.hide()