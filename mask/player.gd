extends Node3D

@onready var action_ui = $UI/ActionButtons
@onready var info_label = $UI/Label_Info
@onready var stack_label = $UI/StackLabel
@onready var pot_label = $UI/PotLabel # Assure-toi d'avoir ce Label dans l'UI
@onready var call_label = $UI/ActionButtons/Label_ToCall # Nouveau Label à créer
@onready var bet_input = $UI/ActionButtons/HBoxContainer/BetInput
@onready var camera = $Camera3D

var my_stack = 0
var current_to_call = 0

func _ready():
	set_multiplayer_authority(name.to_int())

	if is_multiplayer_authority():
		action_ui.hide()
		camera.current = true
		info_label.text = "En attente..."
		
		$UI/ActionButtons/HBoxContainer/Btn_Miser.pressed.connect(_on_btn_miser_pressed)
		$UI/ActionButtons/HBoxContainer/Btn_Coucher.pressed.connect(_on_btn_coucher_pressed)
	else:
		$UI.queue_free()

# --- RPC APPELÉS PAR LE DEALER ---

# Correction : Ajout du 2ème argument 'amount_to_call'
@rpc("authority", "call_local", "reliable")
func notify_turn(is_my_turn: bool, amount_to_call: int = 0):
	if not is_multiplayer_authority(): return

	action_ui.visible = is_my_turn
	current_to_call = amount_to_call
	
	if is_my_turn:
		info_label.text = "À VOUS DE JOUER !"
		
		# Logique d'affichage du "Call"
		if amount_to_call > 0:
			call_label.text = "Mise à suivre : " + str(amount_to_call) + "$"
			bet_input.value = amount_to_call # Pré-remplit le montant mini
			bet_input.min_value = amount_to_call
		else:
			call_label.text = "Parole (Check)"
			bet_input.value = 0
			bet_input.min_value = 0
	else:
		info_label.text = "Le voisin réfléchit..."


# Correction : Renommé 'update_stack' pour correspondre au Dealer
@rpc("authority", "call_local", "reliable")
func update_stack(new_amount: int):
	if is_multiplayer_authority():
		my_stack = new_amount
		stack_label.text = "Argent : " + str(my_stack) + "$"
		bet_input.max_value = my_stack

# Correction : Renommé 'update_pot' pour correspondre au Dealer
@rpc("authority", "call_local", "reliable")
func update_pot(amount: int):
	if is_multiplayer_authority():
		pot_label.text = "POT : " + str(amount) + "$"

# --- ACTIONS VERS LE DEALER ---

func _on_btn_miser_pressed():
	var amount = int(bet_input.value)
	
	# Sécurité : On ne peut pas miser moins que le Call, sauf si on fait Tapis
	if amount < current_to_call and amount < my_stack:
		print("Vous devez miser au moins : ", current_to_call)
		return

	if amount <= my_stack:
		var dealer = get_node("/root/World/Dealer")
		dealer.server_receive_action.rpc_id(1, "BET", amount)
		action_ui.hide()

func _on_btn_coucher_pressed():
	var dealer = get_node("/root/World/Dealer")
	dealer.server_receive_action.rpc_id(1, "FOLD", 0)
	action_ui.hide()
	
@rpc("authority", "call_remote", "reliable")
func receive_cards(cards: Array):
	print("Cartes reçues : ", cards)
	
	# Nettoyer les vieilles cartes s'il y en a
	if has_node("HandContainer"): $HandContainer.queue_free()
	
	var hand_node = Node3D.new()
	hand_node.name = "HandContainer"
	add_child(hand_node)
	
	# Positionner les cartes devant la caméra (Ajuste les Vector3 selon ta scène)
	var offsets = [Vector3(-0.5, -0.5, -1.5), Vector3(0.5, -0.5, -1.5)]
	
	for i in range(cards.size()):
		var card_obj = preload("res://card.tscn").instantiate()
		hand_node.add_child(card_obj)
		card_obj.position = offsets[i]
		
		# On applique la texture
		card_obj.set_card_visuals(cards[i])
		
		# On force la face visible pour le joueur local
		card_obj.reveal()
