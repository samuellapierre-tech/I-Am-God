extends SceneTree
## Lanceur de tests headless : exécute chaque tests/test_*.gd (méthodes test_*).

func _init() -> void:
	var failures := 0
	var dir := DirAccess.open("res://tests")
	for file in dir.get_files():
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var suite: Object = load("res://tests/" + file).new()
		for m in suite.get_method_list():
			if not m.name.begins_with("test_"):
				continue
			var err: String = suite.call(m.name)
			if err == "":
				print("PASS ", file, "::", m.name)
			else:
				failures += 1
				print("FAIL ", file, "::", m.name, " — ", err)
	print("%d échec(s)" % failures)
	quit(1 if failures > 0 else 0)
