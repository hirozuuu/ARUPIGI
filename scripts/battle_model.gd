class_name BattleModel
extends RefCounted
## Resolves one command synchronously; the battle view sequences its messages.

enum Outcome { ONGOING, VICTORY, ESCAPED, DEFEAT }

var enemy: EnemyData
var enemy_hp: int = 0
var outcome: Outcome = Outcome.ONGOING
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func setup(enemy_data: EnemyData) -> void:
	enemy = enemy_data
	enemy_hp = maxi(1, enemy.max_hp)
	outcome = Outcome.ONGOING


func attack(session: GameSession, config: GameConfig) -> Array[String]:
	var messages: Array[String] = []
	if outcome != Outcome.ONGOING or enemy == null:
		return messages
	var damage: int = _damage_roll(config.attack_min, config.attack_max)
	enemy_hp = maxi(0, enemy_hp - damage)
	messages.append("あなたの こうげき！\n%sに %d のダメージ。" % [enemy.display_name, damage])
	if enemy_hp == 0:
		outcome = Outcome.VICTORY
		messages.append("%sを たおした！\n経験値 0" % enemy.display_name)
	else:
		_retaliate(session, messages)
	return messages


func resolve_escape(session: GameSession, escaped: bool, config: GameConfig) -> Array[String]:
	var messages: Array[String] = []
	if outcome != Outcome.ONGOING or enemy == null:
		return messages
	if escaped:
		outcome = Outcome.ESCAPED
		var gained := maxi(0, config.escape_experience)
		var levels_gained := session.gain_experience(gained, config)
		var result := "うまく にげきれた！\n経験値 +%d" % gained
		if levels_gained > 0:
			result += "\nレベル %d にアップ！ 移動速度が上がった！" % session.level
		messages.append(result)
	else:
		messages.append("にげられなかった！")
		_retaliate(session, messages)
	return messages


func _retaliate(session: GameSession, messages: Array[String]) -> void:
	var damage: int = _damage_roll(enemy.attack_min, enemy.attack_max)
	session.damage(damage)
	messages.append("%sの こうげき！\nあなたに %d のダメージ。" % [enemy.display_name, damage])
	if session.hp == 0:
		outcome = Outcome.DEFEAT
		messages.append("ちからつきて しまった……\n町で ひとやすみしよう。")


func _damage_roll(minimum: int, maximum: int) -> int:
	return rng.randi_range(maxi(0, minimum), maxi(maxi(0, minimum), maximum))
