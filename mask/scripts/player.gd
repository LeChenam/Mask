extends CharacterBody3D

@export var speed : float = 5.0 
@export var sensitivity : float = 0.003 

@onready var camera = $Head/Camera3D

func _enter_tree():
	# L'autorité est définie par le nom du node (l'ID réseau envoyé par le serveur)
	set_multiplayer_authority(name.to_int())

func _ready():
	# On récupère les IDs pour le debug
	var my_id = multiplayer.get_unique_id()
	var auth_id = get_multiplayer_authority()
	
	if is_multiplayer_authority():
		# --- LOG JOUEUR LOCAL ---
		print("[MOI-MÊME] Mon ID Réseau: ", my_id, " | Je contrôle ce corps.")
		
		if camera:
			camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		set_physics_process(true)
		set_process_unhandled_input(true)
	else:
		# --- LOG JOUEUR DISTANT ---
		print("[AUTRE] Mon ID: ", my_id, " | Ce corps appartient à l'ID: ", auth_id)
		
		if camera:
			camera.current = false
		set_physics_process(false)
		set_process_unhandled_input(false)

func _unhandled_input(event):
	if not is_multiplayer_authority(): return

	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * sensitivity)
		camera.rotate_x(-event.relative.y * sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))

func _physics_process(delta):
	if not is_multiplayer_authority(): return

	if not is_on_floor():
		velocity.y -= 9.8 * delta

	var current_speed = speed if speed != null else 5.0
	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

func _notification(what):
	if not is_multiplayer_authority(): return

	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		velocity = Vector3.ZERO
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		print("[JOUEUR %s] Focus perdu (Alt-Tab)." % name)
		
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		print("[JOUEUR %s] Focus retrouvé." % name)
