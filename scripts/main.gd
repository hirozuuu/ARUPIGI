extends Node

enum State { EXPLORATION, MENU, TRANSITION, BATTLE }
const CONFIG: GameConfig = preload("res://data/config.tres")
const MAPS := {
	"world": preload("res://data/maps/world.tres"),
	"town": preload("res://data/maps/town.tres"),
	"dungeon": preload("res://data/maps/dungeon.tres"),
}
var state: State = State.EXPLORATION
var session := GameSession.new()
var encounters := EncounterController.new()
var battle := BattleModel.new()
var exploration: Exploration
var ui: GameUI
var confirm_armed: bool = false
var notice_remaining: float = 0.0
var messages: Array[String] = []
var message_index: int = 0
var message_remaining: float = 0.0
var transition_remaining: float = 0.0
var transition_loaded: bool = false
var pending_map: String
var pending_position: Vector2

func _ready() -> void:
	_install_inputs()
	get_window().min_size = Vector2i(720, 480)
	exploration = Exploration.new()
	add_child(exploration)
	get_viewport().size_changed.connect(_on_viewport_resized)
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = GameUI.new()
	layer.add_child(ui)
	encounters.rng.randomize()
	battle.rng.randomize()
	session.reset(CONFIG, MAPS.world.spawn_position("start", CONFIG.tile_size))
	encounters.reset(CONFIG)
	exploration.enter(MAPS[session.map_id], session.position, CONFIG)
	ui.notice = "旅のはじまり。屋根の印は町、岩の印は洞窟。"
	notice_remaining = 5.0
	_refresh_ui()

func _install_inputs() -> void:
	var bindings := {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN], "confirm": [KEY_ENTER, KEY_KP_ENTER], "cancel": [KEY_ESCAPE]}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)
			# Accept logical key events too (numpad and accessibility input).
			var logical_event := InputEventKey.new()
			logical_event.keycode = key
			if not InputMap.action_has_event(action, logical_event):
				InputMap.action_add_event(action, logical_event)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_released("confirm"):
		confirm_armed = true
		return
	if state == State.TRANSITION:
		return
	if event.is_action_pressed("cancel"):
		if state == State.EXPLORATION:
			_set_state(State.MENU)
			ui.selected = 0
		elif state == State.MENU:
			_set_state(State.EXPLORATION)
		_refresh_ui()
		return
	if state == State.BATTLE and ui.battle_phase == "command":
		if event.is_action_pressed("move_up") or event.is_action_pressed("move_down"):
			ui.selected = 1 - ui.selected
			ui.queue_redraw()
	if not event.is_action_pressed("confirm") or not confirm_armed:
		return
	confirm_armed = false
	match state:
		State.MENU:
			_set_state(State.EXPLORATION)
		State.BATTLE:
			if ui.battle_phase == "command":
				_run_action()
			elif ui.battle_phase == "result":
				_finish_battle()
	_refresh_ui()

func _set_state(next: State) -> void:
	state = next
	confirm_armed = false

func _begin_transition(map_id: String, point: Vector2) -> void:
	pending_map = map_id
	pending_position = point
	transition_loaded = false
	transition_remaining = CONFIG.transition_seconds * 2.0
	_set_state(State.TRANSITION)

func _physics_process(delta: float) -> void:
	if not Input.is_action_pressed("confirm"):
		confirm_armed = true
	match state:
		State.TRANSITION:
			transition_remaining = maxf(0.0, transition_remaining - delta)
			var duration := maxf(CONFIG.transition_seconds, 0.001)
			if transition_remaining <= duration and not transition_loaded:
				transition_loaded = true
				session.map_id = pending_map
				session.position = pending_position
				exploration.enter(MAPS[pending_map], pending_position, CONFIG)
				exploration.show()
				encounters.reset(CONFIG)
			ui.fade = 1.0 - absf(transition_remaining - duration) / duration
			if transition_remaining <= 0.0:
				ui.fade = 0.0
				_set_state(State.EXPLORATION)
		State.EXPLORATION:
			var distance := exploration.step(delta, CONFIG)
			session.position = exploration.player.position
			var portal := exploration.map.trigger_at(session.position)
			if not portal.is_empty():
				var target: MapData = MAPS[portal.target_map]
				ui.notice = ""
				_begin_transition(portal.target_map, target.spawn_position(portal.target_spawn, CONFIG.tile_size))
			else:
				if exploration.newly_healing():
					session.heal()
					ui.notice = "花の泉でひと休み。HPが全回復した！"
					notice_remaining = 3.5
				var foe := encounters.advance(distance, MAPS[session.map_id], CONFIG)
				if foe != null:
					begin_battle(foe)
			notice_remaining = maxf(0.0, notice_remaining - delta)
			if notice_remaining == 0.0:
				ui.notice = ""
		State.BATTLE:
			exploration.battle_step(delta, CONFIG)
			session.position = exploration.player.position
			ui.flash = maxf(0.0, ui.flash - delta)
			exploration.arena.enemy_art.modulate = Color(1.0, 0.6, 0.5) if ui.flash > 0.0 else Color.WHITE
			if ui.battle_phase == "busy":
				message_remaining -= delta
				if message_remaining <= 0:
					message_index += 1
					if message_index < messages.size():
						ui.battle_text = messages[message_index]
						message_remaining = CONFIG.message_seconds
					else:
						ui.battle_phase = "command" if battle.outcome == BattleModel.Outcome.ONGOING else "result"
						if ui.battle_phase == "result" and battle.outcome == BattleModel.Outcome.VICTORY:
							exploration.arena.set_enemy_active(false)
						confirm_armed = false
	_refresh_ui()

func begin_battle(foe: EnemyData) -> void:
	battle.setup(foe)
	exploration.begin_battle(foe, get_viewport().get_visible_rect().size)
	_set_state(State.BATTLE)
	ui.enemy = foe
	ui.selected = 0
	ui.battle_phase = "command"
	ui.battle_text = "%sが あらわれた！" % foe.display_name
	ui.flash = 0

func _run_action() -> void:
	ui.battle_phase = "busy"
	messages = battle.attack(session, CONFIG) if ui.selected == 0 else battle.escape(session, CONFIG)
	message_index = 0
	message_remaining = CONFIG.message_seconds
	ui.battle_text = messages[0]
	ui.flash = 0.18

func _finish_battle() -> void:
	ui.notice = ""
	session.position = exploration.player.position
	exploration.end_battle()
	if battle.outcome == BattleModel.Outcome.DEFEAT:
		session.heal()
		ui.notice = "町の花の泉で目が覚めた。HPが全回復した。"
		notice_remaining = 4.0
		_begin_transition("town", MAPS.town.spawn_position("recovery", CONFIG.tile_size))
	else:
		encounters.reset(CONFIG)
		_set_state(State.EXPLORATION)

func _on_viewport_resized() -> void:
	if state == State.BATTLE and exploration != null:
		exploration.arena.fit_resized_view(exploration.camera, get_viewport().get_visible_rect().size)
		_refresh_ui()

func _refresh_ui() -> void:
	ui.screen = {State.EXPLORATION: "exploration", State.MENU: "menu", State.TRANSITION: "exploration", State.BATTLE: "battle"}[state]
	ui.hp = session.hp
	ui.max_hp = session.max_hp
	ui.map_name = MAPS[session.map_id].display_name if MAPS.has(session.map_id) else ""
	ui.enemy_hp = battle.enemy_hp
	if state == State.BATTLE:
		ui.battle_rect = exploration.arena.screen_rect()
	ui.queue_redraw()
