extends Node3D

@onready var action_ui = $UI/ActionButtons
@onready var info_label = $UI/Label_Info
@onready var bet_input = $UI/ActionButtons/HBoxContainer/BetInput
@onready var camera = $Camera3D

func _ready():
	# Définit qui possède ce personnage
	set_multiplayer_authority(name.to_int())

	if is_multiplayer_authority():
		action_ui.hide()
		camera.current = true
		info_label.text = "En attente du début de partie..."
		
		# Connexion des boutons
		$UI/ActionButtons/HBoxContainer/Btn_Miser.pressed.connect(_on_btn_miser_pressed)
		$UI/ActionButtons/HBoxContainer/Btn_Coucher.pressed.connect(_on_btn_coucher_pressed)
	else:
		# On supprime l'UI des autres joueurs pour qu'elle n'apparaisse pas sur notre écran
		$UI.queue_free()

# --- Appelé par le Dealer (Serveur) ---
@rpc("authority", "call_local", "reliable")
func notify_turn(is_my_turn: bool):
	if is_multiplayer_authority():
		action_ui.visible = is_my_turn
		info_label.text = "À VOUS DE JOUER !" if is_my_turn else "Le voisin réfléchit..."

@rpc("authority", "call_remote", "reliable")
func receive_cards(cards: Array):
	print("J'ai reçu mes cartes : ", cards)
	# TODO: Ici tu pourras instancier visuellement les cartes devant le joueur

# --- Envoi vers le Dealer ---
func _on_btn_miser_pressed():
	var amount = int(bet_input.value)
	# Chemin absolu vers le nœud Dealer dans la scène World
	var dealer = get_node("/root/World/Dealer") 
	dealer.server_receive_action.rpc_id(1, "BET", amount)
	action_ui.hide()

func _on_btn_coucher_pressed() -> void:
	var dealer = get_node("/root/World/Dealer")
	dealer.server_receive_action.rpc_id(1, "FOLD", 0)
	action_ui.hide()
