extends Node3D

@onready var face_mesh = $MeshInstance3D # Le devant de la carte
@onready var back_mesh = $MeshInstance3D_Back # Le dos (rouge/bleu)

# Fonction appelée par Player.gd ou Dealer.gd
func set_card_visuals(card_id: int):
	# Exemple de logique pour trouver le fichier
	# ID 0 = 2 de Trèfle, etc.
	var rank = (card_id % 13) + 2
	var suit_id = card_id / 13
	var suit_name = ["Clubs", "Diamonds", "Hearts", "Spades"][suit_id]
	
	var texture_path = "res://Assets/Cards/card_" + suit_name + "_" + str(rank) + ".png"
	
	# Appliquer la texture au matériel du Mesh
	var material = StandardMaterial3D.new()
	material.albedo_texture = load(texture_path)
	face_mesh.material_override = material

func reveal():
	# Animation pour retourner la carte
	var tween = create_tween()
	tween.tween_property(self, "rotation:x", 0.0, 0.5) # Face visible

func hide_card():
	rotation.x = deg_to_rad(180) # Face cachée
