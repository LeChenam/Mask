extends Node

# Liste des clés de sons définies dans AudioManager
const SPOOKY_SOUNDS = [
	"creepy_whisper",
	"footstep",
	"gougougaga",
	"laugh",
	"scream",
	"whisper"
]

# Temps d'attente aléatoire (en secondes)
@export var min_time: float = 15.0
@export var max_time: float = 60.0

var timer = Timer.new()

func _ready():
	# On ajoute le timer à la scène
	add_child(timer)
	timer.one_shot = true
	timer.timeout.connect(_on_timer_timeout)
	
	# Seul le serveur décide quand faire peur
	if multiplayer.is_server():
		print("AMBIANCE : Démarrage du générateur de peur...")
		_start_random_timer()

func _start_random_timer():
	# On choisit un temps au hasard entre min et max
	var wait_time = randf_range(min_time, max_time)
	timer.wait_time = wait_time
	timer.start()
	# print("AMBIANCE : Prochain son dans ", int(wait_time), " secondes")

func _on_timer_timeout():
	if not multiplayer.is_server(): return
	
	# 1. Choisir un son au hasard
	var chosen_sound = SPOOKY_SOUNDS.pick_random()
	
	# 2. Choisir un pitch aléatoire pour varier (grave = plus peur)
	var random_pitch = randf_range(0.5, 0.9)
	
	# 3. Envoyer l'ordre à tout le monde !
	play_global_scare.rpc(chosen_sound, random_pitch)
	
	# 4. Relancer le timer
	_start_random_timer()

# --- RPC REÇU PAR TOUS LES CLIENTS ---
@rpc("authority", "call_local", "reliable")
func play_global_scare(sound_name: String, pitch: float):
	print("AMBIANCE : Son joué -> ", sound_name)
	
	# On joue le son via l'AudioManager
	# Volume -5dB pour que ce soit une ambiance de fond, pas une agression
	if AudioManager:
		AudioManager.play(sound_name, false, pitch, -5.0)
