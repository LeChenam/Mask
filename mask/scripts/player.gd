extends CharacterBody3D 

@export var sensitivity = 0.003
@onready var camera = $Head/Camera3D

var is_local_player = false

func _enter_tree():
	# Définit l'autorité réseau (ID du joueur)
	var player_id = name.to_int()
	set_multiplayer_authority(player_id)
	
	# Vérifier si c'est notre joueur local
	is_local_player = (player_id == multiplayer.get_unique_id())
	print("PLAYER : Spawn du joueur ", player_id, " - Est local: ", is_local_player)

func _ready():
	# Attendre un frame pour que tout soit bien synchronisé
	await get_tree().process_frame
	
	if is_local_player:
		# C'est MON perso
		print("PLAYER : Configuration de MON personnage (ID ", multiplayer.get_unique_id(), ")")
		if camera: 
			camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		# C'est le perso d'un AUTRE
		print("PLAYER : Personnage d'un autre joueur détecté")
		if camera: 
			camera.current = false
		set_physics_process(false)
		set_process_unhandled_input(false)

func _unhandled_input(event):
	if not is_local_player: return
	
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * sensitivity)
		camera.rotate_x(-event.relative.y * sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))
