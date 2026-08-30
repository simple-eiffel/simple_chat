note
	description: "[
		The JSON API on the service's processor (D1): every feature takes
		copyable data (integers, separate strings) and answers a
		CHAT_REPLY - status, content type, bytes - so request handlers on
		other processors never touch a domain object. One request executes
		here at a time; the store, bus, limiter and log are ordinary
		attributes of the service this API owns, which is why the exact
		postconditions below (`= old + 1') hold.

		Every answer maps a CHAT_RESULT or a rule onto a status: 401 no or
		expired token, 403 not a member, 4xx the service's refusal, 501
		until Phase 4 implements the service. Never raises for a caller's
		mistake: bad input becomes a reply.
	]"
	author: "Larry Rix"

class
	CHAT_API

inherit
	SIMPLE_WEB_SHARED

create
	make,
	make_from_shared

feature {NONE} -- Initialization

	make (a_service: CHAT_SERVICE; a_config: SERVER_CONFIG)
			-- An API over `a_service' (same processor: tests, and the thread build).
		require
			valid_config: a_config.is_valid
			open: a_service.store.is_open
		do
			service := a_service
			config := a_config
			create codec.make
		ensure
			set: service = a_service and config = a_config
			nothing_yet: request_count = 0
		end

	make_from_shared
			-- Build the service and everything under it on this processor,
			-- from the shared settings. Phase 4 reads `Config_path_key' and
			-- opens the SQLite store; until then defaults and a memory store.
		local
			l_config: SERVER_CONFIG
			l_store: MEMORY_CHAT_STORE
			l_bus: EVENT_BUS
			l_limits: RATE_LIMITER
			l_log: CHAT_LOG
			l_logger: SIMPLE_LOGGER
		do
			create l_config.make_defaults
			create l_store.make
			l_store.open
			create l_bus.make
			create l_limits.make (3600)
			create l_logger
			create l_log.make (l_logger)
			create service.make (l_store, l_bus, l_limits, l_config, l_log)
			config := l_config
			create codec.make
		ensure
			open: service.store.is_open
			nothing_yet: request_count = 0
		end

feature -- Access

	service: CHAT_SERVICE

	config: SERVER_CONFIG

	request_count: INTEGER
			-- Answers given so far.

	last_subscription: INTEGER
			-- The ticket the latest `subscribe' issued; 0 when it was refused.

feature -- Answers: liveness and session

	health: CHAT_REPLY
		local
			l_json: SIMPLE_JSON_OBJECT
		do
			create l_json.make
			l_json.put_boolean (service.store.is_open, "store").do_nothing
			l_json.put_integer (service.store.last_event_id, "last_event_id").do_nothing
			Result := answered (create {CHAT_REPLY}.make_json (200, l_json, 0))
		ensure
			ok: Result.status = 200
			counted: request_count = old request_count + 1
		end

	login (a_username, a_password: separate READABLE_STRING_32; a_client_ip: separate READABLE_STRING_8): CHAT_REPLY
			-- 200 {"token", "member"} for a person who proves the password.
		local
			l_name, l_password: STRING_32
			l_ip: STRING_8
			l_result: CHAT_RESULT [CHAT_SESSION]
		do
			l_name := local_32 (a_username)
			l_password := local_32 (a_password)
			l_ip := local_8 (a_client_ip)
			if l_name.is_empty or l_password.is_empty or l_ip.is_empty then
				Result := answered (bad_request ("username, password and client address are required"))
			else
				l_result := service.authenticate (l_name, l_password, l_ip)
				if l_result.is_success then
					Result := answered (not_yet)   -- Phase 4: the token travels only here, once
				else
					Result := answered (error_reply (l_result.error))
				end
			end
		ensure
			counted: request_count = old request_count + 1
			answered: Result.status = 200 or Result.status = 400 or Result.status = 401 or Result.status = 429 or Result.status = 501
			token_only_on_success: Result.status /= 200 implies not Result.body.has_substring ("%"token%"")
		end

	logout (a_token: separate READABLE_STRING_8): CHAT_REPLY
		local
			l_token: STRING_8
		do
			l_token := local_8 (a_token)
			if attached session_for (l_token) as l_session then
				service.revoke (l_session)
				Result := answered (create {CHAT_REPLY}.make_json (200, create {SIMPLE_JSON_OBJECT}.make, 0))
			else
				Result := answered (unauthorized)
			end
		ensure
			counted: request_count = old request_count + 1
			revoked: session_for (local_8 (a_token)) = Void
		end

	me (a_token: separate READABLE_STRING_8): CHAT_REPLY
		do
			if attached user_for (local_8 (a_token)) as l_user then
				Result := answered (create {CHAT_REPLY}.make_json (200, codec.member_to_json (codec.member_of (l_user)), 0))
			else
				Result := answered (unauthorized)
			end
		ensure
			counted: request_count = old request_count + 1
			needs_session: user_for (local_8 (a_token)) = Void implies Result.status = 401
		end

feature -- Answers: reading

	events (a_token: separate READABLE_STRING_8; a_room_id, a_since_id: INTEGER_64; a_limit: INTEGER; a_statuses_json: separate READABLE_STRING_8): CHAT_REPLY
			-- The page after `a_since_id' (ascending, gap-free, at most `a_limit') plus
			-- the statuses a long-poll's waiter kept (a JSON array, "[]" when none).
		require
			since_non_negative: a_since_id >= 0
			limit_in_range: a_limit > 0 and a_limit <= {CHAT_SERVICE}.Page_maximum
		local
			l_events: ARRAYED_LIST [CHAT_EVENT]
			l_statuses: SIMPLE_JSON_ARRAY
		do
			if attached user_for (local_8 (a_token)) as l_user then
				if attached member_room (l_user, a_room_id) as l_room then
					l_events := service.events_since (l_room, a_since_id, a_limit)
					if attached codec.array_from_bytes (local_8 (a_statuses_json)) as arr then
						l_statuses := arr
					else
						create l_statuses.make
					end
					Result := answered (create {CHAT_REPLY}.make_json (200, codec.page_to_json_merged (l_events, l_statuses), l_events.count))
				else
					Result := answered (forbidden)
				end
			else
				Result := answered (unauthorized)
			end
		ensure
			counted: request_count = old request_count + 1
			bounded: Result.item_count <= a_limit
			page_on_success: Result.status = 200 implies Result.is_json
			needs_session: user_for (local_8 (a_token)) = Void implies Result.status = 401
		end

	events_before (a_token: separate READABLE_STRING_8; a_room_id, a_before_id: INTEGER_64; a_limit: INTEGER): CHAT_REPLY
			-- History paging: the `a_limit' events before `a_before_id', ascending.
		require
			before_positive: a_before_id > 0
			limit_in_range: a_limit > 0 and a_limit <= {CHAT_SERVICE}.Page_maximum
		local
			l_events: ARRAYED_LIST [CHAT_EVENT]
		do
			if attached user_for (local_8 (a_token)) as l_user then
				if attached member_room (l_user, a_room_id) as l_room then
					l_events := service.events_before (l_room, a_before_id, a_limit)
					Result := answered (create {CHAT_REPLY}.make_json (200, codec.page_to_json (l_events, create {ARRAYED_LIST [CHAT_STATUS]}.make (0)), l_events.count))
				else
					Result := answered (forbidden)
				end
			else
				Result := answered (unauthorized)
			end
		ensure
			counted: request_count = old request_count + 1
			bounded: Result.item_count <= a_limit
		end

	subscribe (a_token: separate READABLE_STRING_8; a_room_id: INTEGER_64; a_subscriber: separate EVENT_SUBSCRIBER)
			-- Ring `a_subscriber' for `a_room_id' from now: the ticket is `last_subscription', 0 when refused.
		do
			if attached user_for (local_8 (a_token)) as l_user and then attached member_room (l_user, a_room_id) then
				service.bus.subscribe (a_subscriber)
				last_subscription := service.bus.last_ticket
			else
				last_subscription := 0
			end
		ensure
			ticket_when_allowed: (attached user_for (local_8 (a_token)) as u and then attached member_room (u, a_room_id)) = (last_subscription > 0)
			live: last_subscription > 0 implies service.bus.is_subscribed (last_subscription)
		end

	unsubscribe (a_ticket: INTEGER)
		do
			service.bus.unsubscribe (a_ticket)
		ensure
			gone: not service.bus.is_subscribed (a_ticket)
		end

	members (a_token: separate READABLE_STRING_8; a_room_id: INTEGER_64): CHAT_REPLY
			-- {"members": [...]} - the roster, never a hash.
		do
			if attached user_for (local_8 (a_token)) as l_user then
				if attached member_room (l_user, a_room_id) then
					Result := answered (not_yet)   -- Phase 4: CHAT_STORE.members_of
				else
					Result := answered (forbidden)
				end
			else
				Result := answered (unauthorized)
			end
		ensure
			counted: request_count = old request_count + 1
			no_hashes: not Result.body.has_substring ("password_hash")
		end

	rooms (a_token: separate READABLE_STRING_8): CHAT_REPLY
			-- [{id, name}] for the caller's rooms.
		do
			if attached user_for (local_8 (a_token)) then
				Result := answered (not_yet)   -- Phase 4: service.rooms_of
			else
				Result := answered (unauthorized)
			end
		ensure
			counted: request_count = old request_count + 1
		end

	participants (a_token: separate READABLE_STRING_8): CHAT_REPLY
		do
			if attached user_for (local_8 (a_token)) then
				Result := answered (not_yet)
			else
				Result := answered (unauthorized)
			end
		ensure
			counted: request_count = old request_count + 1
		end

	attachment (a_token: separate READABLE_STRING_8; a_attachment_id: INTEGER_64): CHAT_REPLY
			-- The file's bytes with its validated type; nosniff is the handler's job.
		do
			if attached user_for (local_8 (a_token)) then
				Result := answered (not_yet)   -- Phase 4: read data/uploads/<sha>.<ext>
			else
				Result := answered (unauthorized)
			end
		ensure
			counted: request_count = old request_count + 1
		end

feature -- Answers: posting

	post_message (a_token: separate READABLE_STRING_8; a_room_id: INTEGER_64; a_body: separate READABLE_STRING_32): CHAT_REPLY
			-- 201 with the stored event.
		local
			l_body: STRING_32
			l_result: CHAT_RESULT [CHAT_EVENT]
		do
			l_body := local_32 (a_body)
			if attached user_for (local_8 (a_token)) as l_user then
				if attached member_room (l_user, a_room_id) as l_room then
					if l_body.is_empty then
						Result := answered (bad_request ("body is required"))
					elseif l_body.count > config.message_characters then
						Result := answered (error_reply (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_too_long, "message too long", 400)))
					else
						l_result := service.post_message (l_user, l_room, l_body)
						if l_result.is_success and then attached l_result.value as e then
							Result := answered (create {CHAT_REPLY}.make_json (201, e.to_json, 1))
						else
							Result := answered (error_reply (l_result.error))
						end
					end
				else
					Result := answered (forbidden)
				end
			else
				Result := answered (unauthorized)
			end
		ensure
			counted: request_count = old request_count + 1
			appended_on_success: Result.status = 201 implies service.store.last_event_id = old service.store.last_event_id + 1
			nothing_on_failure: Result.status /= 201 implies service.store.last_event_id = old service.store.last_event_id
			needs_session: user_for (local_8 (a_token)) = Void implies Result.status = 401
		end

	post_image (a_token: separate READABLE_STRING_8; a_room_id: INTEGER_64; a_bytes: separate READABLE_STRING_8; a_file_name, a_caption: separate READABLE_STRING_32): CHAT_REPLY
			-- 201 with the stored image event; 413 too large; 415 not a PNG/JPEG by signature.
		do
			if attached user_for (local_8 (a_token)) as l_user then
				if attached member_room (l_user, a_room_id) then
					Result := answered (not_yet)   -- Phase 4: service.store_upload then post_image
				else
					Result := answered (forbidden)
				end
			else
				Result := answered (unauthorized)
			end
		ensure
			counted: request_count = old request_count + 1
			nothing_on_failure: Result.status /= 201 implies service.store.last_event_id = old service.store.last_event_id
		end

