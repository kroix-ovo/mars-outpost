extends RefCounted
## Astronaut appearance options shared by the customizer, the landing intro and the colony view.
## A look is a plain Dictionary of option ids, so it saves as JSON and never touches the simulation.

const SKIN_TONES := [
	{"id": "porcelain", "label": "Porcelain", "color": Color("#f6dcc8")},
	{"id": "rose", "label": "Rose", "color": Color("#efc3a4")},
	{"id": "sand", "label": "Sand", "color": Color("#e2b48c")},
	{"id": "honey", "label": "Honey", "color": Color("#d29b6c")},
	{"id": "golden", "label": "Golden", "color": Color("#c48a58")},
	{"id": "olive", "label": "Olive", "color": Color("#b07f55")},
	{"id": "caramel", "label": "Caramel", "color": Color("#9c6942")},
	{"id": "bronze", "label": "Bronze", "color": Color("#7f5133")},
	{"id": "umber", "label": "Umber", "color": Color("#643c25")},
	{"id": "ebony", "label": "Ebony", "color": Color("#4a2b1b")},
]

const HAIR_STYLES := [
	{"id": "short", "label": "Short crop"},
	{"id": "buzz", "label": "Buzz cut"},
	{"id": "bald", "label": "Bald"},
	{"id": "curly", "label": "Short curls"},
	{"id": "afro", "label": "Afro"},
	{"id": "bun", "label": "Top bun"},
	{"id": "ponytail", "label": "Ponytail"},
	{"id": "long", "label": "Long"},
	{"id": "bob", "label": "Bob"},
	{"id": "braids", "label": "Braids"},
	{"id": "spiky", "label": "Spiky"},
	{"id": "headscarf", "label": "Headscarf"},
]

const HAIR_COLORS := [
	{"id": "black", "label": "Black", "color": Color("#1d1a1c")},
	{"id": "dark_brown", "label": "Dark brown", "color": Color("#3d2618")},
	{"id": "brown", "label": "Brown", "color": Color("#6b4226")},
	{"id": "auburn", "label": "Auburn", "color": Color("#8f3b1f")},
	{"id": "red", "label": "Red", "color": Color("#c4532a")},
	{"id": "blonde", "label": "Blonde", "color": Color("#d9b56a")},
	{"id": "silver", "label": "Silver", "color": Color("#c9c9cf")},
	{"id": "blue", "label": "Blue", "color": Color("#3f6fd1")},
	{"id": "pink", "label": "Pink", "color": Color("#e277a8")},
	{"id": "teal", "label": "Teal", "color": Color("#2aa39a")},
	{"id": "plum", "label": "Plum", "color": Color("#5e2f6b")},
	{"id": "navy", "label": "Navy", "color": Color("#22305e")},
]

const EYE_COLORS := [
	{"id": "dark", "label": "Dark brown", "color": Color("#2b1a12")},
	{"id": "brown", "label": "Brown", "color": Color("#5a3720")},
	{"id": "hazel", "label": "Hazel", "color": Color("#7a6232")},
	{"id": "green", "label": "Green", "color": Color("#3e7a45")},
	{"id": "blue", "label": "Blue", "color": Color("#3d74b8")},
	{"id": "grey", "label": "Grey", "color": Color("#6f7a86")},
]

const FACIAL_HAIR := [
	{"id": "none", "label": "None"},
	{"id": "mustache", "label": "Mustache"},
	{"id": "goatee", "label": "Goatee"},
	{"id": "beard", "label": "Full beard"},
]

const GLASSES := [
	{"id": "none", "label": "None"},
	{"id": "round", "label": "Round"},
	{"id": "square", "label": "Square"},
	{"id": "sunglasses", "label": "Sunglasses"},
]

const BUILDS := [
	{"id": "slim", "label": "Slim", "width": 0.88},
	{"id": "regular", "label": "Regular", "width": 1.0},
	{"id": "broad", "label": "Broad", "width": 1.16},
]

