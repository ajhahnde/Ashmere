class_name BotController
extends RefCounted
## Produces an InputCommand for a bot-controlled entity from the world state.
##
## v0.1 behaviour: walk toward the nearest enemy, stop on contact, and — once the
## entity is a kitted hero — cast its abilities. The bot heals itself when hurt,
## otherwise fires the first damaging ability of its active form that can actually
## reach the target. Deterministic — a pure function of the state — so a bot match
## replays identically and feeds the same simulation core a human would, gating on
## the very `AbilityExecutor.can_cast` the player's casts pass through.

## Stop advancing once within this many world units of the target.
const STOP_RANGE := 60.0

## The ability bar is four slots (0..3) per form; the bot scans them in order so its
## pick is deterministic by slot rather than by dictionary iteration order.
const SLOT_COUNT := 4

## Heal once health falls below this fraction of the maximum — soon enough to
## matter in a trade, but not so eager the bot tops off a scratch every tick.
const HEAL_HP_FRACTION := 0.6


func decide(state: SimState, bot_id: int) -> InputCommand:
	var command := InputCommand.new()
	var bot := state.get_entity(bot_id)
	if bot == null:
		return command
	var target := _nearest_enemy(state, bot)
	if target == null:
		return command
	var offset := target.position - bot.position
	if offset.length() > STOP_RANGE:
		command.move_dir = offset.normalized()
	if bot.is_hero:
		_choose_cast(command, bot, target)
	return command


## Layers an ability cast onto the bot's command when one is worth casting this
## tick: a self-heal first when the bot is hurt and can afford one, otherwise the
## first damaging ability of its active form that can land on `target`. Reads the
## same state the player's input sampler does and gates on the same cast rules, so a
## bot's casts stay pure and replayable. The bot fights from its starting form;
## transforming into the animal kit is a later step.
func _choose_cast(command: InputCommand, bot: SimEntity, target: SimEntity) -> void:
	var slots: Dictionary = bot.kit.get(bot.form, {})
	if bot.max_hp > 0 and bot.hp < int(float(bot.max_hp) * HEAL_HP_FRACTION):
		var heal_slot := _castable_slot(bot, slots, AbilitySpec.EFFECT_HEAL, target)
		if heal_slot >= 0:
			command.ability_slot = heal_slot
			return
	var damage_slot := _castable_slot(bot, slots, AbilitySpec.EFFECT_DAMAGE, target)
	if damage_slot >= 0:
		command.ability_slot = damage_slot
		command.target_point = target.position
		command.target_id = target.id


## The lowest slot in `slots` whose ability has `effect`, passes the cast gate
## (form, resource, cooldown), and — for a damaging ability — can reach `target`.
## -1 when none qualifies. A heal is self-cast, so it needs no reach check.
func _castable_slot(bot: SimEntity, slots: Dictionary, effect: int, target: SimEntity) -> int:
	var dist := bot.position.distance_to(target.position)
	for slot in SLOT_COUNT:
		if not slots.has(slot):
			continue
		var ability_id: int = slots[slot]
		if not AbilityData.has_ability(ability_id):
			continue
		var spec := AbilityData.spec(ability_id)
		if spec.effect != effect:
			continue
		if not AbilityExecutor.can_cast(bot, spec):
			continue
		if effect == AbilitySpec.EFFECT_DAMAGE and not _reaches(spec, dist):
			continue
		return slot
	return -1


## Whether a cast of `spec` aimed straight at an enemy `dist` away would actually
## strike it — mirroring the executor's landing geometry so the bot never spends a
## cast on empty air. A UNIT ability reaches any enemy within range; a GROUND area
## lands on the target (pulled in to range) and hits if the target sits inside its
## radius; a SKILLSHOT flies the full range along the aim, so it strikes only an
## enemy in the band one radius around that range.
func _reaches(spec: AbilitySpec, dist: float) -> bool:
	match spec.target_kind:
		AbilitySpec.TARGET_UNIT:
			return dist <= spec.range
		AbilitySpec.TARGET_GROUND:
			return dist <= spec.range + spec.radius
		AbilitySpec.TARGET_SKILLSHOT:
			return absf(dist - spec.range) <= spec.radius
	return false


func _nearest_enemy(state: SimState, bot: SimEntity) -> SimEntity:
	var nearest: SimEntity = null
	var nearest_dist := INF
	for id in state.entities:
		var other: SimEntity = state.entities[id]
		if other.team == bot.team:
			continue
		var dist := bot.position.distance_to(other.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = other
	return nearest