feature -- Answers: account and administration

	change_password (a_token: separate READABLE_STRING_8; a_old, a_new: separate READABLE_STRING_32): CHAT_REPLY
		do
			if attached user_for (local_8 (a_token)) then
				Result := answered (not_yet)
			else
				Result := answered (unauthorized)
			end
		ensure
			counted: request_count = old request_count + 1
		end

	admin_users (a_token: separate READABLE_STRING_8): CHAT_REPLY
		do
			Result := answered (admin_only (a_token))
		ensure
			counted: request_count = old request_count + 1
		end

	admin_create_user (a_token: separate READABLE_STRING_8; a_username: separate READABLE_STRING_8; a_display_name, a_password: separate READABLE_STRING_32; a_is_admin: BOOLEAN): CHAT_REPLY
		do
			Result := answered (admin_only (a_token))
		ensure
			counted: request_count = old request_count + 1
		end

	admin_reset_password (a_token: separate READABLE_STRING_8; a_user_id: INTEGER_64; a_password: separate READABLE_STRING_32): CHAT_REPLY
		do
			Result := answered (admin_only (a_token))
		ensure
			counted: request_count = old request_count + 1
		end

	admin_create_bot (a_token: separate READABLE_STRING_8; a_username: separate READABLE_STRING_8; a_display_name: separate READABLE_STRING_32): CHAT_REPLY
			-- The bot's token is shown once, in this reply, and never stored in clear.
		do
			Result := answered (admin_only (a_token))
		ensure
			counted: request_count = old request_count + 1
		end

	admin_revoke_bot (a_token: separate READABLE_STRING_8; a_bot_id: INTEGER_64): CHAT_REPLY
		do
			Result := answered (admin_only (a_token))
		ensure
			counted: request_count = old request_count + 1
		end

	admin_backup (a_token: separate READABLE_STRING_8): CHAT_REPLY
		do
			Result := answered (admin_only (a_token))
		ensure
			counted: request_count = old request_count + 1
		end

