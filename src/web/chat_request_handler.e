note
	description: "[
		The request handler simple_web creates for every request, on the
		processor that serves it (SIMPLE_WEB_HANDLER_SERVER, D1). It reads
		the HTTP side - the Bearer token, path and query parameters, the
		JSON body - and answers through the one CHAT_API on the service's
		processor, copying each CHAT_REPLY back as bytes. `setup_routes'
		is the single list of the API's routes.

		The long-poll lives here: a POLL_WAITER on its own processor is
		subscribed to the room, the page is read, and if it is empty the
		handler blocks on the waiter through POLL_WAIT's wait condition
		until the bus wakes it or a POLL_ALARM times it out.
	]"
	author: "Larry Rix"

class
	CHAT_REQUEST_HANDLER

inherit
	SIMPLE_WEB_REQUEST_HANDLER

	CHAT_SHARED

create
	make

feature {NONE} -- Setup

	setup_routes
			-- The API surface (06-INTERFACE-DESIGN + spec/10): every route, in one place.
		do
			create codec.make
			routes.on_get ("/health", agent handle_health)
			routes.on_post ("/login", agent handle_login)
			routes.on_post ("/logout", agent handle_logout)
			routes.on_get ("/rooms", agent handle_rooms)
			routes.on_get ("/rooms/{id}/events", agent handle_events)
			routes.on_get ("/rooms/{id}/wait", agent handle_wait)
			routes.on_get ("/rooms/{id}/stream", agent handle_stream)
			routes.on_get ("/rooms/{id}/members", agent handle_members)
			routes.on_post ("/rooms/{id}/messages", agent handle_post_message)
			routes.on_post ("/rooms/{id}/images", agent handle_post_image)
			routes.on_get ("/attachments/{id}", agent handle_attachment)
			routes.on_get ("/me", agent handle_me)
			routes.on_post ("/me/password", agent handle_change_password)
			routes.on_get ("/participants", agent handle_participants)
			routes.on_get ("/admin/users", agent handle_admin_users)
			routes.on_post ("/admin/users", agent handle_admin_create_user)
			routes.on_post ("/admin/users/{id}/password", agent handle_admin_reset_password)
			routes.on_post ("/admin/bots", agent handle_admin_create_bot)
			routes.on_delete ("/admin/bots/{id}/token", agent handle_admin_revoke_bot)
			routes.on_post ("/admin/backup", agent handle_admin_backup)
		ensure then
			all_registered: routes.count = Route_count
			health_reachable: routes.has_route ("GET", {STRING_32} "/health")
			wait_reachable: routes.has_route ("GET", {STRING_32} "/rooms/1/wait")
		end

feature -- Request reading (contract support)

	bearer_token (a_request: SIMPLE_WEB_SERVER_REQUEST): detachable STRING_8
			-- The 64 hex characters after "Bearer " (case-insensitive scheme), or Void.
		do
			if attached a_request.header ("Authorization") as h and then h.count = Bearer_prefix.count + Token_length
				and then h.substring (1, Bearer_prefix.count).is_case_insensitive_equal (Bearer_prefix)
			then
				Result := h.substring (Bearer_prefix.count + 1, h.count)
				if not is_hex (Result) then
					Result := Void
				end
			end
		ensure
			shape: attached Result as t implies (t.count = Token_length and is_hex (t))
		end

	client_ip (a_request: SIMPLE_WEB_SERVER_REQUEST): STRING_8
			-- The peer address, or the rightmost X-Forwarded-For entry when the peer is the door (DR-010).
			-- Phase 4: simple_web must expose the peer address; until then the peer is taken as local.
		do
			if trusts_forwarded_headers (a_request) and then attached a_request.header ("X-Forwarded-For") as f and then not f.is_empty then
				Result := rightmost_address (f)
			else
				Result := Loopback
			end
		ensure
			given: not Result.is_empty
			peer_when_untrusted: not trusts_forwarded_headers (a_request) implies Result.same_string (Loopback)
		end

	trusts_forwarded_headers (a_request: SIMPLE_WEB_SERVER_REQUEST): BOOLEAN
			-- Only when the immediate peer is 127.0.0.1 (the door). Phase 4: the peer address.
		do
			Result := False
		end

	room_id_of (a_request: SIMPLE_WEB_SERVER_REQUEST): INTEGER_64
			-- The {id} path parameter; 0 when absent or not a positive integer.
		do
			if attached a_request.path_parameter ("id") as p and then p.is_integer_64 then
				Result := p.to_integer_64.max (0)
			end
		ensure
			non_negative: Result >= 0
		end

	integer_query (a_request: SIMPLE_WEB_SERVER_REQUEST; a_name: READABLE_STRING_8; a_default: INTEGER_64): INTEGER_64
			-- The query parameter `a_name' as an integer, else `a_default'.
		do
			Result := a_default
			if attached a_request.query_parameter (a_name) as q and then q.is_integer_64 then
				Result := q.to_integer_64
			end
		end

	json_body (a_request: SIMPLE_WEB_SERVER_REQUEST): detachable SIMPLE_JSON_OBJECT
			-- The body as a JSON object, or Void.
		do
			Result := codec.object_from_bytes (a_request.body)
		end

	json_string (a_object: detachable SIMPLE_JSON_OBJECT; a_key: STRING_32): STRING_32
			-- The string under `a_key', or empty.
		do
			if attached a_object as o and then attached o.string_item (a_key) as s then
				Result := s
			else
				create Result.make_empty
			end
		end

	is_hex (a_text: READABLE_STRING_8): BOOLEAN
		do
			Result := across a_text as ch all (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f') end
		end

	rightmost_address (a_list: READABLE_STRING_8): STRING_8
			-- The last comma-separated entry of `a_list', trimmed; the door appends the true peer last.
		require
			given: not a_list.is_empty
		local
			l_parts: LIST [READABLE_STRING_8]
		do
			l_parts := a_list.split (',')
			create Result.make_from_string (l_parts.last)
			Result.left_adjust
			Result.right_adjust
			if Result.is_empty then
				Result := Loopback
			end
		ensure
			given: not Result.is_empty
		end

