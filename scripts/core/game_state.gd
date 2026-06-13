class_name GameState

## Tiny cross-scene flag bag. Static vars persist for the lifetime of the run
## (they live on the class, not on a node), so the main menu can tell the gameplay
## scene whether to start fresh or load the saved world.

static var load_on_start := false
