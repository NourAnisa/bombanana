extends Node3D

const Rules = preload("res://scripts/rules.gd")
const PORT := 24570
const ROLES := ["Teknisi", "Pengamat", "Pemandu"]
const GESTURES := [
	"☝ Nomor seri genap",
	"✌ Nomor seri ganjil",
	"🔴 Kabel merah paling kiri",
	"🔵 Kabel biru paling kanan",
	"★ Bintang",
	"◆ Wajik",
	"☾ Bulan",
	"① ON",
	"① OFF",
	"② ON",
	"② OFF",
	"③ ON",
	"③ OFF",
	"⏱ Cepat!"
]
const INK := Color("f4f4e9")
const MUTED := Color("9ba7b1")
const YELLOW := Color("fbd36a")
const TEAL := Color("64dcc2")
const PINK := Color("ff8e96")

var solo := false
var solo_role := 0
var roster: Array[int] = []
var round_data: Dictionary = {}
var local_view: Dictionary = {"phase": "menu"}
var chat_log: Array[String] = []
var message := "Pilih Latihan Solo, Host LAN, atau Gabung LAN."
var tick_accumulator := 0.0
var current_signature := ""
var board_signature := ""
var root_ui: Control
var header_box: HBoxContainer
var left_box: VBoxContainer
var right_box: VBoxContainer
var timer_label: Label
var status_label: Label
var chat_edit: LineEdit
var bomb_visual: Node3D


func _ready() -> void:
	randomize()
	multiplayer.peer_connected.connect(_peer_joined)
	multiplayer.peer_disconnected.connect(_peer_left)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)
	_build_world()
	_build_shell()
	_render()


func _process(delta: float) -> void:
	if not _is_server() or round_data.get("phase") != "playing":
		return
	tick_accumulator += delta
	if tick_accumulator < 1.0:
		return
	tick_accumulator -= 1.0
	round_data["seconds"] = maxi(0, int(round_data["seconds"]) - 1)
	if round_data["seconds"] == 0:
		round_data["phase"] = "lost"
		_log("Waktu habis. Bom meledak!")
	_push_views()


func _is_server() -> bool:
	return solo or (multiplayer.has_multiplayer_peer() and multiplayer.is_server())


func _host() -> void:
	_leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 2)
	if err != OK:
		message = "Gagal membuka UDP %d. Kode galat: %d" % [PORT, err]
		_render()
		return
	multiplayer.multiplayer_peer = peer
	roster = [1]
	message = "Server aktif. Teman bergabung lewat IP host dan port %d." % PORT
	_push_views()


func _join(address: String) -> void:
	if address.strip_edges().is_empty():
		message = "Isi alamat IP komputer host dahulu."
		_render()
		return
	_leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), PORT)
	if err != OK:
		message = "Gagal menghubungi host. Kode galat: %d" % err
		_render()
		return
	multiplayer.multiplayer_peer = peer
	message = "Menghubungi %s:%d ..." % [address.strip_edges(), PORT]
	_render()


func _practice() -> void:
	_leave()
	solo = true
	solo_role = 0
	roster = [1]
	chat_log.clear()
	_log("Mode latihan: ganti peran untuk membaca semua petunjuk.")
	_start_round()


func _leave() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	solo = false
	roster.clear()
	round_data.clear()
	chat_log.clear()
	local_view = {"phase": "menu"}
	current_signature = ""
	board_signature = ""
	message = "Kembali ke menu utama."
	_render()


func _connected() -> void:
	message = "Terhubung ke host. Menunggu pembagian peran."
	_render()


func _connection_failed() -> void:
	_leave()
	message = "Sambungan gagal. Periksa IP dan firewall UDP %d." % PORT
	_render()


func _server_disconnected() -> void:
	_leave()
	message = "Host terputus."
	_render()


func _peer_joined(id: int) -> void:
	if not multiplayer.is_server():
		return
	if not roster.has(id):
		var empty_slot := roster.find(0)
		if empty_slot >= 0:
			roster[empty_slot] = id
		elif roster.size() < 3:
			roster.append(id)
		else:
			return
		_log("%s bergabung." % ROLES[roster.find(id)])
		_push_views()


