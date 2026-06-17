extends GutTest
## Contracts for the corner minimap. The drawing itself is judged in a playtest, but the two
## headless-safe pieces are pinned here: the sim-to-panel coordinate mapping (pure, so the plan
## lines up with the arena), and that build + per-tick update run without error over a real world.


func test_map_point_maps_the_arena_corners_to_the_panel() -> void:
	var panel := Vector2(Minimap.SIZE, Minimap.SIZE)
	var bounds := MapData.BOUNDS
	assert_eq(Minimap.map_point(bounds.position, panel), Vector2.ZERO, "top-left maps to 0")
	assert_eq(Minimap.map_point(bounds.end, panel), panel, "bottom-right maps to size")
	assert_eq(Minimap.map_point(bounds.get_center(), panel), panel * 0.5, "centre maps to centre")


func test_build_and_update_run_over_a_real_world() -> void:
	var minimap := Minimap.new()
	add_child_autofree(minimap)  # _ready pins the corner anchors
	var sim := SimCore.new()
	sim.spawn_structures()
	var hero := sim.add_hero(0, MapData.spawn_for_team(0), 320.0)
	sim.add_hero(1, MapData.spawn_for_team(1), 300.0)
	var focus := sim.state.get_entity(hero)
	# Local-authority path (filters enemy dots by vision) and the pure-CLIENT path (shows all).
	minimap.update(sim.state, 0, focus, [Color.RED, Color.BLUE], true)
	minimap.update(sim.state, 0, focus, [Color.RED, Color.BLUE], false)
	# Before a hero spawns the driver passes a null focus — must not error.
	minimap.update(sim.state, 0, null, [Color.RED, Color.BLUE], true)
	assert_eq(minimap.custom_minimum_size, Vector2(Minimap.SIZE, Minimap.SIZE), "the panel is sized")


func test_unmap_point_is_the_inverse_of_map_point() -> void:
	var panel := Vector2(Minimap.SIZE, Minimap.SIZE)
	var bounds := MapData.BOUNDS
	assert_eq(Minimap.unmap_point(Vector2.ZERO, panel), bounds.position, "0 maps back to top-left")
	assert_eq(Minimap.unmap_point(panel, panel), bounds.end, "size maps back to bottom-right")
	assert_eq(Minimap.unmap_point(panel * 0.5, panel), bounds.get_center(), "centre back to centre")
	# A non-trivial sim point survives map → unmap unchanged (the click projection is lossless).
	var p := bounds.position + bounds.size * Vector2(0.3, 0.7)
	var round_trip := Minimap.unmap_point(Minimap.map_point(p, panel), panel)
	assert_almost_eq(round_trip, p, Vector2(0.01, 0.01), "map → unmap is the identity")


func test_a_click_on_the_plan_emits_a_command_at_the_world_point_under_it() -> void:
	var minimap := Minimap.new()
	autofree(minimap)
	var panel := Vector2(Minimap.SIZE, Minimap.SIZE)
	minimap.size = panel  # pin a known size so the projection is independent of a layout pass
	watch_signals(minimap)
	var local := panel * Vector2(0.25, 0.6)
	var world := Minimap.unmap_point(local, panel)

	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = local
	minimap._gui_input(right)
	assert_signal_emitted_with_parameters(minimap, "order_requested", [world])

	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	left.position = local
	minimap._gui_input(left)
	assert_signal_emitted_with_parameters(minimap, "look_requested", [world])
