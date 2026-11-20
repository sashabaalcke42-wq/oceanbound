extends Screen
## The job board: one job at a time. Accepting a job shows its next step on
## the HUD and a beacon at the place to go.


func _init() -> void:
	title = "Job Board"
	subtitle = "Take one job at a time. Pay is on delivery."


func _fill() -> void:
	if Jobs.active:
		var j := Jobs.active
		add_heading("Your job")
		var detail := "%s\nNext: %s." % [j.description, j.status_text()]
		if j.time_limit > 0.0:
			detail += "  Time left: %s." % _clock(j.time_left)
		add_row("%s  ($%d)" % [j.title, j.reward], detail, [["Give up", Jobs.abandon]])
	add_heading("Available")
	var board := Jobs.board()
	if board.is_empty():
		add_row("Nothing today", "Check back later.")
	for j in board:
		var detail := j.description
		detail += "\nTime allowed: %s." % (_clock(j.time_limit) if j.time_limit > 0.0 else "no limit")
		if j.requirements != "":
			detail += "  Needs: %s" % j.requirements
		add_row("%s  ($%d)" % [j.title, j.reward], detail,
				[["Accept", Jobs.accept.bind(j), Jobs.active == null]])


static func _clock(seconds: float) -> String:
	var s := maxi(ceili(seconds), 0)
	return "%d:%02d" % [s / 60, s % 60]