func _peer_left(id: int) -> void:
	if not multiplayer.is_server() or not roster.has(id):
		return
	var role_index := roster.find(id)
	roster[role_index] = 0  # Preserve roles when a player disconnects.
	_log("%s terputus; tunggu pemain pengganti." % ROLES[role_index])
	_push_views()


func _start_round() -> void:
	if not _is_server() or (not solo and (roster.size() != 3 or roster.has(0))):
		return
	round_data = Rules.create_round()
	tick_accumulator = 0.0
	chat_log.clear()
	_log("Misi dimulai. Selesaikan KABEL → SIMBOL → SAKLAR.")
	_push_views()


func _request_start() -> void:
	if solo or (multiplayer.is_server() and roster.size() == 3 and not roster.has(0)):
		_start_round()


func _request_action(kind: String, index: int) -> void:
	if solo:
		_server_action(1, kind, index)
	elif multiplayer.is_server():
		_server_action(1, kind, index)
	else:
		action_request.rpc_id(1, kind, index)


@rpc("any_peer", "call_remote", "reliable")
func action_request(kind: String, index: int) -> void:
	if multiplayer.is_server():
		_server_action(multiplayer.get_remote_sender_id(), kind, index)


func _server_action(sender: int, kind: String, index: int) -> void:
	if not _is_server() or round_data.get("phase") != "playing":
		return
	if not solo and (roster.is_empty() or roster[0] != sender):
		return
	var stage: int = round_data["stage"]
	if kind == "wire" and stage == 0 and index >= 0 and index < 4:
		if index == int(round_data["target_wire"]):
			round_data["stage"] = 1
			_log("✓ Kabel aman. Sekarang masukkan urutan simbol.")
		else:
			_strike("Kabel yang dipotong salah.")
	elif kind == "glyph" and stage == 1 and index >= 0 and index < 3:
		var glyph: String = round_data["glyphs"][index]
		if glyph == Rules.wanted_glyph(int(round_data["digit"]), int(round_data["glyph_progress"])):
			round_data["glyph_progress"] += 1
			if round_data["glyph_progress"] == 3:
				round_data["stage"] = 2
				_log("✓ Simbol benar. Atur tiga saklar.")
		else:
			round_data["glyph_progress"] = 0
			_strike("Urutan simbol salah; mulai lagi dari awal.")
	elif kind == "toggle" and stage == 2 and index >= 0 and index < 3:
		var switches: Array = round_data["switches"]
		switches[index] = not switches[index]
		_push_views()
		return
	elif kind == "confirm" and stage == 2:
		if Rules.switches_match(round_data["switches"], round_data["beacon"]):
			round_data["phase"] = "won"
			_log("✓ BOM DIJINAKKAN! Kerja sama tim berhasil.")
		else:
			_strike("Kombinasi saklar salah.")
	else:
		return
	_push_views()


func _strike(reason: String) -> void:
	round_data["strikes"] += 1
	_log("✕ %s (%d/3 kesalahan)" % [reason, round_data["strikes"]])
	if round_data["strikes"] >= 3:
		round_data["phase"] = "lost"
		_log("Bom meledak. Coba lagi!")


func _send_message(value: String, gesture := false) -> void:
	var cleaned := value.strip_edges().substr(0, 90)
	if cleaned.is_empty():
		return
	if solo or multiplayer.is_server():
		_server_message(1, cleaned, gesture)
	else:
		message_request.rpc_id(1, cleaned, gesture)


@rpc("any_peer", "call_remote", "reliable")
func message_request(value: String, gesture: bool) -> void:
	if multiplayer.is_server():
		_server_message(
			multiplayer.get_remote_sender_id(), value.strip_edges().substr(0, 90), gesture
		)


func _server_message(sender: int, value: String, gesture: bool) -> void:
	if not _is_server() or not round_data.has("phase") or value.is_empty():
		return
	var role_index := solo_role if solo else roster.find(sender)
	if role_index < 0:
		return
	if role_index == 2:
		if not gesture or not GESTURES.has(value):
			return
	elif gesture:
		return
	_log("%s: %s" % [ROLES[role_index], value.replace("\n", " ")])
	_push_views()


func _log(value: String) -> void:
	chat_log.append(value)
	if chat_log.size() > 13:
		chat_log.pop_front()


