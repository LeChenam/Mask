extends CharacterBody3D

@export var speed = 5.0
@export var jump_velocity = 4.5
@export var sensitivity = 0.003 

# Vérifie bien que ta hiérarchie est : Player -> Head -> Camera3D
@onready var camera = $Head/Camera3D

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _enter_tree():
	# Définit qui contrôle ce personnage dès son apparition
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	if is_multiplayer_authority():
		# C'est MON personnage
		camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		print("[JOUEUR %s] Local : Contrôles activés." % name)
	else:
		# C'est l'avatar d'un AUTRE joueur sur mon écran
		camera.current = false
		# On désactive le processing pour ne pas gâcher de ressources
		set_physics_process(false)
		set_process_unhandled_input(false)
		print("[JOUEUR %s] Distant : Contrôles désactivés." % name)

func _unhandled_input(event):
	# Sécurité supplémentaire
	if not is_multiplayer_authority(): return

	if event is InputEventMouseMotion:
		# Rotation horizontale (le corps tourne)
		rotate_y(-event.relative.x * sensitivity)
		# Rotation verticale (seule la caméra/tête tourne)
		camera.rotate_x(-event.relative.y * sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority(): return

	# Gravité
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Saut
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# Déplacements ZQSD
	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		# Log de debug précis
		if Engine.get_physics_frames() % 60 == 0: # Log toutes les secondes environ
			print("[JOUEUR %s] Bouge vers %s" % [name, _get_direction_name(input_dir)])
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

func _get_direction_name(dir: Vector2) -> String:
	var res = []
	if dir.y < 0: res.append("Z")
	if dir.y > 0: res.append("S")
	if dir.x < 0: res.append("Q")
	if dir.x > 0: res.append("D")
	return "+".join(res)
