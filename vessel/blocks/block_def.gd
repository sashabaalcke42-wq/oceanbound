class_name BlockDef
extends Resource
## Definition of one kind of building block. One .tres file per block in
## res://data/blocks/. Adding a block type means adding a file here, not code.

enum Shape { CUBE, WEDGE }
enum Category { STRUCTURE, PROPULSION, EQUIPMENT, DECORATION }

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var category := Category.STRUCTURE
@export var shape := Shape.CUBE
## Size in grid cells before rotation.
@export var size := Vector3i.ONE
## The cell (in the block's own cells) that goes where the player clicks.
## An outboard uses its top cell, so it hangs down from the transom.
@export var anchor := Vector3i.ZERO
@export var mass_kg := 1.0
@export var price := 0
@export var default_color := Color(0.7, 0.72, 0.75)

@export_group("Hull")
## Hull blocks count as sealed volume and keep the boat afloat.
@export var buoyant := false

@export_group("Propulsion")
## Maximum forward thrust in newtons. Applied at the block's lowest cell.
@export var thrust_n := 0.0
## How far the engine swings to steer, in degrees. 0 means it cannot steer.
@export var steer_angle_deg := 0.0
@export var fuel_burn_lph := 0.0
## The water speed at which the propeller stops pushing (its pitch times its
## top revs). Thrust falls off towards it, as with a real propeller.
@export var prop_pitch_speed_ms := 14.0
## Steered by hand with a tiller handle. The driver sits within reach of it,
## and a boat takes only one. Otherwise the engine is steered by cable from a
## helm seat with a wheel, and several can be fitted side by side.
@export var tiller := false

@export_group("Equipment")
## Litres of fuel this block holds.
@export var fuel_capacity_l := 0.0
## A helm seat has a steering wheel. Remote (non-tiller) outboards need one.
@export var is_helm := false
@export var seats := 0
## A bilge pump: litres per hour it pumps out of the boat. Runs on its own.
@export var pump_lph := 0.0
