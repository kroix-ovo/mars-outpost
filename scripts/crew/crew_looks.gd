extends RefCounted
## Designed looks for the named outpost crew (data/crew/outpost_roster.json), plus a diverse
## fallback set for crew without a designed look. Training fixtures use the landing crew.
## Presentation only; keyed by crew definition id and never read by the simulation.

const Look := preload("res://scripts/crew/astronaut_look.gd")

const ROLE_LABELS := {
	"engineering": "Engineer", "botany": "Botanist", "geology": "Geologist",
	"medicine": "Medic", "piloting": "Pilot",
}

const ROSTER := {
	"outpost_crew_01": {"name": "Inez Solis", "role": "engineering", "skin": "olive", "hair_style": "ponytail",
		"hair_color": "dark_brown", "eye_color": "brown", "facial_hair": "none", "glasses": "none",
		"build": "regular", "height": "average", "suit": "white", "accent": "amber"},
	"outpost_crew_02": {"name": "Amara Okafor", "role": "botany", "skin": "ebony", "hair_style": "afro",
		"hair_color": "black", "eye_color": "dark", "facial_hair": "none", "glasses": "none",
		"build": "regular", "height": "tall", "suit": "sage", "accent": "green"},
	"outpost_crew_03": {"name": "Tariq Nasser", "role": "engineering", "skin": "caramel", "hair_style": "short",
		"hair_color": "black", "eye_color": "brown", "facial_hair": "beard", "glasses": "none",
		"build": "broad", "height": "tall", "suit": "white", "accent": "cyan"},
	"outpost_crew_04": {"name": "Nia Park", "role": "geology", "skin": "rose", "hair_style": "bob",
		"hair_color": "black", "eye_color": "dark", "facial_hair": "none", "glasses": "square",
		"build": "slim", "height": "short", "suit": "orange", "accent": "navy"},
	"outpost_crew_05": {"name": "Jo Silva", "role": "medicine", "skin": "honey", "hair_style": "curly",
		"hair_color": "teal", "eye_color": "hazel", "facial_hair": "none", "glasses": "round",
		"build": "regular", "height": "average", "suit": "white", "accent": "red"},
	"outpost_crew_06": {"name": "Luca Ivanov", "role": "piloting", "skin": "porcelain", "hair_style": "buzz",
		"hair_color": "blonde", "eye_color": "blue", "facial_hair": "mustache", "glasses": "none",
		"build": "broad", "height": "average", "suit": "sky", "accent": "gold"},
	"outpost_crew_07": {"name": "Leila Mensah", "role": "botany", "skin": "umber", "hair_style": "headscarf",
		"hair_color": "plum", "eye_color": "dark", "facial_hair": "none", "glasses": "none",
		"build": "regular", "height": "average", "suit": "lilac", "accent": "gold"},
	"outpost_crew_08": {"name": "Ren Ito", "role": "geology", "skin": "sand", "hair_style": "spiky",
		"hair_color": "black", "eye_color": "dark", "facial_hair": "none", "glasses": "round",
		"build": "slim", "height": "average", "suit": "graphite", "accent": "pink"},
	"outpost_crew_09": {"name": "Maya Chen", "role": "engineering", "skin": "sand", "hair_style": "bun",
		"hair_color": "dark_brown", "eye_color": "brown", "facial_hair": "none", "glasses": "none",
		"build": "slim", "height": "short", "suit": "white", "accent": "violet"},
}

## The six crew who land with the commander (the reference colony's starting roster).
const LANDING_CREW := ["outpost_crew_01", "outpost_crew_02", "outpost_crew_03",
	"outpost_crew_04", "outpost_crew_05", "outpost_crew_06"]

## Varied stand-in looks for crew without a designed look, picked in a stable order.
const FALLBACKS := [
	{"skin": "bronze", "hair_style": "braids", "hair_color": "black", "suit": "white", "accent": "amber"},
	{"skin": "porcelain", "hair_style": "long", "hair_color": "red", "suit": "sky", "accent": "navy", "eye_color": "green"},
	{"skin": "golden", "hair_style": "short", "hair_color": "black", "suit": "orange", "accent": "cyan", "glasses": "square"},
	{"skin": "umber", "hair_style": "bald", "hair_color": "black", "suit": "white", "accent": "green", "facial_hair": "goatee", "build": "broad"},
	{"skin": "sand", "hair_style": "bun", "hair_color": "silver", "suit": "lilac", "accent": "gold", "glasses": "round"},
	{"skin": "olive", "hair_style": "curly", "hair_color": "brown", "suit": "sage", "accent": "red", "facial_hair": "beard"},
	{"skin": "rose", "hair_style": "ponytail", "hair_color": "blonde", "suit": "graphite", "accent": "pink"},
	{"skin": "caramel", "hair_style": "headscarf", "hair_color": "navy", "suit": "white", "accent": "violet"},
	{"skin": "ebony", "hair_style": "spiky", "hair_color": "blue", "suit": "orange", "accent": "amber", "height": "tall"},
]


static func has_design(definition_id: String) -> bool:
	return ROSTER.has(definition_id)


static func look_for(definition_id: String, display_name: String = "") -> Dictionary:
	## Returns a complete look for any crew definition id.
	if ROSTER.has(definition_id):
		return Look.sanitize(ROSTER[definition_id])
	var named_id := _training_identity(display_name)
	if named_id.is_empty() and definition_id.begins_with("fixture_crew_"):
		named_id = _training_identity("Fixture Crew " + definition_id.right(1).to_upper())
	if not named_id.is_empty():
		return Look.sanitize(ROSTER[named_id])
	var pick: Dictionary = FALLBACKS[_fallback_index(definition_id)].duplicate()
	pick.name = display_name if not display_name.is_empty() else definition_id
	return Look.sanitize(pick)


static func display_name(value: String) -> String:
	## Fixture identifiers remain in the simulation; players meet the landing crew.
	var id := _training_identity(value)
	return str(ROSTER[id].name) if not id.is_empty() else value


static func _training_identity(value: String) -> String:
	for prefix in ["Fixture Crew ", "Astronaut "]:
		if value.begins_with(prefix):
			var suffix := value.trim_prefix(prefix)
			if suffix.length() == 1 and suffix >= "A" and suffix <= "I":
				return "outpost_crew_%02d" % (suffix.unicode_at(0) - 64)
	return ""


static func role_label(definition_id: String) -> String:
	return ROLE_LABELS.get(ROSTER.get(definition_id, {}).get("role", ""), "Crew")


static func _fallback_index(definition_id: String) -> int:
	# Ids ending in a letter or number map in order, so A..I differ from one another.
	var tail := definition_id.substr(definition_id.length() - 1)
	var code := tail.to_lower().unicode_at(0)
	if code >= 97 and code <= 122:
		return (code - 97) % FALLBACKS.size()
	if code >= 48 and code <= 57:
		return (code - 48) % FALLBACKS.size()
	return posmod(definition_id.hash(), FALLBACKS.size())