feature {PARTICIPANT_DISPATCHER} -- The dispatcher's processor

	dispatcher_start_after: INTEGER_64
			-- Where a new dispatcher begins: the store's last event id, so a
			-- restart never re-answers history (Issue 16).
		do
			Result := service.store.last_event_id
		ensure
			definition: Result = service.store.last_event_id
		end

	dispatcher_page (a_room_id, a_since_id: INTEGER_64; a_limit: INTEGER): STRING_8
			-- The page of `a_room_id' after `a_since_id' as bytes - what `events'
			-- answers, without a token: the dispatcher is this process. An
			-- unknown room gives an empty page.
		require
			since_non_negative: a_since_id >= 0
			limit_in_range: a_limit > 0 and a_limit <= {CHAT_SERVICE}.Page_maximum
		local
			l_events: ARRAYED_LIST [CHAT_EVENT]
		do
			if a_room_id > 0 and then attached service.store.room (a_room_id) as l_room and then l_room.is_stored then
				l_events := service.events_since (l_room, a_since_id, a_limit)
			else
				create l_events.make (0)
			end
			Result := codec.bytes_of (codec.page_to_json (l_events, create {ARRAYED_LIST [CHAT_STATUS]}.make (0)))
			request_count := request_count + 1
		ensure
			counted: request_count = old request_count + 1
			decodable: codec.page_from_bytes (Result) /= Void
			bounded: attached codec.page_from_bytes (Result) as p implies p.events.count <= a_limit
			all_after: attached codec.page_from_bytes (Result) as p implies across p.events as e all e.id > a_since_id and e.room_id = a_room_id end
			empty_when_unknown: service.store.room (a_room_id) = Void implies (attached codec.page_from_bytes (Result) as p and then p.events.is_empty)
		end

	dispatcher_can_post (a_bot_user_id, a_room_id: INTEGER_64): BOOLEAN
			-- May bot `a_bot_user_id' post in `a_room_id': stored, active, a bot, and a member?
		do
			Result := attached service.store.user (a_bot_user_id) as u and then u.is_stored and then u.is_bot and then u.is_active
				and then attached service.store.room (a_room_id) as r and then r.is_stored and then service.store.is_member (u.id, r.id)
		ensure
			definition: Result = (attached service.store.user (a_bot_user_id) as u and then u.is_stored and then u.is_bot and then u.is_active
				and then attached service.store.room (a_room_id) as r and then r.is_stored and then service.store.is_member (u.id, r.id))
		end

	dispatcher_try_ask (a_key: separate READABLE_STRING_8): BOOLEAN
			-- One more ask under `a_key' if its limit allows - decided and
			-- counted here, in one step, on the processor that owns the limiter.
		require
			key_given: not a_key.is_empty
		local
			l_key: STRING_8
		do
			l_key := local_8 (a_key)
			Result := service.limits.is_allowed (l_key)
			if Result then
				service.limits.record (l_key)
			end
		ensure
			granted_when_allowed: Result = old service.limits.is_allowed (local_8 (a_key))
			recorded: Result implies service.limits.count (local_8 (a_key)) = old service.limits.count (local_8 (a_key)) + 1
			nothing_when_refused: not Result implies service.limits.counts_model |=| old service.limits.counts_model
		end

	dispatcher_post (a_bot_user_id, a_room_id: INTEGER_64; a_text: separate READABLE_STRING_32): INTEGER
			-- Post `a_text' as bot `a_bot_user_id' in `a_room_id': 201, else the
			-- service's error status - 403 when the bot cannot post there, 400
			-- for an empty or over-long text.
		local
			l_text: STRING_32
			l_result: CHAT_RESULT [CHAT_EVENT]
		do
			l_text := local_32 (a_text)
			if attached service.store.user (a_bot_user_id) as u and then u.is_stored and then u.is_bot and then u.is_active
				and then attached service.store.room (a_room_id) as r and then r.is_stored and then service.store.is_member (u.id, r.id)
			then
				if l_text.is_empty or l_text.count > config.message_characters then
					Result := 400
				else
					l_result := service.post_message (u, r, l_text)
					if l_result.is_success then
						Result := 201
					elseif attached l_result.error as e then
						Result := e.http_status
					else
						Result := 500
					end
				end
			else
				Result := 403
			end
			request_count := request_count + 1
		ensure
			counted: request_count = old request_count + 1
			http_status: Result >= 200 and Result <= 599
			appended_on_success: Result = 201 implies service.store.last_event_id = old service.store.last_event_id + 1
			nothing_on_failure: Result /= 201 implies service.store.last_event_id = old service.store.last_event_id
			only_member_rooms: not dispatcher_can_post (a_bot_user_id, a_room_id) implies Result = 403
			text_required: local_32 (a_text).is_empty implies Result /= 201
			within_limit: local_32 (a_text).count > config.message_characters implies Result /= 201
		end

	dispatcher_display_name (a_user_id: INTEGER_64): STRING_32
			-- The member's display name, or "#<id>" for one the store does not know.
		do
			if attached service.store.user (a_user_id) as u then
				Result := u.display_name.twin
			else
				create Result.make_from_string_general ("#")
				Result.append_string_general (a_user_id.out)
			end
		ensure
			given: not Result.is_empty
			from_store: attached service.store.user (a_user_id) as u implies Result.same_string (u.display_name)
		end

	dispatcher_room_name (a_room_id: INTEGER_64): STRING_32
			-- The room's name, or "room <id>" for one the store does not know.
		do
			if attached service.store.room (a_room_id) as r then
				Result := r.name.twin
			else
				create Result.make_from_string_general ("room ")
				Result.append_string_general (a_room_id.out)
			end
		ensure
			given: not Result.is_empty
			from_store: attached service.store.room (a_room_id) as r implies Result.same_string (r.name)
		end

feature -- Sessions (contract support)

	session_for (a_token: READABLE_STRING_8): detachable CHAT_SESSION
			-- The live session behind `a_token', or Void (also for a malformed token).
		do
			if a_token.count = {CHAT_CLIENT}.Token_length then
				Result := service.session_for_token (a_token)
			end
		ensure
			shape_first: a_token.count /= {CHAT_CLIENT}.Token_length implies Result = Void
		end

	user_for (a_token: READABLE_STRING_8): detachable CHAT_USER
			-- The active user behind `a_token', or Void.
		do
			if attached session_for (a_token) as l_session and then attached service.store.user (l_session.user_id) as l_user and then l_user.is_active then
				Result := l_user
			end
		ensure
			active: attached Result as u implies u.is_active
			needs_session: session_for (a_token) = Void implies Result = Void
		end

	member_room (a_user: CHAT_USER; a_room_id: INTEGER_64): detachable CHAT_ROOM
			-- The room, when `a_user' is a member of it.
		require
			stored: a_user.is_stored
		do
			if a_room_id > 0 and then attached service.store.room (a_room_id) as l_room and then service.is_member (a_user, l_room) then
				Result := l_room
			end
		ensure
			member: attached Result as r implies service.store.is_member (a_user.id, r.id)
		end