func _push_views() -> void:
	if solo:
		_receive_view(_make_view(solo_role))
		return
	for i in range(roster.size()):
		var id := roster[i]
		if id == 0:
			continue
		var view := _make_view(i)
		if id == 1:
			_receive_view(view)
		else:
			receive_view.rpc_id(id, view)


func _make_view(role_index: int) -> Dictionary:
	var connected := 0
	for id in roster:
		if id != 0:
			connected += 1
	var view := {
		"phase": round_data.get("phase", "lobby"),
		"role": ROLES[role_index],
		"role_index": role_index,
		"players": connected,
		"solo": solo,
		"seconds": round_data.get("seconds", 180),
		"strikes": round_data.get("strikes", 0),
		"stage": round_data.get("stage", 0),
		"glyph_progress": round_data.get("glyph_progress", 0),
		"messages": chat_log.duplicate(),
	}
	if round_data.is_empty():
		return view
	if role_index == 0:
		view["wire_count"] = 4
		view["glyphs"] = round_data["glyphs"].duplicate()
		view["switches"] = round_data["switches"].duplicate()
	elif role_index == 1:
		view["wires"] = round_data["wires"].duplicate()
		view["glyphs"] = round_data["glyphs"].duplicate()
		view["digit"] = round_data["digit"]
		view["beacon"] = round_data["beacon"]
		view["switches"] = round_data["switches"].duplicate()
	else:
		view["manual"] = true
	return view


@rpc("authority", "call_remote", "reliable")
func receive_view(view: Dictionary) -> void:
	_receive_view(view)


func _receive_view(view: Dictionary) -> void:
	local_view = view
	_render()


func _build_shell() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	root_ui = Control.new()
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root_ui)

	var header := PanelContainer.new()
	header.anchor_right = 1.0
	header.offset_left = 20
	header.offset_top = 14
	header.offset_right = -20
	header.offset_bottom = 72
	_style_panel(header)
	root_ui.add_child(header)
	header_box = HBoxContainer.new()
	header_box.add_theme_constant_override("separation", 16)
	header.add_child(header_box)

	var left := PanelContainer.new()
	left.anchor_bottom = 1.0
	left.offset_left = 20
	left.offset_top = 88
	left.offset_right = 324
	left.offset_bottom = -20
	_style_panel(left)
	root_ui.add_child(left)
	left_box = VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 11)
	left.add_child(left_box)

	var right := PanelContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -486
	right.offset_top = 88
	right.offset_right = -20
	right.offset_bottom = -20
	_style_panel(right)
	root_ui.add_child(right)
	var scroller := ScrollContainer.new()
	scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroller)
	right_box = VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.add_theme_constant_override("separation", 12)
	scroller.add_child(right_box)


