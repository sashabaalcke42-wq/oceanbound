class_name Job
extends RefCounted
## One job: a title, a reward, an optional time limit, and a list of
## objectives done in order. Objectives are plain data, so new job kinds are
## new combinations rather than new code:
##   {"text": String, "location": StringName,
##    "give": {"id": StringName, "count": int},   # handed to you on arrival
##    "take": {"id": StringName, "count": int}}   # taken from you on arrival

enum State { AVAILABLE, ACTIVE, DONE, FAILED }

var id := 0
var kind: StringName
var title := ""
var description := ""
var reward := 0
## Seconds allowed once accepted. 0 means no limit.
var time_limit := 0.0
var time_left := 0.0
var requirements := ""
var objectives: Array[Dictionary] = []
var current := 0
var state := State.AVAILABLE


func current_objective() -> Dictionary:
	return objectives[current] if current < objectives.size() else {}


func status_text() -> String:
	var obj := current_objective()
	return obj.get("text", "")
