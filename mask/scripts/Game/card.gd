extends Node3D
# ============================================================================
# CARD - Affichage visuel d'une carte de poker avec support des masques
# ============================================================================

# Signaux pour l'interaction avec les cartes masquées
signal mask_effect_activated(card_id: int)
signal mask_hovered(card_id: int, is_hovering: bool)

# Mesh pour la face et le dos
var mesh_face: MeshInstance3D
var mesh_dos: MeshInstance3D
var collision_area: Area3D

# Mapping des couleurs (suit)
# deck index / 13 = suit: 0=pique, 1=coeur, 2=carreau, 3=trefle
const SUIT_FOLDERS = ["pique", "coeur", "carreau", "trefle"]
const SUIT_PREFIXES = ["pique", "coeurs", "carreau", "trefle"]

# Mapping des rangs (2-14 devient nom de fichier)
# deck index % 13 = rang: 0=2, 1=3, ..., 8=10, 9=V, 10=D, 11=R, 12=A
const RANK_NAMES = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "valet", "reine", "roi", "as"]
const FACE_CARD_RANK_NAMES = ["valet", "reine", "roi"]

var card_id: int = -1
var is_face_up: bool = false

# ============================================================================
# SYSTÈME DE MASQUES
# ============================================================================
var is_masked: bool = false          # Cette carte a-t-elle un masque ?
var is_in_hand: bool = false         # Carte dans la main du joueur (vs table)
var effect_used: bool = false        # L'effet a-t-il déjà été utilisé ?
var is_interactive: bool = false     # Peut-on cliquer sur cette carte ?
var is_hovered: bool = false         # Souris au-dessus ?

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

func _create_collision_area():
	"""Crée la zone de collision pour détecter les clics/hover sur la carte"""
	if collision_area:
		return
	
	collision_area = Area3D.new()
	collision_area.name = "ClickArea"
	
	# IMPORTANT: Activer la détection des rayons de souris
	collision_area.input_ray_pickable = true
	collision_area.monitoring = true
	collision_area.monitorable = true
	
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(0.7, 1.0, 0.1)  # Taille de la carte
	collision_shape.shape = box_shape
	
	collision_area.add_child(collision_shape)
	add_child(collision_area)
	
	# Connecter les signaux
	collision_area.mouse_entered.connect(_on_mouse_entered)
	collision_area.mouse_exited.connect(_on_mouse_exited)
	collision_area.input_event.connect(_on_input_event)
	
	print("🎯 Zone de clic créée pour carte masquée ID: ", card_id)

# ============================================================================
# CONFIGURATION DE LA CARTE
# ============================================================================

func set_card_visuals(id: int, masked: bool = false):
	"""Configure l'apparence de la carte selon son ID (0-51)"""
	card_id = id
	is_masked = masked
	
	# S'assurer que les mesh existent
	if not mesh_face or not mesh_dos:
		_create_card_meshes()
	
	var rank_index: int = id % 13             # 0-12
	var suit_index: int = int(float(id) / 13) # 0-3 (division explicite)
	
	var suit_folder = SUIT_FOLDERS[suit_index]
	var suit_prefix = SUIT_PREFIXES[suit_index]
	var rank_name = RANK_NAMES[rank_index]
	
	# Construire le chemin vers la texture
	var texture_path: String
	if masked and _is_face_card(rank_index):
		# Utiliser la texture masquée
		var face_rank_name = FACE_CARD_RANK_NAMES[rank_index - 9]
		texture_path = "res://assets/cartes_sprite/" + suit_folder + "/" + suit_prefix + "_" + face_rank_name + "_masque.png"
		print("🎭 Carte MASQUÉE: ", texture_path)
	else:
		texture_path = "res://assets/cartes_sprite/" + suit_folder + "/" + suit_prefix + "_" + rank_name + ".png"
	
	# Charger la texture
	var texture = load(texture_path) as Texture2D
	if texture:
		_apply_face_texture(texture)
		print("🃏 Carte chargée: ", texture_path)
	else:
		print("❌ Texture non trouvée: ", texture_path)
		_apply_fallback_material()

