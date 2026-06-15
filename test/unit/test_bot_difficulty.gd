extends GutTest
## The bot's difficulty handicap — a cast-cadence reaction delay that softens a bot
## without dulling it. A higher level opens a damaging cast on more ticks: HARD every
## tick (full strength), the softer levels only on a slower beat, so the bot's poke
## uptime drops and a human can out-trade it. These pin that the handicap throttles only
## the damaging cast — never a heal (survival stays sharp) — and that the level-name
## mapping the flag and the menu share resolves as expected. Headless and deterministic.

const WILDKIN_SPIRIT_BOLT_SLOT := 0  # human SKILLSHOT, range 600 / radius 60
const WILDKIN_MEND_SLOT := 1  # human HEAL


func _bot() -> BotController:
	return BotController.new()


func _hero(sim: SimCore, kit_id: String, pos: Vector2) -> int:
	var id := sim.add_hero(0, pos, 300.0)
	sim.equip_kit(id, kit_id)
	return id


func test_easy_difficulty_throttles_the_damage_cast_to_a_beat() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "wildkin", Vector2.ZERO)  # the first entity, id 1
	sim.add_entity(1, Vector2(600.0, 0.0), 0.0, 600)  # in the skillshot band, ready to poke
	var bot := _bot()
	bot.difficulty = BotController.Difficulty.EASY
	var period: int = BotController.CAST_PERIOD[BotController.Difficulty.EASY]
	# Off the bot's beat ((tick + id) % period != 0) it holds its poke — the reaction
	# handicap — though the target sits squarely in range.
	sim.state.tick = 0  # (0 + 1) % period != 0
	assert_eq(bot.decide(sim.state, id).ability_slot, -1, "off its beat the eased bot does not poke")
	# On a beat it fires the very skillshot a full-strength bot would.
	sim.state.tick = period - 1  # (period - 1 + 1) % period == 0
	assert_eq(
		bot.decide(sim.state, id).ability_slot, WILDKIN_SPIRIT_BOLT_SLOT, "on its beat it pokes"
	)


func test_hard_difficulty_pokes_every_tick() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "wildkin", Vector2.ZERO)
	sim.add_entity(1, Vector2(600.0, 0.0), 0.0, 600)
	var bot := _bot()
	bot.difficulty = BotController.Difficulty.HARD  # the default, asserted explicit here
	sim.state.tick = 1  # an off-beat tick for any softer level
	assert_eq(
		bot.decide(sim.state, id).ability_slot,
		WILDKIN_SPIRIT_BOLT_SLOT,
		"the full-strength bot opens its cast every tick, no reaction handicap"
	)


func test_difficulty_handicap_never_throttles_a_heal() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "wildkin", Vector2.ZERO)
	sim.state.get_entity(id).hp = 100  # under the 60% heal threshold
	sim.add_entity(1, Vector2(600.0, 0.0), 0.0, 600)
	var bot := _bot()
	bot.difficulty = BotController.Difficulty.EASY
	sim.state.tick = 0  # off the cast beat, where a poke would be withheld
	assert_eq(
		bot.decide(sim.state, id).ability_slot,
		WILDKIN_MEND_SLOT,
		"survival is never throttled: a hurt eased bot still heals off-beat"
	)


func test_difficulty_from_name_maps_levels_and_defaults_to_easy() -> void:
	assert_eq(BotController.difficulty_from_name("hard"), BotController.Difficulty.HARD)
	assert_eq(BotController.difficulty_from_name("normal"), BotController.Difficulty.NORMAL)
	assert_eq(BotController.difficulty_from_name("easy"), BotController.Difficulty.EASY)
	assert_eq(
		BotController.difficulty_from_name("bogus"),
		BotController.Difficulty.EASY,
		"an unknown name falls back to the winnable easy default"
	)
