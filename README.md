# OceanBound

A 3D open-world maritime sandbox built in Godot 4 (GDScript). You start with a
small personal dock, build your own boats from blocks, and make a living on the
water.

## Running the game

1. Install [Godot 4.7](https://godotengine.org/download) (the standard build,
   not .NET). No installer is needed: unzip it and run it.
2. In the Godot Project Manager, choose **Import** and pick this folder's
   `project.godot`.
3. Press **F5** (or the play button) to run.

See `docs/` for architecture notes and decisions.

## Controls

| Key | On foot | At the helm |
| --- | --- | --- |
| W A S D | Walk (also on a moving boat's deck) | Throttle up and down, steer |
| Mouse | Look | Look around |
| Shift | Run | |
| Space | Jump (in the water: climb out at a jetty or boat side) | |
| E | Use: shops, job board, fuel pump; next to your boat, step aboard and take the helm | Stopped beside a jetty: tie up and step ashore. Elsewhere: get up from the seat |
| R | | Start or stop the engine |
| X | | Cut the throttle |
| F | Fish (cast, strike, reel in) | Fish, when stopped |
| B (hold) | Bail water out of the boat you are in | Bail |
| V | First or third person | First or third person |
| M | Full map | Full map |
| F11 | Fullscreen on or off | Fullscreen on or off |
| Esc | Free or capture the mouse | |

Your boat is tied up alongside your dock. Walk up beside it and press **E**
to step aboard and take the helm. Bring it in slowly next to any jetty and
press **E** again: the lines go out, the boat is drawn in alongside, and you
step onto the jetty. At sea, **E** stands you up in the boat instead. Fall in
and you swim; swim to a jetty or your boat and press **Space** to climb out.

The mini map in the bottom-right corner is north-up and zooms out as you go
faster. It marks Harbour Town, the jetties, your dock, your boat and the place
your job wants you (in gold). **M** shows the whole island. With the mouse
left alone at the helm, the camera swings round behind the boat.

## How the water behaves

- Boats float on every bit of their hull, so your weight, your load and any
  water in the bottom make them sit lower and lean towards the heavy side.
  Walk to one side of the tinny and watch it list.
- Waves move the water itself, so boats surge on crests and get set back in
  troughs. Wind pushes on what is above the water and drifts a stopped boat.
- A propeller only grips when it is well under the surface. Mount the motor
  too high, or lift the stern on a wave, and the engine races and the boat
  slows.
- Waves higher than your gunwale slop in. The water sloshes to the low side
  and weighs you down. Hold **B** to bail, or fit a **bilge pump** (Marine
  Supplies). If the motor's powerhead goes under, the engine dies until you
  have bailed out.

## Building a boat

You start with a kit of boat parts and no boat. Walk to the workbench at the
shore end of your dock and press **E** to open the workshop. The first time,
a tutorial walks you through building a tinny one step at a time, with a blue
outline showing where the blocks go.

| Input | In the workshop |
| --- | --- |
| Left click | Place a block (click and drag to place a rectangle) |
| Right click | Remove a block |
| Right drag, wheel | Orbit and zoom the camera |
| R / T | Rotate / tilt the block |
| C | Next colour |
| Ctrl+Z / Ctrl+Y | Undo / redo |
| Esc | Close the workshop |

The panel on the right shows the boat's weight, draft, freeboard and
estimated top speed, and anything that would stop it launching. Designs can
be saved and loaded; loading needs enough blocks in your inventory.

## Making a living

**Harbour Town** is a short run along the coast from your dock (head right as
you look out to sea; the signpost at the land end of your dock points the
way). The compass strip at the top of the screen always shows it, along with
the public jetties and your own dock, each with its distance; the place your
current job wants you is shown in gold. On its quay are the **fish market**, the **job board** and a
fuel pump; up the hill are **Marine Supplies** (boat blocks), the **General
Store** (bait and rods) and the **Harbour Office**. Public jetties at
Lighthouse Point, Northern Cove and Oyster Farm are where deliveries go.

- **Jobs.** Take one job at a time from the board. Its next step shows at the
  top right, and a gold beacon marks where to go. Deliveries have a deadline;
  stop at the jetty (or step off) to pick up and drop off. Fish orders want a
  number of one fish brought to Harbour Town's quay.
- **Fishing.** Press **F** facing the water from a dock, the shore or a
  stopped boat. When the float starts bobbing and it says something's biting,
  press **F** again quickly. Bait halves the wait. Deeper water holds bigger,
  pricier fish; tuna only live far out.
- **Money.** You start with $250. Fish prices change through the day and drop
  if you sell a lot of one kind at once. Fuel is $2 a litre at any pump.

## Checking the code

The boat physics has a headless test. With Godot on your PATH:

```
godot --headless --path . --fixed-fps 60 res://tests/physics_test.tscn
godot --headless --path . res://tests/editor_test.tscn
godot --headless --path . --fixed-fps 60 res://tests/flow_test.tscn
godot --headless --path . --fixed-fps 60 res://tests/loop_test.tscn
```
