extends GutTest
## Behaviour checks on the bot's ability casting. The bot walks toward the nearest
## enemy (the walking-skeleton behaviour) and, once it is a kitted hero, layers a
## cast onto that intent: a self-heal when hurt, otherwise the first damaging
## ability of its active form that can actually reach the target. These pin the
## selection order and the per-targeting-mode reach gate, plus one end-to-end check
## that a chosen cast lands in the sim. Headless and deterministic, creep waves off.

const WILDKIN_SPIRIT_BOLT_SLOT := 0  # human SKILLSHOT, range 600 / radius 60
const WILDKIN_MEND_SLOT := 1  # human HEAL


func _bot() -> BotController:
	return BotController.new()


func _hero(sim: SimCore, kit_id: String, pos: Vector2) -> int:
	var id := sim.add_hero(0, pos, 300.0)
	sim.equip_kit(id, kit_id)
	return id


# --- The is-a-kitted-hero gate ----------------------------------------------


func test_a_bot_without_a_kit_only_moves() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var mover := sim.add_hero(0, Vector2.ZERO, 300.0)  # never equipped -> not a caster
	sim.add_entity(1, Vector2(400.0, 0.0), 0.0, 600)
	var command := _bot().decide(sim.state, mover)
	assert_eq(command.ability_slot, -1, "a kit-less hero never casts")
	assert_ne(command.move_dir, Vector2.ZERO, "but it still advances on the enemy")


# --- Selection: which slot, by reach and effect -----------------------------


func test_bot_fires_a_skillshot_at_an_enemy_in_its_band() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "wildkin", Vector2.ZERO)
	sim.add_entity(1, Vector2(600.0, 0.0), 0.0, 600)  # at the skillshot's exact range
	var command := _bot().decide(sim.state, id)
	assert_eq(command.ability_slot, WILDKIN_SPIRIT_BOLT_SLOT, "it casts the reachable skillshot")
	assert_eq(command.target_point, Vector2(600.0, 0.0), "aimed straight at the enemy")


func test_bot_holds_fire_when_no_ability_can_reach() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "wildkin", Vector2.ZERO)
	# Far outside the skillshot's [range-radius, range+radius] band: a cast would
	# strike empty air, so the bot must not spend it.
	sim.add_entity(1, Vector2(1200.0, 0.0), 0.0, 600)
	var command := _bot().decide(sim.state, id)
	assert_eq(command.ability_slot, -1, "a full-health bot out of reach casts nothing")
	assert_ne(command.move_dir, Vector2.ZERO, "it closes the distance instead")


func test_bot_picks_a_ground_ability_that_can_reach() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "hyena", Vector2.ZERO)  # human slot 0 = Bone-Hex, GROUND
	sim.add_entity(1, Vector2(400.0, 0.0), 0.0, 600)  # inside range + radius
	var command := _bot().decide(sim.state, id)
	assert_eq(command.ability_slot, 0, "the ground area is cast on a reachable enemy")
	assert_eq(command.target_point, Vector2(400.0, 0.0), "dropped on the target")


func test_a_unit_ability_locks_the_target() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "cheetah", Vector2.ZERO)
	# Shift to the animal kit, whose slot 0 (Hamstring) is unit-targeted.
	var beast := InputCommand.new()
	beast.ability_slot = 3
	sim.step({id: beast})
	var enemy := sim.add_entity(1, Vector2(200.0, 0.0), 0.0, 600)  # inside Hamstring's 280
	var command := _bot().decide(sim.state, id)
	assert_eq(command.ability_slot, 0, "the unit ability is selected")
	assert_eq(command.target_id, enemy, "and locked onto the nearest enemy")


func test_a_hurt_bot_heals_before_it_attacks() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "wildkin", Vector2.ZERO)
	sim.state.get_entity(id).hp = 100  # well under the 60% heal threshold of 600
	sim.add_entity(1, Vector2(600.0, 0.0), 0.0, 600)  # a damage target is also in reach
	var command := _bot().decide(sim.state, id)
	assert_eq(command.ability_slot, WILDKIN_MEND_SLOT, "survival comes first: it heals, not pokes")


# --- End to end: the chosen cast lands --------------------------------------


func test_a_bot_cast_lands_in_the_sim() -> void:
	var sim := SimCore.new()
	sim.spawn_creeps = false
	var id := _hero(sim, "wildkin", Vector2.ZERO)
	sim.state.get_entity(id).move_speed = 0.0  # hold position so the cast geometry is exact
	# At the skillshot's range (600), and beyond the 250 auto-attack range, so only the cast lands.
	var enemy := sim.add_entity(1, Vector2(600.0, 0.0), 0.0, 600)
	sim.step({id: _bot().decide(sim.state, id)})
	assert_eq(sim.state.get_entity(enemy).hp, 520, "Spirit Bolt's 80 lands on the enemy")
	assert_eq(sim.state.get_entity(id).resource, 80, "and its 20 cost is booked")