func _is_face_card(rank_index: int) -> bool:
	"""Vérifie si le rang correspond à une carte tête (V, D, R)"""
	return rank_index >= 9 and rank_index <= 11

func set_as_hand_card(interactive: bool = true):
	"""Configure cette carte comme une carte en main (interactive)"""
	is_in_hand = true
	is_interactive = interactive and is_masked
	
	if is_interactive:
		_create_collision_area()

func set_as_table_card():
	"""Configure cette carte comme une carte de table (non interactive)"""
	is_in_hand = false
	is_interactive = false

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

# ============================================================================
# VISIBILITÉ
# ============================================================================

func reveal():
	"""Révèle la face de la carte"""
	is_face_up = true
	if mesh_face:
		mesh_face.visible = true
	if mesh_dos:
		mesh_dos.visible = false
	print("🃏 Carte révélée (ID: ", card_id, ", Masquée: ", is_masked, ")")

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

# ============================================================================
# INTERACTION SOURIS (pour cartes masquées en main)
# ============================================================================

func _on_mouse_entered():
	"""Appelé quand la souris survole la carte"""
	if not is_interactive or not is_masked:
		return
	
	is_hovered = true
	mask_hovered.emit(card_id, true)
	
	# Effet visuel de survol - légère élévation
	var tween = create_tween()
	tween.tween_property(self, "position:y", position.y + 0.05, 0.1)

func _on_mouse_exited():
	"""Appelé quand la souris quitte la carte"""
	if not is_interactive:
		return
	
	is_hovered = false
	mask_hovered.emit(card_id, false)
	
	# Revenir à la position normale
	var tween = create_tween()
	tween.tween_property(self, "position:y", position.y - 0.05, 0.1)

func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int):
	"""Gère les clics sur la carte"""
	if not is_interactive or not is_masked or effect_used:
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_activate_mask_effect()

func _activate_mask_effect():
	"""Active l'effet du masque de cette carte"""
	if effect_used:
		print("⚠ Effet déjà utilisé pour cette carte")
		return
	
	print("🎭 ACTIVATION de l'effet masque - Carte ID: ", card_id)
	effect_used = true
	mask_effect_activated.emit(card_id)
	
	# Effet visuel d'activation
	_play_activation_effect()

func _play_activation_effect():
	"""Joue un effet visuel lors de l'activation du masque"""
	# Flash lumineux
	var tween = create_tween()
	if mesh_face and mesh_face.material_override:
		var original_material = mesh_face.material_override.duplicate()
		var flash_material = StandardMaterial3D.new()
		flash_material.emission_enabled = true
		flash_material.emission = Color(1.0, 0.2, 0.2)  # Rouge sinistre
		flash_material.emission_energy_multiplier = 2.0
		
		mesh_face.material_override = flash_material
		tween.tween_callback(func(): mesh_face.material_override = original_material).set_delay(0.3)

# ============================================================================
# INFORMATIONS SUR LE MASQUE
# ============================================================================

func get_mask_info() -> Dictionary:
	"""Retourne les informations du masque si la carte est masquée"""
	if not is_masked:
		return {}
	
	# Utiliser MaskEffects si disponible
	if ClassDB.class_exists("MaskEffects"):
		return MaskEffects.get_face_card_info(card_id)
	
	# Fallback simple
	var rank_index = card_id % 13
	var suit_index = int(float(card_id) / 13)
	var is_red = suit_index == 1 or suit_index == 2
	
	return {
		"is_head": true,
		"is_red": is_red,
		"rank": rank_index - 9
	}

func can_activate_effect() -> bool:
	"""Vérifie si l'effet peut être activé"""
	return is_masked and is_in_hand and not effect_used and is_interactive
