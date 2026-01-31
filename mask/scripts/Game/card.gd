extends Area3D

# ============================================================================
# CARD - Script pour les visuels des cartes
# ============================================================================

@onready var mesh_face = $MeshFace
@onready var mesh_dos = $MeshDos

var card_id: int = -1
var is_revealed: bool = false

# Noms des couleurs (suits)
const SUIT_NAMES = ["hearts", "diamonds", "clubs", "spades"]
const RANK_NAMES = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]

func _ready():
	# Par défaut, la carte est cachée (dos visible)
	if mesh_face:
		mesh_face.visible = false
	if mesh_dos:
		mesh_dos.visible = true

func set_card_visuals(id: int):
	"""Configure les visuels de la carte selon son ID (0-51)"""
	card_id = id
	
	var rank: int = id % 13  # 0-12 (2 à As)
	var suit: int = int(id / 13)  # 0-3 (Coeur, Carreau, Trèfle, Pique)
	
	var rank_name = RANK_NAMES[rank]
	var suit_name = SUIT_NAMES[suit]
	
	print("CARD : Configuration de la carte ", rank_name, " de ", suit_name)
	
	# Charger la texture de la carte si elle existe
	var texture_path = "res://assets/cards/" + suit_name + "_" + rank_name + ".png"
	var texture = load(texture_path)
	
	if texture and mesh_face:
		# Créer un material avec la texture
		var material = StandardMaterial3D.new()
		material.albedo_texture = texture
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_face.material_override = material
	else:
		# Fallback : créer une texture de couleur simple avec le nom
		create_fallback_visual(rank_name, suit_name, suit)

func create_fallback_visual(_rank: String, _suit_name: String, _suit_index: int):
	"""Crée un visuel de fallback si les textures n'existent pas"""
	if not mesh_face:
		return
	
	# Couleurs selon la couleur de la carte (non utilisé pour l'instant)
	# var suit_colors = [Color.RED, Color.RED, Color.BLACK, Color.BLACK]
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	mesh_face.material_override = material
	
	# On pourrait ajouter un Label3D pour afficher le rang/couleur
	# mais pour l'instant on utilise juste la couleur de base

func reveal():
	"""Révèle la carte (face visible)"""
	is_revealed = true
	if mesh_face:
		mesh_face.visible = true
	if mesh_dos:
		mesh_dos.visible = false

func hide_card():
	"""Cache la carte (dos visible)"""
	is_revealed = false
	if mesh_face:
		mesh_face.visible = false
	if mesh_dos:
		mesh_dos.visible = true

func get_card_name() -> String:
	"""Retourne le nom lisible de la carte"""
	if card_id < 0:
		return "Unknown"
	
	var rank: int = card_id % 13
	var suit: int = int(card_id / 13)
	
	return RANK_NAMES[rank] + " of " + SUIT_NAMES[suit]
