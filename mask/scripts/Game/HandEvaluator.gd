class_name HandEvaluator

# Convertit l'ID (0-51) en Rangs (2-14) et Couleurs (0-3)
static func get_card_data(card_id):
	var rank = (card_id % 13) + 2 
	var suit = card_id / 13      
	return {"rank": rank, "suit": suit}

static func evaluate(hole_cards, community_cards):
	var all_cards = hole_cards + community_cards
	var ranks = []
	var suits = []
	
	for c in all_cards:
		var data = get_card_data(c)
		ranks.append(data.rank)
		suits.append(data.suit)
	
	ranks.sort()
	ranks.reverse() 
	
	var flush_suit = get_flush_suit(suits)
	var is_straight = check_straight(ranks)
	var counts = get_rank_counts(ranks)
	
	# Vérifications hiérarchiques
	if flush_suit != -1 and is_straight: return 9000 + ranks[0] # Quinte Flush
	if counts.values().has(4): return 8000 + get_key_by_value(counts, 4) # Carré
	if counts.values().has(3) and counts.values().has(2): return 7000 + (get_key_by_value(counts, 3) * 10) # Full
	if flush_suit != -1: return 6000 # Couleur
	if is_straight: return 5000 + ranks[0] # Suite
	if counts.values().has(3): return 4000 + get_key_by_value(counts, 3) # Brelan
	if counts.values().count(2) >= 2: return 3000 # Double Paire
	if counts.values().has(2): return 2000 + get_key_by_value(counts, 2) # Paire
	
	return ranks[0] # Carte Haute

static func get_flush_suit(suits):
	for s in range(4):
		if suits.count(s) >= 5: return s
	return -1

static func check_straight(ranks):
	var unique_ranks = []
	for r in ranks: if not unique_ranks.has(r): unique_ranks.append(r)
	if unique_ranks.size() < 5: return false
	for i in range(unique_ranks.size() - 4):
		if unique_ranks[i] - unique_ranks[i+4] == 4: return true
	return false

static func get_rank_counts(ranks):
	var counts = {}
	for r in ranks: counts[r] = counts.get(r, 0) + 1
	return counts

static func get_key_by_value(dict, target):
	for k in dict: if dict[k] == target: return k
	return 0
