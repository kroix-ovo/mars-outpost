extends RefCounted
## Strict validator for commands that exist only in contract 3.0.0. Existing v2
## command shapes keep their own validator; this never accepts arbitrary payloads.
const Schema = preload("res://scripts/simulation/command_schemas.gd")
const VERSION := "3.0.0"
const PAYLOADS = {
	"request_fast_forward": {"target_elapsed_s": "elapsed"},
	"cancel_fast_forward": {},
}

static func owns(type: Variant) -> bool:
	return type is String and PAYLOADS.has(type)

static func validate(command: Dictionary) -> Dictionary:
	if not Schema.exact_keys(command, ["contract_version", "command_id", "type", "payload"]):
		return Schema.failure("invalid_schema", "Command envelope keys do not match the schema.")
	if not Schema.identifier(command.command_id) or not command.type is String or not command.contract_version is String or not command.payload is Dictionary:
		return Schema.failure("invalid_schema", "Invalid command envelope types.")
	if command.contract_version != VERSION:
		return Schema.failure("unsupported_contract", "contract_version must be 3.0.0")
	if not PAYLOADS.has(command.type):
		return Schema.failure("unsupported_command", "Unknown campaign command type.")
	var schema: Dictionary = PAYLOADS[command.type]
	if not Schema.exact_keys(command.payload, schema.keys()):
		return Schema.failure("invalid_schema", "Payload keys do not match the command schema.")
	var normalized := command.duplicate(true)
	for key in schema:
		var value: Variant = command.payload[key]
		# Whole simulated seconds only: the mission clock has no fractional boundary.
		if schema[key] != "elapsed" or not Schema.whole(value, 1):
			return Schema.failure("invalid_value", "Invalid payload field: " + key)
		normalized.payload[key] = int(value)
	return {"ok": true, "code": "ok", "reason": "", "command": normalized}