func _style_panel(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182338f2")
	style.border_color = Color("637483")
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	panel.add_theme_stylebox_override("panel", style)


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _render() -> void:
	if root_ui == null:
		return
	var signature_view := local_view.duplicate(true)
	signature_view.erase("seconds")
	var signature := JSON.stringify(signature_view) + message
	if signature == current_signature:
		_update_timer()
		return
	current_signature = signature
	_clear(header_box)
	_clear(left_box)
	_clear(right_box)
	_render_header()
	_render_left()
	_render_right()
	_render_bomb()
	_update_timer()


func _render_header() -> void:
	var title := _label(header_box, "●  BANANA PANIC LAB", 22, YELLOW)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var phase: String = local_view.get("phase", "menu")
	var headline := (
		"PROTOTIPE GODOT 4"
		if phase == "menu"
		else "%s  ·  %s" % [str(local_view.get("role", "")), phase.to_upper()]
	)
	_label(header_box, headline, 15, TEAL)
	timer_label = _label(header_box, "", 26, INK)
	if phase != "menu":
		_button(header_box, "Keluar", func(): _leave(), false, 82)


func _update_timer() -> void:
	if timer_label == null:
		return
	var phase: String = local_view.get("phase", "menu")
	if phase == "playing":
		var seconds: int = local_view.get("seconds", 180)
		timer_label.text = "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]
		timer_label.add_theme_color_override("font_color", PINK if seconds <= 30 else INK)
	else:
		timer_label.text = "03:00" if phase == "menu" else "—:—"


func _render_left() -> void:
	var phase: String = local_view.get("phase", "menu")
	_label(left_box, "MISI  /  BRIEFING", 17, YELLOW)
	_label(
		left_box,
		"Tiga monyet. Tiga sudut pandang. Satu bom yang harus dijinakkan bersama.",
		15,
		INK
	)
	if phase == "menu":
		_label(
			left_box,
			"LATIHAN: jelajahi setiap peran sendiri.\nLAN: satu host dan dua klien di jaringan yang sama.",
			14,
			MUTED
		)
		_spacer(left_box)
		_label(left_box, message, 14, TEAL)
		return
	_label(
		left_box,
		"%s  ·  %s pemain" % [str(local_view.get("role", "")), str(local_view.get("players", 1))],
		16,
		TEAL
	)
	if phase == "lobby":
		_label(
			left_box,
			"Host LAN memakai UDP %d. Bagikan alamat IP lokal host kepada dua teman." % PORT,
			14,
			MUTED
		)
	else:
		_label(
			left_box,
			(
				"Tahap %d/3    ·    Kesalahan %d/3"
				% [mini(int(local_view.get("stage", 0)) + 1, 3), int(local_view.get("strikes", 0))]
			),
			16,
			PINK
		)
	var chat_title := (
		"ISYARAT & RIWAYAT" if int(local_view.get("role_index", 0)) == 2 else "KOMUNIKASI TIM"
	)
	_label(left_box, chat_title, 15, YELLOW)
	var history := RichTextLabel.new()
	history.bbcode_enabled = false
	history.fit_content = false
	history.scroll_following = true
	history.selection_enabled = true
	history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lines := PackedStringArray()
	for entry in local_view.get("messages", []):
		lines.append(str(entry))
	history.text = "\n".join(lines)
	left_box.add_child(history)
	if phase == "playing":
		if int(local_view.get("role_index", 0)) == 2:
			_label(left_box, "Pemandu tidak bisa mengetik. Kirim gestur di panel kanan.", 13, MUTED)
		else:
			chat_edit = LineEdit.new()
			chat_edit.placeholder_text = "Ketik pesan ke tim…"
			chat_edit.max_length = 90
			left_box.add_child(chat_edit)
			chat_edit.text_submitted.connect(
				func(value: String):
					_send_message(value)
					chat_edit.clear()
			)
			_button(
				left_box,
				"Kirim pesan ↗",
				func():
					_send_message(chat_edit.text)
					chat_edit.clear()
			)


func _render_right() -> void:
	var phase: String = local_view.get("phase", "menu")
	if phase == "menu":
		_render_menu()
	elif phase == "lobby":
		_render_lobby()
	else:
		_render_round()


func _render_menu() -> void:
	_label(right_box, "SIAP MENJADI TIM PENJINAK?", 23, YELLOW)
	_label(
		right_box,
		"Game kooperatif orisinal terinspirasi konsep pembagian informasi antarpemain.",
		16,
		INK
	)
	_spacer(right_box, 15)
	_button(right_box, "▶  LATIHAN SOLO", func(): _practice())
	_label(right_box, "Coba seluruh mekanik di satu perangkat; ganti peran kapan saja.", 13, MUTED)
	_spacer(right_box, 12)
	_button(right_box, "◉  HOST LAN (TEKNISI)", func(): _host())
	_label(
		right_box, "Host memegang bom. Dua teman bergabung sebagai Pengamat dan Pemandu.", 13, MUTED
	)
	_spacer(right_box, 12)
	var ip := LineEdit.new()
	ip.placeholder_text = "IP host, mis. 192.168.1.5"
	ip.text = "127.0.0.1"
	right_box.add_child(ip)
	_button(right_box, "↗  GABUNG LAN", func(): _join(ip.text))
	_label(
		right_box,
		"Untuk uji satu komputer: jalankan tiga instance Godot; dua klien masuk ke 127.0.0.1.",
		13,
		MUTED
	)


func _render_lobby() -> void:
	_label(right_box, "RUANG TUNGGU", 25, YELLOW)
	_label(right_box, "Peranmu: %s" % str(local_view["role"]), 17, TEAL)
	_label(right_box, "Pemain tersambung: %d / 3" % int(local_view["players"]), 18, INK)
	_spacer(right_box, 15)
	_label(
		right_box,
		"TEKNISI   ·   Sentuh kabel, simbol, dan saklar. Tidak dapat melihat warna dan layar.",
		15,
		INK
	)
	_label(
		right_box,
		"PENGAMAT   ·   Melihat bom, warna, nomor seri, dan sinyal. Tidak dapat menyentuhnya.",
		15,
		INK
	)
	_label(
		right_box, "PEMANDU   ·   Membaca manual. Hanya dapat mengirim isyarat singkat.", 15, INK
	)
	_spacer(right_box, 20)
	if multiplayer.is_server():
		_button(right_box, "MULAI MISI", func(): _request_start(), int(local_view["players"]) == 3)
	else:
		_label(right_box, "Menunggu host memulai setelah tiga pemain bergabung...", 15, MUTED)


func _render_round() -> void:
	var phase: String = local_view["phase"]
	if phase == "won" or phase == "lost":
		_label(
			right_box,
			"BERHASIL! 🎉" if phase == "won" else "BOOM! 💥",
			30,
			TEAL if phase == "won" else PINK
		)
		_label(
			right_box,
			"Bom berhasil dijinakkan." if phase == "won" else "Tiga kesalahan atau waktu habis.",
			18,
			INK
		)
		if solo or multiplayer.is_server():
			_button(right_box, "MAIN LAGI", func(): _start_round())
		return
	if solo:
		_label(right_box, "LATIHAN: GANTI PERAN", 14, YELLOW)
		var choices := OptionButton.new()
		for role in ROLES:
			choices.add_item(role)
		choices.select(solo_role)
		choices.item_selected.connect(
			func(index: int):
				solo_role = index
				_push_views()
		)
		right_box.add_child(choices)
		_label(
			right_box,
			"Lihat petunjuk setiap peran, lalu kembali ke Teknisi untuk menekan tombol.",
			13,
			MUTED
		)
	var role_index: int = local_view["role_index"]
	if role_index == 2:
		_render_manual()
	else:
		_render_modules(role_index == 0)


func _render_manual() -> void:
	_label(right_box, "📖  MANUAL RAHASIA", 24, YELLOW)
	_label(
		right_box,
		(
			"Hanya kamu yang tahu aturan. Tanyakan nomor seri dan warna "
			+ "kepada Pengamat, lalu beri isyarat kepada tim."
		),
		15,
		INK
	)
	_section("01 / KABEL")
	_label(
		right_box,
		(
			"Jika angka terakhir nomor seri GENAP: potong kabel MERAH paling kiri. "
			+ "Jika GANJIL: potong kabel BIRU paling kanan."
		),
		16,
		INK
	)
	_section("02 / SIMBOL")
	_label(
		right_box,
		(
			"Nomor seri GENAP: ★ BINTANG → ◆ WAJIK → ☾ BULAN.\n"
			+ "Nomor seri GANJIL: ☾ BULAN → ◆ WAJIK → ★ BINTANG."
		),
		16,
		INK
	)
	_section("03 / SAKLAR")
	_label(
		right_box,
		"Lampu MERAH: ON / OFF / ON\nLampu BIRU: OFF / ON / ON\nLampu HIJAU: ON / ON / OFF",
		16,
		INK
	)
	_section("KIRIM ISYARAT")
	for gesture in GESTURES:
		var token: String = gesture
		_button(right_box, token, func(): _send_message(token, true), true, 40)


func _render_modules(can_touch: bool) -> void:
	var stage: int = local_view["stage"]
	_label(right_box, "PANEL BOM  /  TAHAP %d" % (stage + 1), 22, YELLOW)
	if can_touch:
		_label(
			right_box,
			(
				"Kamu dapat meraba bentuk dan posisi, tetapi tidak melihat warna "
				+ "atau angka di layar. Minta arahan tim."
			),
			14,
			MUTED
		)
	else:
		_label(
			right_box,
			(
				"NOMOR SERI ··· %d      SINYAL · %s"
				% [int(local_view["digit"]), str(local_view["beacon"]).to_upper()]
			),
			17,
			TEAL
		)
		_label(
			right_box,
			"Jelaskan warna, bentuk, dan nomor seri kepada tim. Kamu tidak dapat menekan modul.",
			14,
			MUTED
		)
	_section("01 / POTONG KABEL" + ("   ✓" if stage > 0 else ""))
	var wire_row := HBoxContainer.new()
	wire_row.add_theme_constant_override("separation", 6)
	right_box.add_child(wire_row)
	for i in range(4):
		var slot := i
		var color_name := "?" if can_touch else str(local_view["wires"][i]).to_upper()
		_button(
			wire_row,
			"%s\n%s" % [char(65 + i), color_name],
			func(): _request_action("wire", slot),
			can_touch and stage == 0,
			78
		)
	_section("02 / URUTAN SIMBOL" + ("   ✓" if stage > 1 else ""))
	_label(right_box, "Masukan: %d / 3" % int(local_view["glyph_progress"]), 13, MUTED)
	var glyph_row := HBoxContainer.new()
	glyph_row.add_theme_constant_override("separation", 6)
	right_box.add_child(glyph_row)
	for i in range(3):
		var slot := i
		var glyph_name: String = local_view["glyphs"][i]
		var mark := "★" if glyph_name == "bintang" else ("◆" if glyph_name == "wajik" else "☾")
		_button(
			glyph_row,
			"%s\n%s" % [mark, str(i + 1)],
			func(): _request_action("glyph", slot),
			can_touch and stage == 1,
			80
		)
	_section("03 / ATUR SAKLAR" + ("   ✓" if stage > 2 else ""))
	var switch_row := HBoxContainer.new()
	switch_row.add_theme_constant_override("separation", 6)
	right_box.add_child(switch_row)
	for i in range(3):
		var slot := i
		var state := "ON" if local_view["switches"][i] else "OFF"
		_button(
			switch_row,
			"%d\n%s" % [i + 1, state],
			func(): _request_action("toggle", slot),
			can_touch and stage == 2,
			80
		)
	_button(
		right_box,
		"KONFIRMASI SAKLAR",
		func(): _request_action("confirm", 0),
		can_touch and stage == 2
	)


func _section(value: String) -> void:
	_spacer(right_box, 8)
	_label(right_box, value, 17, YELLOW)


func _label(parent: Node, value: String, font_size := 16, color := INK) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _spacer(parent: Node, height := 8) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	parent.add_child(spacer)


func _button(
	parent: Node, caption: String, callback: Callable, enabled := true, min_width := 0
) -> Button:
	var button := Button.new()
	button.text = caption
	button.disabled = not enabled
	button.custom_minimum_size = Vector2(min_width, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 15)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("24445a")
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color("37637b")
	button.add_theme_stylebox_override("hover", hover)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("142437")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("9fb5c4")
	settings.ambient_light_energy = 0.75
	environment.environment = settings
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -24, 0)
	sun.light_energy = 0.9
	sun.light_color = Color("ffdfaa")
	add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 3.8, 1.5)
	lamp.light_energy = 2.2
	lamp.omni_range = 9
	lamp.light_color = Color("80f2d3")
	add_child(lamp)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 3.5, 7.5)
	camera.look_at(Vector3(0, 1.25, 0))
	camera.fov = 53
	camera.current = true
	add_child(camera)

	_box(self, Vector3(18, 0.12, 13), Color("25384a"), Vector3(0, -0.12, 0))
	_box(self, Vector3(18, 5, 0.25), Color("1e3445"), Vector3(0, 2.25, -4.7))
	_box(self, Vector3(0.14, 4.3, 13), Color("223b4c"), Vector3(-7, 2.1, 0))
	_box(self, Vector3(0.14, 4.3, 13), Color("223b4c"), Vector3(7, 2.1, 0))
	_box(self, Vector3(8.4, 0.18, 3.15), Color("a8774d"), Vector3(0, 0.98, 0))
	for x in [-3.3, 3.3]:
		for z in [-1.15, 1.15]:
			_box(self, Vector3(0.25, 1.0, 0.25), Color("554137"), Vector3(x, 0.45, z))
	for x in [-5.1, -3.8, 3.8, 5.1]:
		_box(self, Vector3(0.65, 0.9, 0.65), Color("3b5964"), Vector3(x, 0.39, -3.7))
	for x in [-4.0, 0.0, 4.0]:
		_box(self, Vector3(1.8, 0.08, 0.06), Color("63babb"), Vector3(x, 3.6, -4.5))

	_monkey(Vector3(-2.65, 1.05, -0.25), Color("efaa67"))
	_monkey(Vector3(2.65, 1.05, -0.25), Color("a78ac5"))
	_monkey(Vector3(0, 1.0, -2.6), Color("eac064"))
	bomb_visual = Node3D.new()
	add_child(bomb_visual)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.62
	return material


