extends RefCounted
## Deterministic, diff-friendly JSON writer for data/*.json and data/fixtures/*.json (tools only).
## Keys keep their insertion order (no sorting). A container is written on one line when it
## holds only scalars (e.g. one battle event) or fits in WIDTH columns (tabs count as 4);
## otherwise one entry per line, tab-indented.
##
##   const JsonPretty := preload("res://tests/tools/json_pretty.gd")
##   JsonPretty.write("res://data/stages.json", value)

const WIDTH := 110


static func stringify(v: Variant, indent: String = "") -> String:
	var one := one_line(v)
	if not (v is Dictionary or v is Array) or (v as Variant).is_empty() or _flat(v) \
			or indent.length() * 4 + one.length() <= WIDTH:
		return one
	var inner := indent + "\t"
	var lines := PackedStringArray()
	if v is Dictionary:
		for k in v:
			lines.append(inner + JSON.stringify(str(k)) + ": " + stringify(v[k], inner))
		return "{\n" + ",\n".join(lines) + "\n" + indent + "}"
	for x in v:
		lines.append(inner + stringify(x, inner))
	return "[\n" + ",\n".join(lines) + "\n" + indent + "]"


## True when no value inside is a non-empty container.
static func _flat(v: Variant) -> bool:
	var values: Array = v.values() if v is Dictionary else v
	for x in values:
		if (x is Dictionary or x is Array) and not (x as Variant).is_empty():
			return false
	return true


## Single-line JSON with a space after ":" and ",".
static func one_line(v: Variant) -> String:
	if v is Dictionary:
		var parts := PackedStringArray()
		for k in v:
			parts.append(JSON.stringify(str(k)) + ": " + one_line(v[k]))
		return "{" + ", ".join(parts) + "}"
	if v is Array:
		var items := PackedStringArray()
		for x in v:
			items.append(one_line(x))
		return "[" + ", ".join(items) + "]"
	return JSON.stringify(v)


## Writes `v` as pretty JSON plus a trailing newline. Returns false if the file can't be written.
static func write(path: String, v: Variant) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("JsonPretty: cannot write %s" % path)
		return false
	f.store_string(stringify(v) + "\n")
	f.close()
	return true