const HEIGHTS := [
	{"id": "short", "label": "Short", "scale": 0.9},
	{"id": "average", "label": "Average", "scale": 1.0},
	{"id": "tall", "label": "Tall", "scale": 1.1},
]

const SUIT_COLORS := [
	{"id": "white", "label": "Classic white", "color": Color("#e9e7e1")},
	{"id": "orange", "label": "Launch orange", "color": Color("#e77a2e")},
	{"id": "sky", "label": "Sky blue", "color": Color("#7fb3e0")},
	{"id": "sage", "label": "Sage", "color": Color("#9cb98a")},
	{"id": "graphite", "label": "Graphite", "color": Color("#5d6168")},
	{"id": "lilac", "label": "Lilac", "color": Color("#b49ad6")},
]

const ACCENT_COLORS := [
	{"id": "amber", "label": "Amber", "color": Color("#ffb347")},
	{"id": "red", "label": "Signal red", "color": Color("#e0473a")},
	{"id": "cyan", "label": "Cyan", "color": Color("#3cc4e0")},
	{"id": "green", "label": "Green", "color": Color("#58b85c")},
	{"id": "violet", "label": "Violet", "color": Color("#8b62d9")},
	{"id": "gold", "label": "Gold", "color": Color("#e8c547")},
	{"id": "navy", "label": "Navy", "color": Color("#2d4a8a")},
	{"id": "pink", "label": "Pink", "color": Color("#ec6fa6")},
]

## Option groups in customizer order. Each key in a look maps to one of these lists.
const GROUPS := {
	"skin": SKIN_TONES, "hair_style": HAIR_STYLES, "hair_color": HAIR_COLORS, "eye_color": EYE_COLORS,
	"facial_hair": FACIAL_HAIR, "glasses": GLASSES, "build": BUILDS, "height": HEIGHTS,
	"suit": SUIT_COLORS, "accent": ACCENT_COLORS,
}

const MAX_NAME_LENGTH := 24


static func default_look() -> Dictionary:
	return {"name": "Alex Rivera", "skin": "golden", "hair_style": "short", "hair_color": "dark_brown",
		"eye_color": "brown", "facial_hair": "none", "glasses": "none", "build": "regular",
		"height": "average", "suit": "white", "accent": "amber"}


static func option(group: String, id: String) -> Dictionary:
	## Returns the option record, falling back to the group's first entry for unknown ids.
	var list: Array = GROUPS.get(group, [])
	for entry in list:
		if entry.id == id:
			return entry
	return list[0] if not list.is_empty() else {}


static func index_of(group: String, id: String) -> int:
	var list: Array = GROUPS.get(group, [])
	for i in list.size():
		if list[i].id == id:
			return i
	return 0


static func color(look: Dictionary, group: String) -> Color:
	return option(group, str(look.get(group, ""))).get("color", Color.WHITE)


static func clean_name(value: String) -> String:
	## Keeps printable characters only, collapses spaces and caps the length.
	var out := ""
	for ch in value.strip_edges():
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.substr(0, MAX_NAME_LENGTH).strip_edges()


static func sanitize(look: Variant) -> Dictionary:
	## Any stored or edited look becomes a complete, valid look.
	var result := default_look()
	if not look is Dictionary:
		return result
	for group in GROUPS:
		var id := str(look.get(group, result[group]))
		result[group] = option(group, id).id
	var cleaned := clean_name(str(look.get("name", "")))
	result.name = cleaned if not cleaned.is_empty() else default_look().name
	return result


static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var look := default_look()
	for group in GROUPS:
		var list: Array = GROUPS[group]
		look[group] = list[rng.randi_range(0, list.size() - 1)].id
	# Most astronauts in a random draw keep a bare face and no glasses, like the real corps.
	if rng.randf() < 0.55: look.facial_hair = "none"
	if rng.randf() < 0.6: look.glasses = "none"
	return look
