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
