extends Node
## STUB — remplacé par la branche feature/ai-narrator.
## Contrat : narrate(context) émet narration_ready(text) de façon asynchrone.

signal narration_ready(text: String)


func narrate(context: Dictionary) -> void:
	narration_ready.emit.call_deferred(str(context.get("summary", "...")))
