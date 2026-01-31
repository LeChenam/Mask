extends CharacterBody3D  # <--- C'EST CETTE LIGNE QUI EST CRUCIALE

@export var speed = 5.0
@export var sensitivity = 0.003
@onready var camera = $Head/Camera3D

func _enter_tree():
	# Définit l'autorité réseau (ID du joueur)
	set_multiplayer_authority(name.to_int())

func _ready():
	if is_multiplayer_authority():
		# C'est MON perso
		if camera: camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		# C'est le perso d'un AUTRE
		if camera: camera.current = false
		set_physics_process(false)
		set_process_unhandled_input(false)

func _unhandled_input(event):
	if not is_multiplayer_authority(): return
	
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * sensitivity)
		camera.rotate_x(-event.relative.y * sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))

func _physics_process(delta):
	# Pas besoin de re-vérifier is_multiplayer_authority() ici 
	# car on a coupé le physics_process dans le _ready() pour les autres.
	
	# C'est ici que tu avais l'erreur. 
	# Cela ne marche que si "extends CharacterBody3D" est présent en haut.
	if not is_on_floor():
		velocity.y -= 9.8 * delta

	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
