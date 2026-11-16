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
| W A S D | Walk | Throttle up and down, steer |
| Mouse | Look | Look around the boat |
| Shift | Sprint | |
| Space | Jump | |
| E | Use (board a boat) | Step off at a dock |
| R | | Start or stop the engine |
| X | | Cut the throttle |
| Esc | Free or capture the mouse | |

## Checking the code

The boat physics has a headless test. With Godot on your PATH:

```
godot --headless --path . --fixed-fps 60 res://tests/physics_test.tscn
```
