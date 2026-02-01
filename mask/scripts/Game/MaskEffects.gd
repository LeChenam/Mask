class_name MaskEffects
# ============================================================================
# MASK EFFECTS - Système central des masques pour MASKARD
# ============================================================================
# Ce script contient toutes les définitions des masques et leurs effets

# ============================================================================
# CONSTANTES DE JEU
# ============================================================================

const MASK_PROBABILITY = 0.33  # 33% chance qu'une tête soit masquée
const STEAL_AMOUNT = 50        # Jetons volés par la Dame Rouge
const MASK_SHOP_COST = 100     # Coût d'un masque dans le shop
const BLIND_MULTIPLIER = 1.5   # Multiplicateur des blinds par tour

# Cartes de tête : indices dans RANK_NAMES
const FACE_CARD_RANKS = [9, 10, 11]  # Valet=9, Dame=10, Roi=11 (0-indexed)

# Couleurs de carte : 0=pique(noir), 1=coeur(rouge), 2=carreau(rouge), 3=trefle(noir)
const RED_SUITS = [1, 2]    # coeur, carreau
const BLACK_SUITS = [0, 3]  # pique, trefle

# Noms pour les fichiers de texture
const SUIT_FOLDERS = ["pique", "coeur", "carreau", "trefle"]
const SUIT_PREFIXES = ["pique", "coeurs", "carreau", "trefle"]
const RANK_MASKED_NAMES = ["valet", "reine", "roi"]  # Pour les fichiers _masque

# ============================================================================
# ENUMS - Types de masques
# ============================================================================

enum HeadCardColor { RED, BLACK }
enum HeadCardRank { JACK, QUEEN, KING }  # 0, 1, 2

enum PlayerMask {
	NONE = 0,
	CORBEAU = 1,   # +30% chance de cartes têtes
	VOILE = 2,     # Bloque le premier effet ciblé
	AFFAME = 3     # Effets marchent même si fold
}

enum DealerMask {
	NONE = 0,
	USURIER = 1,   # Toutes les mises doublées
	GEOLIER = 2,   # Impossible de se coucher
	AVEUGLE = 3    # Cartes communes cachées
}

# ============================================================================
# DÉTECTION DES CARTES TÊTES
# ============================================================================

static func is_face_card(card_id: int) -> bool:
	"""Vérifie si une carte est une tête (J, Q, K)"""
	var rank_index = card_id % 13
	return rank_index in FACE_CARD_RANKS

static func get_face_card_info(card_id: int) -> Dictionary:
	"""Retourne les infos de masque pour une carte tête, ou vide si pas tête"""
	var rank_index = card_id % 13
	var suit_index = int(float(card_id) / 13)
	
	if rank_index not in FACE_CARD_RANKS:
		return {}
	
	var is_red = suit_index in RED_SUITS
	var rank_type = rank_index - 9  # 0=Valet, 1=Dame, 2=Roi
	
	return {
		"is_head": true,
		"color": HeadCardColor.RED if is_red else HeadCardColor.BLACK,
		"rank": rank_type,
		"suit_index": suit_index,
		"name": _get_mask_name(is_red, rank_type),
		"hand_effect": _get_hand_effect_description(is_red, rank_type),
		"table_effect": _get_table_effect_description(is_red, rank_type)
	}

static func should_card_be_masked() -> bool:
	"""Détermine si une carte tête doit être masquée (33% de chance)"""
	return randf() < MASK_PROBABILITY

static func get_masked_texture_path(card_id: int) -> String:
	"""Retourne le chemin de la texture masquée pour une carte tête"""
	var rank_index = card_id % 13
	var suit_index = int(float(card_id) / 13)
	
	if rank_index not in FACE_CARD_RANKS:
		return ""
	
	var suit_folder = SUIT_FOLDERS[suit_index]
	var suit_prefix = SUIT_PREFIXES[suit_index]
	var rank_name = RANK_MASKED_NAMES[rank_index - 9]
	
	return "res://assets/cartes_sprite/" + suit_folder + "/" + suit_prefix + "_" + rank_name + "_masque.png"

# ============================================================================
# NOMS DES MASQUES (en anglais stylisé)
# ============================================================================

static func _get_mask_name(is_red: bool, rank_type: int) -> String:
	if is_red:
		match rank_type:
			HeadCardRank.JACK: return "The Observer"
			HeadCardRank.QUEEN: return "The Parasite"
			HeadCardRank.KING: return "The Corrupt Banker"
	else:
		match rank_type:
			HeadCardRank.JACK: return "The Trickster"
			HeadCardRank.QUEEN: return "The Inquisitor"
			HeadCardRank.KING: return "The Void"
	return "Unknown"

# ============================================================================
# DESCRIPTIONS DES EFFETS DEPUIS LA MAIN
# ============================================================================

