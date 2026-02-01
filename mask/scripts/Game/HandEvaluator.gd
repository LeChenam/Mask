class_name HandEvaluator

# Convertit l'ID (0-51) en Rangs (2-14) et Couleurs (0-3)
# Rang: 2=2, 3=3, ..., 10=10, J=11, Q=12, K=13, A=14
# Couleur: 0=Pique, 1=Coeur, 2=Carreau, 3=Trèfle
static func get_card_data(card_id):
	var rank = (card_id % 13) + 2 
	var suit = card_id / 13      
	return {"rank": rank, "suit": suit}

static func evaluate(hole_cards, community_cards):
	var all_cards = hole_cards + community_cards
	var cards_data = []
	
	for c in all_cards:
		cards_data.append(get_card_data(c))
	
	# Trouver la meilleure combinaison de 5 cartes parmi les 7
	var best_score = 0
	var combinations = get_combinations(cards_data, 5)
	
	for combo in combinations:
		var score = evaluate_five_cards(combo)
		if score > best_score:
			best_score = score
	
	return best_score

static func evaluate_five_cards(cards: Array) -> int:
	var ranks = []
	var suits = []
	
	for c in cards:
		ranks.append(c.rank)
		suits.append(c.suit)
	
	ranks.sort()
	ranks.reverse()  # Du plus grand au plus petit
	
	var is_flush = check_flush(suits)
	var straight_high = check_straight(ranks)
	var counts = get_rank_counts(ranks)
	
	# Quinte Flush Royale (A-K-Q-J-10 même couleur)
	if is_flush and straight_high == 14:
		return 10000 + 14  # Score max
	
	# Quinte Flush
	if is_flush and straight_high > 0:
		return 9000 + straight_high
	
	# Carré
	var four_kind = get_n_of_a_kind(counts, 4)
	if four_kind > 0:
		var kicker = get_highest_kicker(ranks, [four_kind])
		return 8000 + four_kind * 15 + kicker
	
	# Full (Brelan + Paire)
	var three_kind = get_n_of_a_kind(counts, 3)
	var pair = get_n_of_a_kind(counts, 2)
	if three_kind > 0 and pair > 0:
		return 7000 + three_kind * 15 + pair
	
	# Couleur
	if is_flush:
		return 6000 + ranks[0] * 15 + ranks[1]
	
	# Suite
	if straight_high > 0:
		return 5000 + straight_high
	
	# Brelan
	if three_kind > 0:
		var kickers = get_kickers(ranks, [three_kind], 2)
		return 4000 + three_kind * 225 + kickers[0] * 15 + kickers[1]
	
	# Double Paire
	var pairs = get_all_pairs(counts)
	if pairs.size() >= 2:
		pairs.sort()
		pairs.reverse()
		var kicker = get_highest_kicker(ranks, [pairs[0], pairs[1]])
		return 3000 + pairs[0] * 225 + pairs[1] * 15 + kicker
	
	# Paire
	if pair > 0:
		var kickers = get_kickers(ranks, [pair], 3)
		return 2000 + pair * 3375 + kickers[0] * 225 + kickers[1] * 15 + kickers[2]
	
	# Carte Haute
	return 1000 + ranks[0] * 3375 + ranks[1] * 225 + ranks[2] * 15 + ranks[3]

static func check_flush(suits: Array) -> bool:
	return suits.count(suits[0]) == 5

static func check_straight(ranks: Array) -> int:
	# Vérifier suite normale
	var unique = []
	for r in ranks:
		if not unique.has(r):
			unique.append(r)
	
	if unique.size() < 5:
		return 0
	
	unique.sort()
	unique.reverse()
	
	# Suite normale (ex: 10-9-8-7-6)
	if unique[0] - unique[4] == 4:
		return unique[0]
	
	# Suite basse avec As (A-2-3-4-5 = "Wheel")
	if unique[0] == 14 and unique[1] == 5 and unique[2] == 4 and unique[3] == 3 and unique[4] == 2:
		return 5  # Le 5 est la carte haute dans cette suite
	
	return 0

static func get_rank_counts(ranks: Array) -> Dictionary:
	var counts = {}
	for r in ranks:
		counts[r] = counts.get(r, 0) + 1
	return counts

static func get_n_of_a_kind(counts: Dictionary, n: int) -> int:
	var best = 0
	for rank in counts:
		if counts[rank] == n and rank > best:
			best = rank
	return best

static func get_all_pairs(counts: Dictionary) -> Array:
	var pairs = []
	for rank in counts:
		if counts[rank] == 2:
			pairs.append(rank)
	return pairs

static func get_highest_kicker(ranks: Array, exclude: Array) -> int:
	for r in ranks:
		if not exclude.has(r):
			return r
	return 0

static func get_kickers(ranks: Array, exclude: Array, count: int) -> Array:
	var kickers = []
	for r in ranks:
		if not exclude.has(r) and kickers.size() < count:
			kickers.append(r)
	while kickers.size() < count:
		kickers.append(0)
	return kickers

# Génère toutes les combinaisons de n éléments
static func get_combinations(arr: Array, n: int) -> Array:
	if n == 0:
		return [[]]
	if arr.size() < n:
		return []
	
	var result = []
	_combinations_helper(arr, n, 0, [], result)
	return result

static func _combinations_helper(arr: Array, n: int, start: int, current: Array, result: Array):
	if current.size() == n:
		result.append(current.duplicate())
		return
	
	for i in range(start, arr.size()):
		current.append(arr[i])
		_combinations_helper(arr, n, i + 1, current, result)
		current.pop_back()
