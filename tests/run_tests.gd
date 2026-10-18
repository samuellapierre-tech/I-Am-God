extends SceneTree
## Lanceur de tests headless : exécute chaque tests/test_*.gd (méthodes test_*).
## Chaque test tourne dans son propre processus : GDScript ne peut pas intercepter une erreur
## de script, donc un plantage n'est détectable que dans la sortie du processus enfant.

const OK_MARK := "__TEST_OK__"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 3 and args[0] == "--single":
		_run_single(args[1], args[2])
		return
	var failures := 0
	var dir := DirAccess.open("res://tests")
	for file in dir.get_files():
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var suite: Object = load("res://tests/" + file).new()
		for m in suite.get_method_list():
			if not m.name.begins_with("test_"):
				continue
			var err := _run_isolated(file, m.name)
			if err == "":
				print("PASS ", file, "::", m.name)
			else:
				failures += 1
				print("FAIL ", file, "::", m.name, " — ", err)
	print("%d échec(s)" % failures)
	quit(1 if failures > 0 else 0)


func _run_isolated(file: String, method: String) -> String:
	var output := []
	var cmd := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/run_tests.gd", "--", "--single", file, method]
	OS.execute(OS.get_executable_path(), cmd, output, true)
	var text := "\n".join(output)
	if text.contains("SCRIPT ERROR") or text.contains("Parse Error"):
		return "erreur de script :\n" + text.strip_edges()
	if not text.contains(OK_MARK):
		for line in text.split("\n"):
			if line.begins_with("__TEST_FAIL__ "):
				return line.trim_prefix("__TEST_FAIL__ ")
		return "plantage (aucun résultat) :\n" + text.strip_edges()
	# Les sorties du test (ex. mesures de perf) restent visibles.
	for line in text.split("\n"):
		if line.strip_edges() != "" and line != OK_MARK and not line.begins_with("Godot Engine"):
			print("    ", line)
	return ""


func _run_single(file: String, method: String) -> void:
	var suite: Object = load("res://tests/" + file).new()
	var res: Variant = suite.call(method)
	if typeof(res) == TYPE_STRING and res == "":
		print(OK_MARK)
	else:
		print("__TEST_FAIL__ ", res)
	quit(0)