static func _get_hand_effect_description(is_red: bool, rank_type: int) -> String:
	if is_red:
		match rank_type:
			HeadCardRank.JACK:
				return "Choose a player - inspect one of their cards. 'I see you...'"
			HeadCardRank.QUEEN:
				return "Steal " + str(STEAL_AMOUNT) + " chips from a chosen player."
			HeadCardRank.KING:
				return "Force a pact: share gains equally. If they fold: -50% bet. If you fold: -100% bet."
	else:
		match rank_type:
			HeadCardRank.JACK:
				return "Exchange one of your cards with a random card from the deck."
			HeadCardRank.QUEEN:
				return "Force a player to reveal their highest card."
			HeadCardRank.KING:
				return "Blind a random player - they cannot see the community cards."
	return ""

# ============================================================================
# DESCRIPTIONS DES EFFETS DEPUIS LA TABLE
# ============================================================================

static func _get_table_effect_description(is_red: bool, rank_type: int) -> String:
	if is_red:
		match rank_type:
			HeadCardRank.JACK:
				return "Partial revelation - Each player must show one card of their choice."
			HeadCardRank.QUEEN:
				return "Transfusion - Richest player gives " + str(STEAL_AMOUNT) + " to poorest at round end."
			HeadCardRank.KING:
				return "Poisoned pot - Every player must bet half their current bet again."
	else:
		match rank_type:
			HeadCardRank.JACK:
				return "Minor chaos - A random table card is replaced by a new one."
			HeadCardRank.QUEEN:
				return "Tribunal - No folding allowed, 50 chip minimum per action."
			HeadCardRank.KING:
				return "Absolute darkness - Screens dim, timer reduced, sounds distorted."
	return ""

# ============================================================================
# MASQUES DU SHOP JOUEUR
# ============================================================================

static func get_player_mask_info(mask: PlayerMask) -> Dictionary:
	match mask:
		PlayerMask.CORBEAU:
			return {
				"name": "Masque du Corbeau",
				"name_en": "Raven Mask",
				"description": "+30% chance to receive face cards in your starting hand.",
				"description_fr": "+30% de chances de recevoir des cartes têtes.",
				"cost": MASK_SHOP_COST,
				"visual": "Black beak mask, falling feathers"
			}
		PlayerMask.VOILE:
			return {
				"name": "Le Masque Voilé",
				"name_en": "The Veiled Mask",
				"description": "The first face card effect that targets you has no effect.",
				"description_fr": "Le premier effet de tête qui te cible n'a pas d'effet.",
				"cost": MASK_SHOP_COST,
				"visual": "Black smoke veil, whisper 'Not this time...'"
			}
		PlayerMask.AFFAME:
			return {
				"name": "Le Masque Affamé",
				"name_en": "The Hungry Mask",
				"description": "Your face card effects can be activated even if you fold.",
				"description_fr": "Tes effets de têtes marchent même si tu te couches.",
				"cost": MASK_SHOP_COST,
				"visual": "Sharp teeth, heavy breathing, 'Still hungry...'"
			}
	return {}

static func get_available_shop_masks(last_mask: PlayerMask) -> Array:
	"""Retourne les masques disponibles (exclut le dernier acheté)"""
	var masks = [PlayerMask.CORBEAU, PlayerMask.VOILE, PlayerMask.AFFAME]
	if last_mask != PlayerMask.NONE:
		masks.erase(last_mask)
	return masks

# ============================================================================
# MASQUES DU CROUPIER
# ============================================================================

static func get_dealer_mask_info(mask: DealerMask) -> Dictionary:
	match mask:
		DealerMask.USURIER:
			return {
				"name": "Le Masque de l'Usurier",
				"name_en": "The Usurer's Mask",
				"description": "All bets are DOUBLED. Minimum bet x2, raises x2.",
				"description_fr": "Toutes les mises sont DOUBLÉES.",
				"announcement": "Money calls for money...",
				"visual": "Long fingers counting coins, greedy smile"
			}
		DealerMask.GEOLIER:
			return {
				"name": "Le Masque du Geôlier",
				"name_en": "The Jailer's Mask",
				"description": "IMPOSSIBLE to fold. All players must see every raise.",
				"description_fr": "IMPOSSIBLE de se coucher.",
				"announcement": "Nobody leaves...",
				"visual": "Chains on interface, bloody padlock replaces fold button"
			}
		DealerMask.AVEUGLE:
			return {
				"name": "Le Masque de l'Aveugle",
				"name_en": "The Blind's Mask",
				"description": "Community cards are face-down. Play with your hand only.",
				"description_fr": "Les cartes communes sont cachées.",
				"announcement": "If I cannot see, neither can you...",
				"visual": "Sewn eyes, pulsing black rectangles"
			}
	return {}

static func select_random_dealer_mask() -> DealerMask:
	"""Sélectionne un masque de croupier au hasard (25% chaque + 25% aucun)"""
	return [DealerMask.NONE, DealerMask.USURIER, DealerMask.GEOLIER, DealerMask.AVEUGLE].pick_random()
