extends Node3D
# ============================================================================
# CARD - Affichage visuel d'une carte de poker
# ============================================================================

# Mesh pour la face et le dos
var mesh_face: MeshInstance3D
var mesh_dos: MeshInstance3D

# Mapping des couleurs (suit)
# deck index / 13 = suit: 0=pique, 1=coeur, 2=carreau, 3=trefle
const SUIT_FOLDERS = ["pique", "coeur", "carreau", "trefle"]
const SUIT_PREFIXES = ["pique", "coeurs", "carreau", "trefle"]

# Mapping des rangs (2-14 devient nom de fichier)
# deck index % 13 = rang: 0=2, 1=3, ..., 8=10, 9=V, 10=D, 11=R, 12=A
const RANK_NAMES = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "valet", "reine", "roi", "as"]

var card_id: int = -1
var is_face_up: bool = false

func _ready():
	# Récupérer les mesh existants de la scène
	if has_node("MeshFace"):
		mesh_face = $MeshFace
	if has_node("MeshDos"):
		mesh_dos = $MeshDos
	
	# Créer les mesh si pas présents
	if not mesh_face or not mesh_dos:
		_create_card_meshes()
	
	# Par défaut : montrer le dos
	hide_face()

func _create_card_meshes():
	"""Crée les mesh de la carte (face et dos) en utilisant QuadMesh pour les textures"""
	
	# Face de la carte (QuadMesh pour texture 2D)
	if not mesh_face:
		var face = MeshInstance3D.new()
		face.name = "MeshFace"
		var quad = QuadMesh.new()
		quad.size = Vector2(0.7, 1.0)  # Ratio carte de poker (7:10)
		face.mesh = quad
		face.position = Vector3(0, 0, 0.005)  # Légèrement devant
		add_child(face)
		mesh_face = face
		
		# Matériau blanc par défaut
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.WHITE
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_face.material_override = mat
	
	# Dos de la carte
	if not mesh_dos:
		var dos = MeshInstance3D.new()
		dos.name = "MeshDos"
		var quad = QuadMesh.new()
		quad.size = Vector2(0.7, 1.0)
		dos.mesh = quad
		dos.position = Vector3(0, 0, -0.005)  # Légèrement derrière
		dos.rotation_degrees.y = 180  # Tourner pour faire face à l'autre côté
		add_child(dos)
		mesh_dos = dos
		
		# Matériau bleu pour le dos
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.1, 0.6)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_dos.material_override = mat

func set_card_visuals(id: int):
	"""Configure l'apparence de la carte selon son ID (0-51)"""
	card_id = id
	
	# S'assurer que les mesh existent
	if not mesh_face or not mesh_dos:
		_create_card_meshes()
	
	var rank_index: int = id % 13             # 0-12
	var suit_index: int = int(float(id) / 13) # 0-3 (division explicite)
	
	var suit_folder = SUIT_FOLDERS[suit_index]
	var suit_prefix = SUIT_PREFIXES[suit_index]
	var rank_name = RANK_NAMES[rank_index]
	
	# Construire le chemin vers la texture
	var texture_path = "res://assets/cartes_sprite/" + suit_folder + "/" + suit_prefix + "_" + rank_name + ".png"
	
	# Charger la texture
	var texture = load(texture_path) as Texture2D
	if texture:
		_apply_face_texture(texture)
		print("🃏 Carte chargée: ", texture_path)
	else:
		print("❌ Texture non trouvée: ", texture_path)
		_apply_fallback_material()

func _apply_face_texture(texture: Texture2D):
	"""Applique la texture sur la face de la carte"""
	if not mesh_face:
		return
	
	var material = StandardMaterial3D.new()
	material.albedo_texture = texture
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_face.material_override = material

func _apply_fallback_material():
	"""Applique un matériau de secours si la texture n'est pas trouvée"""
	if not mesh_face:
		return
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_face.material_override = material

func reveal():
	"""Révèle la face de la carte"""
	is_face_up = true
	if mesh_face:
		mesh_face.visible = true
	if mesh_dos:
		mesh_dos.visible = false
	print("🃏 Carte révélée (ID: ", card_id, ")")

func hide_face():
	"""Cache la face de la carte (montre le dos)"""
	is_face_up = false
	if mesh_face:
		mesh_face.visible = false
	if mesh_dos:
		mesh_dos.visible = true

func flip():
	"""Retourne la carte"""
	if is_face_up:
		hide_face()
	else:
		reveal()
