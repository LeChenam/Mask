extends Node

# --- BIBLIOTHÈQUE DE SONS ---
const SOUNDS = {
	# MUSIQUES
	"base_music": preload("res://assets/audio/music/base_horror_music.mp3"),
	"ambiance_loop": preload("res://assets/audio/music/scary_ambiance.mp3"),
	
	# Ambiances POP
	"creepy_whisper": preload("res://assets/audio/sfx/creepy-whisper.wav"),
	"footstep": preload("res://assets/audio/sfx/footstep.wav"),
	"gougougaga": preload("res://assets/audio/sfx/gougougaga.wav"),
	"laugh": preload("res://assets/audio/sfx/laugh.wav"),
	"scream": preload("res://assets/audio/sfx/scream.wav"),
	"whisper": preload("res://assets/audio/sfx/whisper.wav"),

	# Player hello
	"player_hello":[
		preload("res://assets/audio/sfx/raouf_hello.wav"),
		preload("res://assets/audio/sfx/mathys_hello.wav"),
	],
	
	# SFX UI & JEU
	"ui_click": preload("res://assets/audio/sfx/ui_click.wav"),
	"chips_stack": preload("res://assets/audio/sfx/AllInChips.wav"),
	"ting_money": preload("res://assets/audio/sfx/ting_money.wav"),
	"fold_rustle": preload("res://assets/audio/sfx/blow.wav"),
	"check_knock": preload("res://assets/audio/sfx/knock.wav"),
	"card_slide": preload("res://assets/audio/sfx/card_slide.wav"),
	"your_turn": preload("res://assets/audio/sfx/play.wav"), 
	
	"ready": preload("res://assets/audio/sfx/ready.wav"),
	"heartbeat": preload("res://assets/audio/sfx/heartbeat.wav"),
	"shuffle": preload("res://assets/audio/sfx/shuffle.wav"),
	
	"scary_laugh": [
		preload("res://assets/audio/sfx/scary_laugh.wav"),
	],
	
	"dealer_talk": [
		preload("res://assets/audio/sfx/play.wav"),
		preload("res://assets/audio/sfx/lets_play.wav")
		
	]
}

# --- PISCINE DE LECTEURS ---
var num_players = 8 
var bus = "SFX"
var available_players = [] 

func _ready():
	for i in range(num_players):
		var p = AudioStreamPlayer.new()
		add_child(p)
		available_players.append(p)
		p.bus = bus
		p.finished.connect(_on_stream_finished.bind(p))

func _on_stream_finished(player):
	available_players.append(player)

# --- FONCTION DE LECTURE INTELLIGENTE ---
# Ajout du paramètre 'volume_db' (0.0 par défaut)
func play(sound_name: String, pitch_random: bool = true, pitch: float = 1.0, volume_db: float = 0.0):
	if not SOUNDS.has(sound_name):
		print("AUDIO : Son introuvable -> ", sound_name)
		return

	if available_players.size() == 0:
		return

	var p = available_players.pop_back()

	# Gestion des listes aléatoires
	var resource = SOUNDS[sound_name]
	if resource is Array:
		p.stream = resource.pick_random()
	else:
		p.stream = resource

	# Pitch
	if pitch_random:
		p.pitch_scale = randf_range(0.9, 1.1)
	else:
		p.pitch_scale = pitch

	# --- VOLUME ---
	p.volume_db = volume_db # On applique le volume demandé

	p.play()
