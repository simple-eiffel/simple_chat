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
			routes.on_post ("/rooms/{id}/summary", agent handle_summary)
			routes.on_post ("/rooms/{id}/messages/{eid}/edit", agent handle_edit_message)
			routes.on_post ("/rooms/{id}/messages/{eid}/delete", agent handle_delete_message)
			routes.on_post ("/rooms/{id}/messages/{eid}/reactions", agent handle_react)
			routes.on_post ("/rooms/{id}/messages/{eid}/replies", agent handle_reply)
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
			-- The peer address, or the rightmost X-Forwarded-For entry when the
			-- peer is the door (DR-010): `client_address' with this process's
			-- configuration. Different clients land in different lockout
			-- buckets now that simple_web reports the peer (M-F closed).
		do
			Result := client_address (a_request, api_is_public (shared_api))
		ensure
			given: not Result.is_empty
			peer_when_untrusted: not trusts_forwarded_headers (a_request) implies Result.same_string (peer_address (a_request))
			rightmost_when_trusted: (trusts_forwarded_headers (a_request) and then attached a_request.header ("X-Forwarded-For") as f and then not f.is_empty)
				implies Result.same_string (rightmost_address (f))
		end

	client_address (a_request: SIMPLE_WEB_SERVER_REQUEST; a_public: BOOLEAN): STRING_8
			-- The rule behind `client_ip', with the configuration's kind as an
			-- argument so it is testable without the process-wide API: when the
			-- immediate peer is the loopback door AND the server is public, the
			-- rightmost X-Forwarded-For entry wins (the door appends the true
			-- peer last); otherwise the peer itself, forwarded headers ignored.
		do
			if a_public and then peer_address (a_request).same_string (Loopback)
				and then attached a_request.header ("X-Forwarded-For") as l_forwarded and then not l_forwarded.is_empty
			then
				Result := rightmost_address (l_forwarded)
			else
				Result := peer_address (a_request)
			end
		ensure
			given: not Result.is_empty
			peer_when_not_door: not (a_public and peer_address (a_request).same_string (Loopback)) implies Result.same_string (peer_address (a_request))
		end

	peer_address (a_request: SIMPLE_WEB_SERVER_REQUEST): STRING_8
			-- The connection's peer as simple_web reports it; "local" when the
			-- connector supplies none (an in-process request), so the limiter
			-- always has a non-empty bucket key.
		do
			Result := a_request.remote_address
			if Result.is_empty then
				Result := Local_peer
			end
		ensure
			given: not Result.is_empty
			faithful: not a_request.remote_address.is_empty implies Result.same_string (a_request.remote_address)
		end

	trusts_forwarded_headers (a_request: SIMPLE_WEB_SERVER_REQUEST): BOOLEAN
			-- Only when the immediate peer is 127.0.0.1 (the door) and the
			-- configuration is public: exactly then the door speaks for the
			-- client (DR-010).
		do
			Result := peer_address (a_request).same_string (Loopback) and then api_is_public (shared_api)
		ensure
			definition: Result = (peer_address (a_request).same_string (Loopback) and api_is_public (shared_api))
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
			-- The body as a JSON object; Void when it is not one, or is larger than any
			-- lawful JSON request (`Max_json_body_bytes') - refused before parsing.
		do
			if a_request.body.count <= Max_json_body_bytes then
				Result := codec.object_from_bytes (a_request.body)
			end
		ensure
			bounded: attached Result implies a_request.body.count <= Max_json_body_bytes
		end

	Max_json_body_bytes: INTEGER = 65536
			-- Far above any lawful message (4000 characters of UTF-8 plus the envelope);
			-- image bytes travel on their own route with the upload limit, not here.

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

	Route_count: INTEGER = 25
	Token_length: INTEGER = 64
	Bearer_prefix: STRING_8 = "Bearer "
	Loopback: STRING_8 = "127.0.0.1"
	Local_peer: STRING_8 = "local"
	Sse_content_type: STRING_8 = "text/event-stream"
	Max_stream_seconds: INTEGER = 3600
			-- A stream's hard lifetime: EWF's standalone connector never reports
			-- a hung-up client (see WEB_STREAM_SINK), so without this bound a
			-- dead bot would pin its request processor forever. Clients
			-- reconnect with ?since= and lose nothing.
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
			l_failed: BOOLEAN
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
				if l_failed then
						-- The rescue below already unsubscribed; answer instead of dying subscribed.
					reply (a_response, failed_reply)
				else
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
		rescue
			if not l_failed then
				l_failed := True
				if l_ticket > 0 then
					api_unsubscribe (shared_api, l_ticket)
				end
				retry
			end
		end

	handle_stream (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- SSE for bots and curl: text/event-stream over simple_web's streaming
			-- response - the `handle_wait' choreography repeated over a
			-- WEB_STREAM_SINK. The request's processor is pinned for the
			-- stream's life: that is the design (bots and curl hold one
			-- connection each; people use /wait).
			--
			-- The stream ends when the connector reports the client gone (a
			-- raising connector; EWF's standalone one is silent - see
			-- WEB_STREAM_SINK), when membership is revoked (subscribe refused,
			-- or a later page refused), when page bytes go bad, or when
			-- `Max_stream_seconds' passes - the bound a silent connector makes
			-- necessary. Clients reconnect with ?since= and lose nothing.
		local
			l_room: INTEGER_64
			l_ticket: INTEGER
			l_waiter: separate POLL_WAITER
			l_alarm: separate POLL_ALARM
			l_wait: POLL_WAIT
			l_reply: CHAT_REPLY
			l_sink: WEB_STREAM_SINK
			l_stream: detachable SSE_STREAM
			l_deadline, l_now: SIMPLE_DATE_TIME
			l_failed: BOOLEAN
		do
			l_room := room_id_of (a_request)
			if l_failed then
				if not a_response.is_streaming then
					reply (a_response, failed_reply)
				end
					-- Mid-stream failure: the connection simply ends; the
					-- subscription was already released in the rescue.
			elseif not attached bearer_token (a_request) as t then
				reply (a_response, unauthorized_reply)
			elseif l_room = 0 then
				reply (a_response, bad_request_reply ("room id"))
			else
				l_reply := api_events (shared_api, t, l_room, integer_query (a_request, "since", 0).max (0), Default_page.to_integer_32, Empty_array)
				if l_reply.status /= 200 then
						-- Refused before any streaming: the error travels as plain JSON.
					reply (a_response, l_reply)
				else
					a_response.send_stream_head (200, Sse_content_type)
					create l_sink.make (a_response)
					create l_stream.make (l_sink)
					l_stream.open (l_room, integer_query (a_request, "since", 0).max (0))
					stream_page (l_stream, l_reply)
					l_deadline := (create {SIMPLE_DATE_TIME}.make_now).plus_seconds (Max_stream_seconds)
					from
						create l_now.make_now
					until
						not l_stream.is_open or l_deadline < l_now
					loop
						create l_waiter.make (l_room)
						l_ticket := api_subscribe (shared_api, t, l_room, l_waiter)
						if l_ticket = 0 then
								-- Membership revoked (or the room gone): the stream ends.
							l_stream.close
						else
							l_reply := api_events (shared_api, t, l_room, l_stream.last_delivered_id, Default_page.to_integer_32, Empty_array)
							if l_reply.is_empty_page then
								create l_alarm.make (l_waiter, Default_wait_seconds.to_integer_32)
								start_alarm (l_alarm)
								create l_wait.make
								l_wait.wait_for (l_waiter)
								l_reply := api_events (shared_api, t, l_room, l_stream.last_delivered_id, Default_page.to_integer_32, l_wait.statuses_json)
							end
							api_unsubscribe (shared_api, l_ticket)
							l_ticket := 0
							if l_stream.is_open then
								stream_page (l_stream, l_reply)
							end
						end
						create l_now.make_now
					end
					if l_stream.is_open then
						l_stream.close
					end
				end
			end
		rescue
			if not l_failed then
				l_failed := True
				if l_ticket > 0 then
					api_unsubscribe (shared_api, l_ticket)
					l_ticket := 0
				end
				if attached l_stream as s and then s.is_open then
					s.close
				end
				retry
			end
		end

	stream_page (a_stream: SSE_STREAM; a_reply: CHAT_REPLY)
			-- Decode a page reply and hand it to the stream: events and statuses
			-- deliver; a quiet page becomes a heartbeat (the connection is seen
			-- alive); anything that is not a well-formed 200 page ends the stream.
		require
			open: a_stream.is_open
		local
			l_page: detachable CHAT_PAGE
		do
			if a_reply.status = 200 then
				l_page := codec.page_from_bytes (a_reply.body)
			end
			if l_page = Void then
				a_stream.close
			elseif l_page.is_empty then
				a_stream.heartbeat
			elseif l_page.events.is_empty or else l_page.events.first.id > a_stream.last_delivered_id then
				a_stream.deliver (l_page)
			else
					-- A page that does not follow the cursor: end rather than repeat.
				a_stream.close
			end
		ensure
			cursor_never_backs: a_stream.last_delivered_id >= old a_stream.last_delivered_id
		end

	handle_members (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
		do
			if attached bearer_token (a_request) as t then
				reply (a_response, api_members (shared_api, t, room_id_of (a_request)))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_summary (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- A summary of the room between `since' and `until', for the
			-- member who asked and for nobody else. The engine runs on the
			-- dispatcher's processor and THIS request's processor waits for
			-- it - never the API's, which serves every request in the
			-- process; the long-poll above blocks the same way for the same
			-- reason. The answer goes back in this reply and is stored
			-- nowhere: a summary is not a room event, because events are
			-- never per-person.
		local
			l_room, l_since, l_until, l_asker: INTEGER_64
			l_body: detachable SIMPLE_JSON_OBJECT
			l_text: STRING_32
			l_json: SIMPLE_JSON_OBJECT
		do
			l_room := room_id_of (a_request)
			if not attached bearer_token (a_request) as t then
				reply (a_response, unauthorized_reply)
			elseif l_room = 0 then
				reply (a_response, bad_request_reply ("room id"))
			else
				l_asker := api_summary_gate (shared_api, t, l_room)
				if l_asker = 0 then
					reply (a_response, unauthorized_reply)
				elseif not attached api_dispatcher (shared_api) as l_dispatcher then
					reply (a_response, summary_error_reply (503, "This room has no assistant to summarise it."))
				else
					l_body := json_body (a_request)
					l_since := json_natural (l_body, "since")
					l_until := json_natural (l_body, "until")
					l_text := summary_through (l_dispatcher, l_room, l_since, l_until, l_asker, json_natural (l_body, "minutes").to_integer_32.max (0))
					if last_summary_http = 200 and then not l_text.is_empty then
						create l_json.make
						l_json.put_string (l_text, Key_summary).do_nothing
						reply (a_response, create {CHAT_REPLY}.make_json (200, l_json, 0))
					elseif last_summary_http = 204 then
						reply (a_response, summary_error_reply (404, "There is nothing new to summarise."))
					elseif last_summary_http = 429 then
						reply (a_response, summary_error_reply (429, "You have reached your summary limit for now - please try again later."))
					elseif last_summary_http = 503 then
						reply (a_response, summary_error_reply (503, "This room has no assistant to summarise it."))
					else
						reply (a_response, summary_error_reply (502, "The assistant could not summarise just now."))
					end
				end
			end
		end

	handle_edit_message (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- Only the author may change the words; the original is never
			-- rewritten, an edit is appended naming it.
		do
			if attached bearer_token (a_request) as t then
				reply (a_response, api_edit_message (shared_api, t, room_id_of (a_request), event_id_of (a_request),
					json_string (json_body (a_request), "body")))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_delete_message (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- The author, or an administrator. A tombstone, never a removal.
		do
			if attached bearer_token (a_request) as t then
				reply (a_response, api_delete_message (shared_api, t, room_id_of (a_request), event_id_of (a_request)))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_react (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- One person's emoji, on or off. `on' absent means ON: a client
			-- that posts a bare emoji is adding it, which is the common case.
		local
			l_body: detachable SIMPLE_JSON_OBJECT
		do
			if attached bearer_token (a_request) as t then
				l_body := json_body (a_request)
				reply (a_response, api_react (shared_api, t, room_id_of (a_request), event_id_of (a_request),
					json_string (l_body, "emoji"), json_flag (l_body, "on", True)))
			else
				reply (a_response, unauthorized_reply)
			end
		end

	handle_reply (a_request: SIMPLE_WEB_SERVER_REQUEST; a_response: SIMPLE_WEB_SERVER_RESPONSE)
			-- A reply is an ordinary message naming its parent.
		do
			if attached bearer_token (a_request) as t then
				reply (a_response, api_post_reply (shared_api, t, room_id_of (a_request), event_id_of (a_request),
					json_string (json_body (a_request), "body")))
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
			-- The raw body is the image; X-File-Name and X-Caption carry the rest,
			-- percent-encoded UTF-8 as CHAT_HEADER_TEXT writes them (Phase 4 Task 9b;
			-- a later phase may add multipart).
		local
			l_name, l_caption: STRING_32
		do
			if attached bearer_token (a_request) as t then
				if a_request.body.count > Max_image_body_bytes then
						-- Refused before any parsing or copying; the API still enforces the
						-- configuration's exact `upload_bytes' behind this coarse gate.
					reply (a_response, too_large_reply)
				else
					l_name := header_32 (a_request, Meta_file_name)
					l_caption := header_32 (a_request, Meta_caption)
					reply (a_response, api_post_image (shared_api, t, room_id_of (a_request), a_request.body, l_name, l_caption))
				end
			else
				reply (a_response, unauthorized_reply)
			end
		end

	Meta_file_name: STRING_8 = "X_File_Name"
	Meta_caption: STRING_8 = "X_Caption"
			-- The CGI meta spelling of the wire headers "X-File-Name" and "X-Caption"
			-- (RFC 3875 4.1.18: HTTP_ followed by the field name upper-cased, hyphens
			-- turned into underscores). simple_web's `header' builds the meta name by
			-- upper-casing and prefixing what it is handed and does NOT convert hyphens,
			-- so a hyphenated header is reachable only when it is asked for this way -
			-- "Authorization" has no hyphen, which is why nothing here needed it before.
			-- What CHAT_CLIENT puts on the wire is X-File-Name and X-Caption.

	Max_image_body_bytes: INTEGER = 16777216
			-- 16 MiB: above any lawful configuration (default upload_bytes is 8 MiB), so the
			-- gate never refuses what the service would accept; it only stops a flood early.

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

	api_is_public (a_api: separate CHAT_API): BOOLEAN
			-- Is the service configured public (the Caddy door path, DR-010)?
		do
			Result := a_api.config.is_public
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

	api_summary_gate (a_api: separate CHAT_API; a_token: READABLE_STRING_8; a_room_id: INTEGER_64): INTEGER_64
			-- The asker's id when this token may summarise this room; 0 otherwise.
		do
			Result := a_api.summary_gate (a_token, a_room_id)
		ensure
			non_negative: Result >= 0
		end

	api_dispatcher (a_api: separate CHAT_API): detachable separate PARTICIPANT_DISPATCHER
			-- The dispatcher the host registered, or Void in a server with no
			-- participants. A reference only - it is never called from the
			-- API's processor.
		do
			Result := a_api.participant_dispatcher
		end

	summary_through (a_dispatcher: separate PARTICIPANT_DISPATCHER; a_room_id, a_since_id, a_until_id, a_asker_id: INTEGER_64; a_minutes: INTEGER): STRING_32
			-- The summary, copied here, with `last_summary_http' left holding
			-- the status THAT call produced. Both are read inside this one
			-- routine, which reserves the dispatcher's processor for its whole
			-- body: another request's summary therefore cannot land between a
			-- text and its status.
		require
			positive_room: a_room_id > 0
			since_non_negative: a_since_id >= 0
			until_non_negative: a_until_id >= 0
			positive_asker: a_asker_id > 0
			minutes_non_negative: a_minutes >= 0
		do
			create Result.make_from_separate (a_dispatcher.summary_of (a_room_id, a_since_id, a_until_id, a_asker_id, a_minutes))
			last_summary_http := a_dispatcher.last_summary_status
		ensure
			status_read: last_summary_http > 0
			text_only_when_ok: (not Result.is_empty) implies last_summary_http = 200
		end

	last_summary_http: INTEGER
			-- The status the latest `summary_through' brought back.

	json_natural (a_object: detachable SIMPLE_JSON_OBJECT; a_key: STRING_32): INTEGER_64
			-- The non-negative integer under `a_key', or 0 - for anything
			-- missing, of the wrong type, or negative (D6: a hostile body
			-- yields the default, never a refusal and never an exception).
		do
			if attached a_object as o and then attached o.integer_item (a_key) as n and then n.item > 0 then
				Result := n.item
			end
		ensure
			non_negative: Result >= 0
		end

	Key_summary: STRING_32 = "summary"
			-- The one field of a summary reply.

	api_edit_message (a_api: separate CHAT_API; a_token: STRING_8; a_room_id, a_event_id: INTEGER_64; a_body: STRING_32): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.edit_message (a_token, a_room_id, a_event_id, a_body))
		end

	api_delete_message (a_api: separate CHAT_API; a_token: STRING_8; a_room_id, a_event_id: INTEGER_64): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.delete_message (a_token, a_room_id, a_event_id))
		end

	api_react (a_api: separate CHAT_API; a_token: STRING_8; a_room_id, a_event_id: INTEGER_64; a_emoji: STRING_32; a_on: BOOLEAN): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.react_to_message (a_token, a_room_id, a_event_id, a_emoji, a_on))
		end

	api_post_reply (a_api: separate CHAT_API; a_token: STRING_8; a_room_id, a_parent_id: INTEGER_64; a_body: STRING_32): CHAT_REPLY
		do
			create Result.make_from_separate (a_api.post_reply (a_token, a_room_id, a_parent_id, a_body))
		end

	event_id_of (a_request: SIMPLE_WEB_SERVER_REQUEST): INTEGER_64
			-- The {eid} of the path; 0 when it is missing or not a positive
			-- number, which every caller turns into a 404 rather than a raise.
		do
			if attached a_request.path_parameter ("eid") as p and then p.is_integer_64 and then p.to_integer_64 > 0 then
				Result := p.to_integer_64
			end
		ensure
			non_negative: Result >= 0
		end

	json_flag (a_object: detachable SIMPLE_JSON_OBJECT; a_key: STRING_32; a_default: BOOLEAN): BOOLEAN
			-- The boolean under `a_key', or `a_default' when it is missing or
			-- of the wrong type (D6: a hostile body takes the default).
		do
			if attached a_object as o and then attached o.boolean_item (a_key) as b then
				Result := b.item
			else
				Result := a_default
			end
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

	summary_error_reply (a_status: INTEGER; a_message: READABLE_STRING_8): CHAT_REPLY
			-- A refusal the asker reads in their OWN reply. Nothing is stored
			-- and nothing reaches the room: a summary, refused or given, is
			-- never a room event.
		require
			http_status: a_status >= 200 and a_status <= 599
			said: not a_message.is_empty
		do
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, a_message, a_status))
		ensure
			same_status: Result.status = a_status
		end

	failed_reply: CHAT_REPLY
			-- 500: the wait could not be completed; the subscription is already released.
		do
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, "the wait failed; ask again", 500))
		ensure
			server_error: Result.status = 500
		end

	too_large_reply: CHAT_REPLY
		do
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_too_large, "the upload is larger than any allowed image", 413))
		ensure
			too_large: Result.status = 413
		end

	not_yet_reply: CHAT_REPLY
		do
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501))
		end

	header_32 (a_request: SIMPLE_WEB_SERVER_REQUEST; a_name: READABLE_STRING_8): STRING_32
			-- A header read the one way CHAT_CLIENT writes one (CHAT_HEADER_TEXT):
			-- percent-decoded, then UTF-8. A value carrying no percent sign is
			-- plain UTF-8 and comes back unchanged, so a hand-made request with an
			-- ASCII name still works; a header that is not there is empty.
		do
			if attached a_request.header (a_name) as h then
				Result := header_text.decoded (h)
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

	header_text: CHAT_HEADER_TEXT
			-- The one rule for a file name or a caption on a header line; CHAT_CLIENT
			-- writes them with the same class. Stateless, so a fresh one costs nothing
			-- and no `once' is smuggled onto a request processor.
		do
			create Result
		end

end