func _box(parent: Node3D, size: Vector3, color: Color, location: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = _material(color)
	instance.position = location
	parent.add_child(instance)
	return instance


func _sphere(parent: Node3D, scale_value: Vector3, color: Color, location: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = SphereMesh.new()
	instance.material_override = _material(color)
	instance.position = location
	instance.scale = scale_value
	parent.add_child(instance)


func _monkey(origin: Vector3, fur: Color) -> void:
	var figure := Node3D.new()
	figure.position = origin
	add_child(figure)
	_sphere(figure, Vector3(0.46, 0.59, 0.36), fur, Vector3(0, 0.3, 0))
	_sphere(figure, Vector3(0.52, 0.5, 0.44), fur, Vector3(0, 1.0, 0.1))
	for side in [-1.0, 1.0]:
		_sphere(figure, Vector3(0.20, 0.22, 0.12), fur, Vector3(side * 0.53, 1.05, 0.09))
		_sphere(
			figure, Vector3(0.11, 0.12, 0.06), Color("f3d3ab"), Vector3(side * 0.54, 1.04, 0.18)
		)
		_sphere(
			figure, Vector3(0.085, 0.12, 0.05), Color("17222d"), Vector3(side * 0.18, 1.12, 0.49)
		)
	_sphere(figure, Vector3(0.34, 0.28, 0.09), Color("f1d2a4"), Vector3(0, 0.87, 0.47))
	_sphere(figure, Vector3(0.09, 0.05, 0.045), Color("49342c"), Vector3(0, 0.85, 0.55))


func _wire(parent: Node3D, color: Color, location: Vector3) -> void:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.055
	mesh.bottom_radius = 0.055
	mesh.height = 0.66
	instance.mesh = mesh
	instance.material_override = _material(color)
	instance.position = location
	instance.rotation.x = PI / 2.0
	parent.add_child(instance)


func _render_bomb() -> void:
	if bomb_visual == null:
		return
	var phase: String = local_view.get("phase", "menu")
	var relevant := (
		"%s:%s:%s"
		% [phase, str(local_view.get("role_index", -1)), str(local_view.get("wires", []))]
	)
	if board_signature == relevant:
		return
	board_signature = relevant
	_clear(bomb_visual)
	bomb_visual.visible = not (phase == "playing" and int(local_view.get("role_index", 0)) == 2)
	_box(bomb_visual, Vector3(2.3, 0.52, 1.52), Color("222c38"), Vector3(0, 1.37, 0))
	_box(bomb_visual, Vector3(1.66, 0.08, 0.42), Color("344f60"), Vector3(0, 1.67, -0.48))
	for i in range(4):
		var color := Color("adb5ae")
		if int(local_view.get("role_index", -1)) == 1 and local_view.has("wires"):
			match str(local_view["wires"][i]):
				"merah":
					color = Color("f07b80")
				"biru":
					color = Color("74b7eb")
				"kuning":
					color = Color("f8d76c")
				"hijau":
					color = Color("6adab2")
		_wire(bomb_visual, color, Vector3(-0.72 + i * 0.48, 1.7, -0.1))
	for i in range(3):
		_sphere(
			bomb_visual,
			Vector3(0.15, 0.07, 0.15),
			Color("f4d36b"),
			Vector3(-0.48 + i * 0.48, 1.70, 0.42)
		)
	var glow := (
		Color("68dcc0")
		if phase == "won"
		else (Color("f47880") if phase == "lost" else Color("ffd15f"))
	)
	_sphere(bomb_visual, Vector3(0.13, 0.13, 0.13), glow, Vector3(1.05, 1.75, 0.6))
