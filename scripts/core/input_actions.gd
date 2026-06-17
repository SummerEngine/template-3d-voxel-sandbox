## Remappable movement actions, registered into the InputMap at runtime so the player reads
## actions (not hardcoded keys) and they can be rebound + persisted (via GameSettings.keybinds).
## setup() is idempotent — safe to call from main.gd and player.gd. The rebind UI lives in the
## settings panels. Non-movement keys (hotbar 1-9, F fly-toggle, Q/E, G eat, F5 view) stay fixed.

# action name -> default PHYSICAL keycode (matches the old Input.is_physical_key_pressed behaviour)
const DEFAULTS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"jump": KEY_SPACE,
	"sprint": KEY_CTRL,
	"descend": KEY_SHIFT,
}

# Stable display order + labels for the rebind UI.
const ORDER := ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "descend"]
const LABELS := {
	"move_forward": "Forward", "move_back": "Back", "move_left": "Left", "move_right": "Right",
	"jump": "Jump / Up", "sprint": "Sprint", "descend": "Descend",
}

## Register every action and bind its key (saved override, else default). Safe to re-run.
static func setup() -> void:
	GameSettings.load_cfg()
	for action in DEFAULTS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		_bind(action, keycode_for(action))

## The keycode currently bound to an action — a saved override, or the default.
static func keycode_for(action: String) -> int:
	if GameSettings.keybinds.has(action):
		return int(GameSettings.keybinds[action])
	return int(DEFAULTS.get(action, 0))

## Rebind an action to a new physical keycode, apply it live, and persist.
static func rebind(action: String, keycode: int) -> void:
	if not DEFAULTS.has(action) or keycode == 0:
		return
	GameSettings.keybinds[action] = keycode
	_bind(action, keycode)
	GameSettings.save_cfg()

## Reset every action to its default key.
static func reset() -> void:
	GameSettings.keybinds.clear()
	for action in DEFAULTS:
		_bind(action, int(DEFAULTS[action]))
	GameSettings.save_cfg()

static func _bind(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode as Key
	InputMap.action_add_event(action, ev)

## Human-readable key name for the UI (e.g. "W", "Space", "Ctrl").
static func key_label(keycode: int) -> String:
	var s := OS.get_keycode_string(keycode)
	return s if s != "" else "—"
