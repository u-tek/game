class_name TestCtx
extends RefCounted
## Assertion helper passed to every test method. Records failures instead of aborting.

var failures: Array[String] = []
var current := ""


func ok(cond: bool, msg: String = "") -> void:
	if not cond:
		failures.append("%s: expected true. %s" % [current, msg])


func eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s. %s" % [current, str(expected), str(actual), msg])


func near(actual: float, expected: float, tol: float, msg: String = "") -> void:
	if absf(actual - expected) > tol:
		failures.append("%s: expected %s +/- %s, got %s. %s" % [current, expected, tol, actual, msg])
