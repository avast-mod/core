#       .:       .::         .::            .:: ::    .::
#      .: ::      .::       .::           .::    .::  .::
#     .:  .::      .::     .::     .::     .::      .:.: .:
#    .::   .::      .::   .::    .::  .::    .::      .::
#   .:::::: .::      .:: .::    .::   .::       .::   .::
#  .::       .::      .::::     .::   .:: .::    .::  .::
# .::         .::      .::        .:: .:::  .:: ::     .::
#
# AVaSt - https://github.com/avast-mod
#
# lets the website and the admin panel ask the running game to open a mod in the AVaSt window.
#
# listens on 127.0.0.1 only and only answers pages from the avast sites (checks Origin), so random
# websites cant poke it.
#   GET /ping           {"ok": 1, "ready": true}   ready is false during a run
#   GET /open?mod=<id>  {"ok": 1}, or {"busy": 1} during a run
# game not running? the page falls back to steam://run/<app>//--avast-mod=<id>/ , see mod.gd

extends Node

const PORT := 40203
const SITES := [
	"https://avast.malidev.zip",
	"https://avast.malidev-xp-desktop.workers.dev",
]
const _TIMEOUT_MS := 3000
const _MAX_REQUEST := 8192

var _core: Node
var _server := TCPServer.new()
var _clients: Array = []

func setup(core: Node) -> void:
	_core = core
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _server.listen(PORT, "127.0.0.1") != OK:
		_core.warn("link: port %d is taken, so websites can't open mods in AVaSt" % PORT)
		set_process(false)

func _exit_tree() -> void:
	_server.stop()

func _process(_delta: float) -> void:
	while _server.is_connection_available():
		_clients.append({"peer": _server.take_connection(), "data": PackedByteArray(), "since": Time.get_ticks_msec()})
	for client: Dictionary in _clients.duplicate():
		var peer: StreamPeerTCP = client.peer
		peer.poll()
		var connected := peer.get_status() == StreamPeerTCP.STATUS_CONNECTED
		if connected:
			var waiting := peer.get_available_bytes()
			if waiting > 0:
				client.data.append_array(peer.get_data(waiting)[1])
		var text: String = client.data.get_string_from_utf8()
		var done := connected and text.contains("\r\n\r\n")
		if done:
			_answer(peer, text)
		if done or not connected or client.data.size() > _MAX_REQUEST or Time.get_ticks_msec() - client.since > _TIMEOUT_MS:
			peer.disconnect_from_host()
			_clients.erase(client)

func _answer(peer: StreamPeerTCP, text: String) -> void:
	var lines := text.split("\r\n")
	var request := lines[0].split(" ")
	var headers := {}
	for line in lines.slice(1):
		var colon := line.find(":")
		if colon > 0:
			headers[line.substr(0, colon).strip_edges().to_lower()] = line.substr(colon + 1).strip_edges()
	var origin := str(headers.get("origin", ""))
	if request.size() < 2 or not _sites().has(origin):
		_send(peer, 403, {}, "")
		return
	var cors := {
		"Access-Control-Allow-Origin": origin,
		"Access-Control-Allow-Methods": "GET",
		"Access-Control-Allow-Private-Network": "true",
		"Vary": "Origin",
	}
	if request[0] == "OPTIONS":
		_send(peer, 204, cors, "")
		return
	var path := request[1].split("?")[0]
	var query := request[1].get_slice("?", 1) if request[1].contains("?") else ""
	if request[0] == "GET" and path == "/ping":
		_send(peer, 200, cors, JSON.stringify({"ok": 1, "ready": _core.can_show_mods()}))
	elif request[0] == "GET" and path == "/open":
		var id := ""
		for pair in query.split("&"):
			if pair.begins_with("mod="):
				id = pair.substr(4).uri_decode()
		if not RegEx.create_from_string("^[a-z0-9_]{2,40}$").search(id):
			_send(peer, 400, cors, JSON.stringify({"e": "Unknown mod."}))
		elif _core.show_mod(id):
			_core.info("link: a page opened %s in AVaSt" % id)
			_send(peer, 200, cors, JSON.stringify({"ok": 1}))
		else:
			_send(peer, 200, cors, JSON.stringify({"busy": 1}))
	else:
		_send(peer, 404, cors, "")

func _sites() -> Array:
	var sites := SITES.duplicate()
	var store: String = _core.store.url()
	var scheme_end := store.find("://")
	if scheme_end > 0:
		var host_end := store.find("/", scheme_end + 3)
		sites.append(store.substr(0, host_end) if host_end > 0 else store)
	if store.begins_with("http://127.0.0.1:"):
		sites.append("http://127.0.0.1:8787")
	return sites

func _send(peer: StreamPeerTCP, code: int, headers: Dictionary, body: String) -> void:
	var reason: String = {200: "OK", 204: "No Content", 400: "Bad Request", 403: "Forbidden", 404: "Not Found"}.get(code, "OK")
	var bytes := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n" % [code, reason, bytes.size()]
	for key: String in headers:
		head += "%s: %s\r\n" % [key, headers[key]]
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data((head + "\r\n").to_utf8_buffer() + bytes)
