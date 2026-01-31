extends Node3D

func _enter_tree():
	# Cette fonction se lance AVANT le _ready
	# On définit qui est le propriétaire de ce bonhomme
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	# Si ce bonhomme est À MOI (Local Player)
	if is_multiplayer_authority():
		print("PLAYER: C'est mon personnage ! (ID: " + name + ")")
		# Active la caméra ici si tu en as une
		if has_node("Camera3D"):
			$Camera3D.current = true
	else:
		print("PLAYER: C'est le personnage d'un autre. (ID: " + name + ")")
		# Désactive la caméra des autres pour pas voir à travers leurs yeux
		if has_node("Camera3D"):
			$Camera3D.current = false

@rpc("call_local")
func notify_turn(is_my_turn: bool):
	if not is_multiplayer_authority(): return

	if is_my_turn:
		print("C'EST A MOI DE JOUER !")
		# Affiche tes boutons UI ici (Miser, Coucher)
		# $CanvasLayer/ButtonContainer.show()
	else:
		print("J'attends mon tour...")
		# $CanvasLayer/ButtonContainer.hide()

# Fonctions à connecter à tes boutons d'interface
func _on_btn_miser_pressed():
	# On envoie l'action au serveur
	rpc_id(1, "server_receive_bet", 100) 

func _on_btn_coucher_pressed():
	rpc_id(1, "server_receive_fold")

# --- Actions reçues par le Serveur (définies ici pour simplifier) ---

@rpc("any_peer", "call_local")
func server_receive_bet(amount):
	if not multiplayer.is_server(): return
	print("Le joueur " + name + " veut miser " + str(amount))
	# Ici, vérifie l'argent, ajoute au pot, puis :
	#get_parent().get_parent().next_turn() # Retour au World pour passer la main

@rpc("any_peer", "call_local")
func server_receive_fold():
	if not multiplayer.is_server(): return
	print("Le joueur " + name + " se couche.")
	# Gérer le fold...