feature {NONE} -- Replies

	answered (a_reply: CHAT_REPLY): CHAT_REPLY
			-- Count and pass through.
		do
			request_count := request_count + 1
			Result := a_reply
		ensure
			counted: request_count = old request_count + 1
			same: Result = a_reply
		end

	not_yet: CHAT_REPLY
		do
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501))
		end

	unauthorized: CHAT_REPLY
		do
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_bad_credentials, "a valid Bearer token is required", 401))
		ensure
			status: Result.status = 401
		end

	forbidden: CHAT_REPLY
		do
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_not_member, "not a member of this room", 403))
		ensure
			status: Result.status = 403
		end

	bad_request (a_message: READABLE_STRING_GENERAL): CHAT_REPLY
		require
			explained: not a_message.is_empty
		do
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_refused, a_message, 400))
		ensure
			status: Result.status = 400
		end

	error_reply (a_error: detachable CHAT_ERROR): CHAT_REPLY
			-- The error as a reply; a missing error is an internal failure.
		do
			if attached a_error as e then
				create Result.make_error (e)
			else
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, "no result", 500))
			end
		ensure
			failed: not Result.is_success
		end

	admin_only (a_token: separate READABLE_STRING_8): CHAT_REPLY
			-- 401 without a session, 403 for a person who is not an admin, else the Phase 4 gap.
		do
			if attached user_for (local_8 (a_token)) as l_user then
				if l_user.is_admin then
					Result := not_yet
				else
					create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_refused, "admin only", 403))
				end
			else
				Result := unauthorized
			end
		ensure
			needs_session: user_for (local_8 (a_token)) = Void implies Result.status = 401
		end

feature {NONE} -- Copies across processors

	local_8 (a_text: separate READABLE_STRING_8): STRING_8
		do
			create Result.make_from_separate (a_text)
		ensure
			same_length: Result.count = a_text.count
		end

	local_32 (a_text: separate READABLE_STRING_32): STRING_32
		do
			create Result.make_from_separate (a_text)
		ensure
			same_length: Result.count = a_text.count
		end

feature {NONE} -- Implementation

	codec: CHAT_JSON

invariant
	counts_non_negative: request_count >= 0 and last_subscription >= 0
	store_open: service.store.is_open

end
