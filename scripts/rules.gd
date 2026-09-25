extends RefCounted
## All secret answers stay with the hosting peer. Clients receive role-specific views.

const COLORS := ["merah", "biru", "kuning", "hijau"]
const GLYPHS := ["bulan", "bintang", "wajik"]
const BEACONS := ["merah", "biru", "hijau"]
const SWITCH_RULES := {
	"merah": [true, false, true],
	"biru": [false, true, true],
	"hijau": [true, true, false],
}


static func create_round() -> Dictionary:
	var wires := COLORS.duplicate()
	wires.shuffle()
	var glyphs := GLYPHS.duplicate()
	glyphs.shuffle()
	var digit := randi_range(0, 9)
	var beacon: String = BEACONS.pick_random()
	var target_wire := wires.find("merah") if digit % 2 == 0 else wires.find("biru")
	return {
		"phase": "playing",
		"stage": 0,
		"seconds": 180,
		"strikes": 0,
		"wires": wires,
		"glyphs": glyphs,
		"digit": digit,
		"beacon": beacon,
		"target_wire": target_wire,
		"glyph_progress": 0,
		"switches": [false, false, false],
	}


static func wanted_glyph(digit: int, progress: int) -> String:
	var order := ["bintang", "wajik", "bulan"] if digit % 2 == 0 else ["bulan", "wajik", "bintang"]
	return order[progress]


static func switches_match(states: Array, beacon: String) -> bool:
	var wanted: Array = SWITCH_RULES[beacon]
	return states == wanted