feature -- Constants

	Route_count: INTEGER = 20
	Token_length: INTEGER = 64
	Bearer_prefix: STRING_8 = "Bearer "
	Loopback: STRING_8 = "127.0.0.1"
	Default_page: INTEGER_64 = 100
	Page_maximum: INTEGER_64 = 500
	Default_wait_seconds: INTEGER_64 = 25
	Max_wait_seconds: INTEGER_64 = 25
	Empty_array: STRING_8 = "[]"

feature {NONE} -- Handlers

	handle_health (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			reply (a_response, api_health (shared_api))
		end

	handle_login (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		local
			l_body: detachable SIMPLE_JSON_OBJECT
		do
			l_body := json_body (a_request)
			reply (a_response, api_login (shared_api, json_string (l_body, "username"), json_string (l_body, "password"), client_ip (a_request)))
		end

	handle_logout (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			if attached bearer_token (a_request) as t then
				reply (a_response, api_logout (shared_api, t))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_rooms (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			if attached bearer_token (a_request) as t then
				reply (a_response, api_rooms (shared_api, t))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_events (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- ?since=N (ascending after N) or ?before=N (history), &limit=M.
		local
			l_room: INTEGER_64
			l_limit: INTEGER
		do
			l_room := room_id_of (a_request)
			l_limit := integer_query (a_request, "limit", Default_page).max (1).min (Page_maximum).to_integer_32
			if not attached bearer_token (a_request) as t then
				reply (a_response, unauthorized_reply)
			elseif l_room = 0 then
				reply (a_response, bad_request_reply ("room id"))
			elseif a_request.has_query_parameter ("before") then
				reply (a_response, api_events_before (shared_api, t, l_room, integer_query (a_request, "before", 0).max (1), l_limit))
			else
				reply (a_response, api_events (shared_api, t, l_room, integer_query (a_request, "since", 0).max (0), l_limit, Empty_array))
			end
		end

	handle_wait (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- The long-poll (D-018): answer at once when there is news after `since';
			-- otherwise wait on the doorbell up to `seconds' (<= 25) and answer what came.
		local
			l_room, l_since: INTEGER_64
			l_limit, l_seconds, l_ticket: INTEGER
			l_waiter: separate POLL_WAITER
			l_alarm: separate POLL_ALARM
			l_wait: POLL_WAIT
			l_reply: CHAT_REPLY
		do
			l_room := room_id_of (a_request)
			if not attached bearer_token (a_request) as t then
				reply (a_response, unauthorized_reply)
			elseif l_room = 0 then
				reply (a_response, bad_request_reply ("room id"))
			else
				l_since := integer_query (a_request, "since", 0).max (0)
				l_limit := integer_query (a_request, "limit", Default_page).max (1).min (Page_maximum).to_integer_32
				l_seconds := integer_query (a_request, "seconds", Default_wait_seconds).max (0).min (Max_wait_seconds).to_integer_32
				create l_waiter.make (l_room)
				l_ticket := api_subscribe (shared_api, t, l_room, l_waiter)
				if l_ticket = 0 then
					l_reply := api_events (shared_api, t, l_room, l_since, l_limit, Empty_array)
				else
					l_reply := api_events (shared_api, t, l_room, l_since, l_limit, Empty_array)
					if l_reply.is_empty_page and l_seconds > 0 then
						create l_alarm.make (l_waiter, l_seconds)
						start_alarm (l_alarm)
						create l_wait.make
						l_wait.wait_for (l_waiter)
						l_reply := api_events (shared_api, t, l_room, l_since, l_limit, l_wait.statuses_json)
					end
					api_unsubscribe (shared_api, l_ticket)
				end
				reply (a_response, l_reply)
			end
		end

	handle_stream (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- SSE for bots and curl: the same waiter loop as `handle_wait', repeated,
			-- over a WEB_STREAM_SINK - needs simple_web's streaming response (Phase 4, Spike A).
		do
			reply (a_response, not_yet_reply)
		end

	handle_members (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			if attached bearer_token (a_request) as t then
				reply (a_response, api_members (shared_api, t, room_id_of (a_request)))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_post_message (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			if attached bearer_token (a_request) as t then
				reply (a_response, api_post_message (shared_api, t, room_id_of (a_request), json_string (json_body (a_request), "body")))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_post_image (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- The raw body is the image; X-File-Name and X-Caption carry the rest (Phase 4 may add multipart).
		local
			l_name, l_caption: STRING_32
		do
			if attached bearer_token (a_request) as t then
				l_name := header_32 (a_request, "X-File-Name")
				l_caption := header_32 (a_request, "X-Caption")
				reply (a_response, api_post_image (shared_api, t, room_id_of (a_request), a_request.body, l_name, l_caption))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_attachment (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			if attached bearer_token (a_request) as t then
				reply (a_response, api_attachment (shared_api, t, room_id_of (a_request)))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_me (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			if attached bearer_token (a_request) as t then
				reply (a_response, api_me (shared_api, t))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_change_password (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		local
			l_body: detachable SIMPLE_JSON_OBJECT
		do
			if attached bearer_token (a_request) as t then
				l_body := json_body (a_request)
				reply (a_response, api_change_password (shared_api, t, json_string (l_body, "old"), json_string (l_body, "new")))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_participants (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			if attached bearer_token (a_request) as t then
				reply (a_response, api_participants (shared_api, t))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_admin_users (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			if attached bearer_token (a_request) as t then
				reply (a_response, api_admin_users (shared_api, t))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_admin_create_user (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		local
			l_body: detachable SIMPLE_JSON_OBJECT
		do
			if attached bearer_token (a_request) as t then
				l_body := json_body (a_request)
				reply (a_response, api_admin_create_user (shared_api, t, ascii_of (json_string (l_body, "username")), json_string (l_body, "display_name"),
					json_string (l_body, "password"), attached l_body as b and then b.boolean_item ("is_admin")))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_admin_reset_password (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			if attached bearer_token (a_request) as t then
				reply (a_response, api_admin_reset_password (shared_api, t, room_id_of (a_request), json_string (json_body (a_request), "password")))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_admin_create_bot (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		local
			l_body: detachable SIMPLE_JSON_OBJECT
		do
			if attached bearer_token (a_request) as t then
				l_body := json_body (a_request)
				reply (a_response, api_admin_create_bot (shared_api, t, ascii_of (json_string (l_body, "username")), json_string (l_body, "display_name")))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_admin_revoke_bot (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			if attached bearer_token (a_request) as t then
				reply (a_response, api_admin_revoke_bot (shared_api, t, room_id_of (a_request)))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_admin_backup (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			if attached bearer_token (a_request) as t then
				reply (a_response, api_admin_backup (shared_api, t))
			else
				reply (a_response, unauthorized_reply)
			end
		end

feature {NONE} -- The API's processor (each routine holds the API only for its call)

	api_health (a_api: separate CHAT_API): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.health)
		end

	api_login (a_api: separate CHAT_API; a_username, a_password: STRING_32; a_client_ip: STRING_8): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.login (a_username, a_password, a_client_ip))
		end

	api_logout (a_api: separate CHAT_API; a_token: STRING_8): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.logout (a_token))
		end

	api_rooms (a_api: separate CHAT_API; a_token: STRING_8): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.rooms (a_token))
		end

	api_me (a_api: separate CHAT_API; a_token: STRING_8): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.me (a_token))
		end

	api_events (a_api: separate CHAT_API; a_token: STRING_8; a_room_id, a_since_id: INTEGER_64; a_limit: INTEGER; a_statuses_json: STRING_8): CHAT_REPLY
		require
			since_non_negative: a_since_id >= 0
			limit_in_range: a_limit > 0 and a_limit <= Page_maximum
		do
			create Result.make_from_separate (a_api.events (a_token, a_room_id, a_since_id, a_limit, a_statuses_json))
		end

	api_events_before (a_api: separate CHAT_API; a_token: STRING_8; a_room_id, a_before_id: INTEGER_64; a_limit: INTEGER): CHAT_REPLY
		require
			before_positive: a_before_id > 0
			limit_in_range: a_limit > 0 and a_limit <= Page_maximum
		do
			create Result.make_from_separate (a_api.events_before (a_token, a_room_id, a_before_id, a_limit))
		end

	api_subscribe (a_api: separate CHAT_API; a_token: STRING_8; a_room_id: INTEGER_64; a_waiter: separate POLL_WAITER): INTEGER
			-- The ticket, or 0 when refused.
		do
			a_api.subscribe (a_token, a_room_id, a_waiter)
			Result := a_api.last_subscription
		ensure
			non_negative: Result >= 0
		end

	api_unsubscribe (a_api: separate CHAT_API; a_ticket: INTEGER)
		do
			a_api.unsubscribe (a_ticket)
		end

	api_members (a_api: separate CHAT_API; a_token: STRING_8; a_room_id: INTEGER_64): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.members (a_token, a_room_id))
		end

	api_participants (a_api: separate CHAT_API; a_token: STRING_8): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.participants (a_token))
		end

	api_attachment (a_api: separate CHAT_API; a_token: STRING_8; a_attachment_id: INTEGER_64): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.attachment (a_token, a_attachment_id))
		end

	api_post_message (a_api: separate CHAT_API; a_token: STRING_8; a_room_id: INTEGER_64; a_body: STRING_32): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.post_message (a_token, a_room_id, a_body))
		end

	api_post_image (a_api: separate CHAT_API; a_token: STRING_8; a_room_id: INTEGER_64; a_bytes: STRING_8; a_file_name, a_caption: STRING_32): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.post_image (a_token, a_room_id, a_bytes, a_file_name, a_caption))
		end

	api_change_password (a_api: separate CHAT_API; a_token: STRING_8; a_old, a_new: STRING_32): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.change_password (a_token, a_old, a_new))
		end

	api_admin_users (a_api: separate CHAT_API; a_token: STRING_8): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.admin_users (a_token))
		end

	api_admin_create_user (a_api: separate CHAT_API; a_token, a_username: STRING_8; a_display_name, a_password: STRING_32; a_is_admin: BOOLEAN): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.admin_create_user (a_token, a_username, a_display_name, a_password, a_is_admin))
		end

	api_admin_reset_password (a_api: separate CHAT_API; a_token: STRING_8; a_user_id: INTEGER_64; a_password: STRING_32): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.admin_reset_password (a_token, a_user_id, a_password))
		end

	api_admin_create_bot (a_api: separate CHAT_API; a_token, a_username: STRING_8; a_display_name: STRING_32): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.admin_create_bot (a_token, a_username, a_display_name))
		end

	api_admin_revoke_bot (a_api: separate CHAT_API; a_token: STRING_8; a_bot_id: INTEGER_64): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.admin_revoke_bot (a_token, a_bot_id))
		end

	api_admin_backup (a_api: separate CHAT_API; a_token: STRING_8): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.admin_backup (a_token))
		end

	start_alarm (a_alarm: separate POLL_ALARM)
			-- Asynchronous: the alarm sleeps on its own processor.
		do
			a_alarm.start
		end

feature {NONE} -- Replies

	reply (a_response: SIMPLE_WEB_SERVER_RESPONSE; a_reply: CHAT_REPLY)
			-- Write `a_reply' out: status, nosniff, the bytes with their type.
		do
			a_response.set_status (a_reply.status)
			a_response.set_header ("X-Content-Type-Options", "nosniff")
			a_response.send_binary (a_reply.body, a_reply.content_type)
		end

	unauthorized_reply: CHAT_REPLY
		do
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_bad_credentials, "a valid Bearer token is required", 401))
		end

	bad_request_reply (a_what: READABLE_STRING_8): CHAT_REPLY
		require
			given: not a_what.is_empty
		do
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_refused, "missing or invalid " + a_what, 400))
		end

	not_yet_reply: CHAT_REPLY
		do
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501))
		end

	header_32 (a_request: SIMPLE_WEB_SERVER_REQUEST; a_name: READABLE_STRING_8): STRING_32
			-- A header decoded from UTF-8, or empty.
		do
			if attached a_request.header (a_name) as h then
				Result := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (h)
			else
				create Result.make_empty
			end
		end

	ascii_of (a_text: READABLE_STRING_32): STRING_8
			-- `a_text' when it is plain ASCII, else empty (usernames are [a-z0-9_]).
		do
			if across a_text as c all c.natural_32_code < 128 end then
				Result := a_text.to_string_8
			else
				create Result.make_empty
			end
		end

feature {NONE} -- Implementation

	codec: CHAT_JSON

end
