note
	description: "[
		The request handler simple_web creates for every request, on the
		processor that serves it (SIMPLE_WEB_HANDLER_SERVER, SCOOP-clean).
		`setup_routes' is the one list of the API's routes; each is served
		by a CHAT_API built for this request. Phase 1b gives that CHAT_API
		its `separate CHAT_SERVICE' (the one service processor) through the
		application's once ("PROCESS"); until then every route answers 501.
	]"
	author: "Larry Rix"

class
	CHAT_REQUEST_HANDLER

inherit
	SIMPLE_WEB_REQUEST_HANDLER

	SIMPLE_WEB_SHARED

create
	make

feature {NONE} -- Setup

	setup_routes
			-- The API surface (06-INTERFACE-DESIGN + spec/10): every route, in one place.
		do
			routes.on_get ("/health", agent not_yet)
			routes.on_post ("/login", agent not_yet)
			routes.on_post ("/logout", agent not_yet)
			routes.on_get ("/rooms", agent not_yet)
			routes.on_get ("/rooms/{id}/events", agent not_yet)
			routes.on_get ("/rooms/{id}/wait", agent not_yet)
			routes.on_get ("/rooms/{id}/stream", agent not_yet)
			routes.on_get ("/rooms/{id}/members", agent not_yet)
			routes.on_post ("/rooms/{id}/messages", agent not_yet)
			routes.on_post ("/rooms/{id}/images", agent not_yet)
			routes.on_get ("/attachments/{id}", agent not_yet)
			routes.on_get ("/me", agent not_yet)
			routes.on_post ("/me/password", agent not_yet)
			routes.on_get ("/participants", agent not_yet)
			routes.on_get ("/admin/users", agent not_yet)
			routes.on_post ("/admin/users", agent not_yet)
			routes.on_post ("/admin/users/{id}/password", agent not_yet)
			routes.on_post ("/admin/bots", agent not_yet)
			routes.on_delete ("/admin/bots/{id}/token", agent not_yet)
			routes.on_post ("/admin/backup", agent not_yet)
		ensure then
			all_registered: routes.count = Route_count
			health_reachable: routes.has_route ("GET", {STRING_32} "/health")
			wait_reachable: routes.has_route ("GET", {STRING_32} "/rooms/1/wait")
		end

feature -- Constants

	Route_count: INTEGER = 20

feature {NONE} -- Implementation

	not_yet (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- Phase 1: every route answers 501; Phase 1b routes to a per-request CHAT_API.
		do
			a_response.send_error (501, "Not implemented (Phase 1 skeleton)")
		end

end
