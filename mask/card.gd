extends Area3D

# Synchronisé via le MultiplayerSynchronizer
@export var card_id : int = 0 :
	set(value):
		card_id = value
		update_visuals()

func _ready():
	# Force la mise à jour visuelle à l'apparition
	update_visuals()

func update_visuals():
	# LOGIQUE TEMPORAIRE GAME JAM (Pour tester sans textures)
	# Si c'est MA carte (j'ai l'autorité) -> Je la vois en VERT
	# Si c'est celle d'un autre -> Je la vois en ROUGE (Dos)
	# Si c'est une carte commune (Autorité Serveur) -> Tout le monde la voit (BLEU)
	
	var mesh = $MeshInstance3D # Assure-toi d'avoir un Mesh
	if not mesh: return
	
	var mat = StandardMaterial3D.new()
	
	if is_multiplayer_authority():
		mat.albedo_color = Color.GREEN
		# Plus tard : mat.albedo_texture = load("res://cards/" + str(card_id) + ".png")
	elif name.begins_with("Board"): # Carte au milieu
		mat.albedo_color = Color.BLUE
	else:
		mat.albedo_color = Color.RED # Dos de carte
		
	mesh.material_override = mat
