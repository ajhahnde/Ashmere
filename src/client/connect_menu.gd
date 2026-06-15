class_name ConnectMenu
extends Control
## The in-game connect screen, shown on a windowed launch with no mode flag. It
## lets the player start a single-machine practice match, host a listen-server, or
## join one by address — the same three modes the command line selects with
## `--local`, `--host`, and `--join`, surfaced as UI so a player never needs flags.
##
## Pure presentation: it owns no networking and no simulation, only emitting a
## signal for the chosen mode. `main.gd` wires those signals to the existing
## `_start_*` paths, so the menu adds an entry point without touching authority or
## the wire. A headless run skips it — a menu cannot be driven without a display —
## and the command-line flags stay the automation path.

## The player chose to host a listen-server.
signal host_requested
## The player chose to join a server at `address` (already resolved to the default
## when the field was left blank).
signal join_requested(address: String)
## The player chose a single-machine practice match driving `hero` (a kit id). That
## hero's tribe fields the player's team and the opposing tribe the bots, so the pick
## also chooses the match-up — the same role `--hero` fills on the command line.
signal practice_requested(hero: String)

## Menu styling. An opaque backdrop covers the whole viewport so the debug map and its
## jungle camps — drawn behind the menu in world space — do not bleed through the otherwise
## transparent controls; the card sits on top as a framed panel, so the menu reads as UI
## rather than floating text over the arena.
const BACKDROP_COLOR := Color(0.07, 0.08, 0.10)
const CARD_COLOR := Color(0.13, 0.14, 0.17)
const CARD_PADDING := 52.0
const CARD_CORNER := 14
const CARD_MIN_WIDTH := 680.0
## The menu-wide base font size; every control inherits it, the title overrides larger.
const BASE_FONT_SIZE := 28
const TITLE_FONT_SIZE := 72
const BUTTON_MIN_SIZE := Vector2(560, 76)
const ADDRESS_MIN_WIDTH := 380.0

## The address used when the player leaves the field blank. The driver injects its
## own default so the menu and the `--join` flag resolve to one value.
var default_address := "127.0.0.1"

## The hero the picker starts on (a kit id). The driver injects its own default — any
## `--hero` already parsed, else the default tribe's lead — so the menu reflects the
## command line. Empty selects the first hero in the list.
var default_hero := ""

var _address_field: LineEdit
## Picks the hero the player drives in a practice match. Populated from
## `AbilityData.TRIBE` so the roster cannot drift from the simulation's; each item
## carries its kit id as metadata.
var _hero_picker: OptionButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# A menu-wide theme bumps the base font so every control — the labels, the dropdown, the
	# buttons, the address field — scales up together; the title overrides larger still.
	var ui_theme := Theme.new()
	ui_theme.default_font_size = BASE_FONT_SIZE
	theme = ui_theme

	# An opaque backdrop, behind everything, so the world drawn in screen space behind the
	# menu does not show through the transparent controls. Ignores the mouse so it never
	# eats a click meant for a button below it in the tree.
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = BACKDROP_COLOR
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# A framed card so the controls read against a solid panel rather than the arena. The
	# stylebox is set explicitly so the look does not depend on the active editor theme.
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.custom_minimum_size = Vector2(CARD_MIN_WIDTH, 0)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	card.add_child(box)

	var title := Label.new()
	title.text = "Theria"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	box.add_child(title)

	var pick_label := Label.new()
	pick_label.text = "Practice hero"
	box.add_child(pick_label)

	_hero_picker = OptionButton.new()
	_populate_heroes()
	box.add_child(_hero_picker)

	var practice_button := Button.new()
	practice_button.text = "Practice (single machine)"
	practice_button.custom_minimum_size = BUTTON_MIN_SIZE
	practice_button.pressed.connect(_on_practice_pressed)
	box.add_child(practice_button)

	var host_button := Button.new()
	host_button.text = "Host a match"
	host_button.custom_minimum_size = BUTTON_MIN_SIZE
	host_button.pressed.connect(_on_host_pressed)
	box.add_child(host_button)

	var join_row := HBoxContainer.new()
	box.add_child(join_row)

	_address_field = LineEdit.new()
	_address_field.placeholder_text = default_address
	_address_field.custom_minimum_size = Vector2(ADDRESS_MIN_WIDTH, 0)
	_address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_address_field)

	var join_button := Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(_on_join_pressed)
	join_row.add_child(join_button)


## The card's background: a solid dark panel with rounded corners and inner padding, so the
## controls sit on their own surface clear of the arena behind the menu.
func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_COLOR
	style.set_corner_radius_all(CARD_CORNER)
	style.set_content_margin_all(CARD_PADDING)
	return style


## Fills the hero picker from the tribe rosters — one item per hero, labelled
## "Tribe — Hero", carrying its kit id as metadata — and selects `default_hero` (or the
## first hero when none was injected). Reading `AbilityData.TRIBE` keeps the menu's roster
## in lockstep with the simulation's: a new hero appears here the moment it joins a tribe.
func _populate_heroes() -> void:
	for tribe in AbilityData.TRIBE:
		for hero in AbilityData.TRIBE[tribe]:
			_hero_picker.add_item("%s — %s" % [tribe.capitalize(), (hero as String).capitalize()])
			_hero_picker.set_item_metadata(_hero_picker.item_count - 1, hero)
	if default_hero.is_empty():
		return
	for i in _hero_picker.item_count:
		if _hero_picker.get_item_metadata(i) == default_hero:
			_hero_picker.select(i)
			return


## The kit id of the selected hero, falling back to `default_hero` if nothing is
## selected (an empty roster — never the case while a tribe is defined).
func _selected_hero() -> String:
	if _hero_picker.selected < 0:
		return default_hero
	return _hero_picker.get_item_metadata(_hero_picker.selected)


func _on_practice_pressed() -> void:
	practice_requested.emit(_selected_hero())


func _on_host_pressed() -> void:
	host_requested.emit()


## Resolves the typed address — falling back to `default_address` when blank — and
## emits `join_requested`. Trimmed so stray whitespace is not taken as a host name.
func _on_join_pressed() -> void:
	var address := _address_field.text.strip_edges()
	if address.is_empty():
		address = default_address
	join_requested.emit(address)
