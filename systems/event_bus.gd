extends Node
## Global signal hub. Systems emit here instead of holding references to each
## other, so UI, audio and future systems can listen without coupling.

## A short message for the player, shown by the HUD.
signal notify(text: String)
## The interaction prompt under the crosshair changed. Empty text hides it.
signal interaction_prompt_changed(text: String)
## The player took or left the helm of a vessel.
signal player_boarded(vessel: Node)
signal player_disembarked(vessel: Node)
