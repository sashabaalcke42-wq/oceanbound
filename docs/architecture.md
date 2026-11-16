# Architecture

OceanBound is built in four layers. The full planning doc with diagrams lives
in the project's Claude Docs ("OceanBound: prototype plan"); this file records
what is in the code.

## Layers

| Layer | Where | What it holds |
| --- | --- | --- |
| Data | `data/`, `items/`, `jobs/` | Block, item and shop definitions (`.tres`), and job kinds (small scripts that make Job objects). |
| Services | `systems/` | Autoload singletons with one job each. They never look up scene nodes. |
| World | `world/`, `player/`, `ui/` | The scenes you see: ocean, island, docks, town, jetties, player, HUD, menu screens. |
| Vessels | `vessel/` | Designs, the builder that turns a design into a boat, and the boat physics. |

## Autoloads

| Name | Script | Job |
| --- | --- | --- |
| `EventBus` | `systems/event_bus.gd` | Global signals (notifications, prompts, boarding). |
| `InputSetup` | `systems/input_setup.gd` | Registers input actions in code. |
| `Waves` | `systems/waves.gd` | The ocean surface. `Waves.height_at(x, z)` is what boats float on. |
| `BlockLibrary` | `systems/block_library.gd` | Loads every BlockDef in `data/blocks/`. |
| `ItemLibrary` | `systems/item_library.gd` | Loads every ItemDef in `data/items/`; names and prices for any ownable id. |
| `Inventory` | `systems/inventory.gd` | What the player owns but has not fitted, as item id to count: blocks, fish, bait, cargo. |
| `Economy` | `systems/economy.gd` | Money (`earn`, `spend`, each with a reason) and fish market prices. |
| `Locations` | `systems/locations.gd` | Named places (docks, jetties, the town quay) that jobs and the HUD point at. |
| `Jobs` | `systems/jobs.gd` | The job board, the active job, objectives, deadlines and payouts. |
| `GameState` | `systems/game_state.gd` | The player's boat design, facility build limits, tutorial flag. |

## Decisions

1. **Every boat is built from blocks.** There is no hand-made boat model. The
   player's first tinny, later boats and NPC boats all go through
   `VesselBuilder.build()`, so construction and physics share one code path.
2. **One wave function.** `systems/waves.gd` and `world/ocean/ocean.gdshader`
   implement the same Gerstner waves with the same parameters and time. Change
   one, change the other. Waves fade to flat 260 to 420 m from the camera in
   both, which hides aliasing and lets the horizon ring stay flat.
3. **0.25 m grid.** A 3.5 m tinny is 14 cells long. Blocks can span several
   cells and have 24 orientations (`vessel/blocks/orientations.gd`).
4. **Buoyancy counts enclosed air.** Hull blocks plus any air they seal in
   (found by a layer-by-layer flood fill) give displacement. Open boats
   therefore float as high as real ones, and a boat with a hole in its side
   floats lower. Cells are grouped into 2 x 2 columns, so a tinny takes 32
   wave samples per physics tick.
5. **Believable arcade handling.** Light forward drag, heavy sideways drag,
   speed-dependent yaw damping, and a planing factor above about twice hull
   speed. Thrust is applied at the propeller's position along the boat but
   partway up towards the centre of mass (`thrust_height_assist`), which stands
   in for planing lift. Without it a small, light boat flips backwards under
   full throttle. All numbers live in the vessel's `profile` dictionary.
6. **Boarding puts you at the helm.** Walking on a moving deck is deferred;
   it is a known source of jitter with character controllers on rigid bodies.

7. **Blocks are owned.** Placing a block takes it from the inventory and
   removing it gives it back, so a boat is always made of things the player
   has. Step 3's shop sells more blocks into the same inventory.
8. **Editing rules are separate from the workshop scene.** `DesignEditor`
   (place, remove, drag-fill, undo, size limits, blueprint matching) has no
   3D or UI code, so it is tested headless. `workshop.gd` is the 3D view and
   input; `workshop_ui.gd` is the panels.
9. **Build size depends on the facility.** `GameState.FACILITIES` holds each
   facility's grid limits. The personal dock allows 9 x 8 x 19 cells (about
   2.25 m x 2 m x 4.75 m); the public dry dock and shipyards will add larger ones.
10. **Jobs are data.** A job is a list of objectives, each "go to a place, and
    on arrival take or give some items". Deliveries, fish orders and later
    passengers or towing are new combinations, made by a small script in
    `jobs/kinds/` listed in `Jobs.KIND_SCRIPTS`. Arrival only counts when the
    player is on foot or the boat is nearly stopped.
11. **Places emit, the world decides.** The town and jetties only emit
    `place_used(id)`; `world/main.gd` opens the matching screen. Screens extend
    `ui/screens/screen.gd` and fill a list of rows.
12. **Money has one door.** Every change goes through `Economy.earn()` or
    `Economy.spend()` with a reason, so a ledger, taxes or loans can hook in
    without touching callers. Fish prices drift and fall as you sell.

## Collision layers

| Layer | Used by |
| --- | --- |
| 1 | World: terrain, docks |
| 2 | Vessels |
| 3 | Player |
| 4 | Interactables (areas the player can use with E) |

## Tests and tools

- `tests/physics_test.tscn`: headless boat checks (floating, top speed,
  turning, coasting, waves, design save and load). Run:
  `godot --headless --path . --fixed-fps 60 res://tests/physics_test.tscn`
- `tests/editor_test.tscn`: workshop checks (placement rules, inventory,
  undo, every tutorial step, design analysis, the workshop scene).
- `tests/flow_test.tscn`: a scripted play-through (workshop, launch, drive,
  dock, rebuild, fall in the sea). Any error printed is a failure.
- `tests/loop_test.tscn`: the core loop (shops, job board, deliveries and
  deadlines, fish orders, fishing, the fish market, fuel).
- `tools/screenshots.tscn`: a scripted camera tour that saves screenshots.
