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
			create last_summary_key.make_empty
		ensure
			set: service = a_service and config = a_config
			nothing_yet: request_count = 0
		end

	make_from_shared
			-- Build the service and everything under it on this processor,
			-- from the shared settings: the configuration is loaded from the
			-- path under `Config_path_key' (defaults when the key is absent
			-- or the file is refused - D6, logged, never raised), and the
			-- store is the SQLite file at `database_path' when that
			-- configuration came from a file, with the memory store as the
			-- fallback that keeps this API constructible when the file
			-- store cannot open (the error is logged).
		local
			l_config: detachable SERVER_CONFIG
			l_file_config: SERVER_CONFIG
			l_store: detachable CHAT_STORE
			l_memory: MEMORY_CHAT_STORE
			l_sqlite: SQLITE_CHAT_STORE
			l_bus: EVENT_BUS
			l_limits: RATE_LIMITER
			l_log: CHAT_LOG
			l_logger: SIMPLE_LOGGER
			l_directory: DIRECTORY
		do
			create l_logger
			create l_log.make (l_logger)
			if attached shared_item ({CHAT_SHARED}.Config_path_key) as l_path and then not l_path.is_empty then
				create l_file_config.make_from_file (l_path)
				if l_file_config.is_valid then
					l_config := l_file_config
				else
					l_log.error ("the configuration at " + l_path + " is refused; the API runs on defaults with a memory store")
				end
			end
			if l_config = Void then
				create l_config.make_defaults
			end
			if l_config.is_loaded and then not l_config.data_dir.is_empty then
				create l_directory.make (l_config.data_dir)
				if not l_directory.exists then
					l_directory.recursive_create_dir
				end
				create l_sqlite.make (l_config.database_path)
				l_sqlite.open
				if l_sqlite.is_open then
					l_store := l_sqlite
				else
					l_log.error ("the SQLite store under " + {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (l_config.data_dir) + " cannot open; falling back to a memory store")
				end
			end
			if l_store = Void then
				create l_memory.make
				l_memory.open
				l_store := l_memory
			end
			create l_bus.make
			create l_limits.make (3600)
			create service.make (l_store, l_bus, l_limits, l_config, l_log)
			config := l_config
			create codec.make
			create last_summary_key.make_empty
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

	participant_dispatcher: detachable separate PARTICIPANT_DISPATCHER
			-- The dispatcher DISPATCHER_HOST launched, for a request handler
			-- that needs an ENGINE rather than an answer (a summary). The
			-- handler asks it from the REQUEST's own processor, never from
			-- this one: an engine call takes seconds, and every request in
			-- the process comes through here. Void until it is registered,
			-- and Void for ever in a server configured without participants.

	last_summary_key: STRING_8
			-- The limiter key the latest `dispatcher_summary_allowed' was
			-- charged to, copied onto THIS processor; empty before any. The
			-- copy is what the postcondition speaks of - a lock-passed call's
			-- postcondition is evaluated after the caller's locks are
			-- returned, so reaching back into the caller's own string there
			-- is a phantom raise waiting to happen (see `dispatcher_post').

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
						-- The clear token travels in this one reply and nowhere else (DR-006):
						-- read from the service's seam right after the authenticate, never kept, never logged.
					check has_session: attached l_result.value as l_session then
						check known_user: attached service.store.user (l_session.user_id) as l_account then
							Result := answered (create {CHAT_REPLY}.make_json (200,
								codec.login_to_json (service.last_issued_token, codec.member_of (l_account)), 0))
						end
					end
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
			needs_session: old (user_for (local_8 (a_token)) = Void) implies Result.status = 401
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
			needs_session: old (user_for (local_8 (a_token)) = Void) implies Result.status = 401
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
			ticket_when_allowed: old (not (attached user_for (local_8 (a_token)) as u and then attached member_room (u, a_room_id))) implies last_subscription = 0
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
				if attached member_room (l_user, a_room_id) as l_room then
					Result := answered (create {CHAT_REPLY}.make_json (200, members_json (l_room), 0))
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
			if attached user_for (local_8 (a_token)) as l_user then
				Result := answered (create {CHAT_REPLY}.make (200, {CHAT_REPLY}.Json_content_type, codec.bytes_of_array (rooms_json (l_user))))
			else
				Result := answered (unauthorized)
			end
		ensure
			counted: request_count = old request_count + 1
		end

	participants (a_token: separate READABLE_STRING_8): CHAT_REPLY
			-- {"participants": [{handle, username, display_name}]} - the configured AI participants.
		do
			if attached user_for (local_8 (a_token)) then
				Result := answered (create {CHAT_REPLY}.make_json (200, participants_json, 0))
			else
				Result := answered (unauthorized)
			end
		ensure
			counted: request_count = old request_count + 1
		end

	attachment (a_token: separate READABLE_STRING_8; a_attachment_id: INTEGER_64): CHAT_REPLY
			-- The file's bytes with its validated type; nosniff is the handler's job.
		local
			l_body: STRING_8
			i: INTEGER
		do
			if attached user_for (local_8 (a_token)) then
				if a_attachment_id > 0 and then service.store.has_attachment (a_attachment_id) then
					if attached service.store.attachment (a_attachment_id) as l_attachment and then
						attached service.store.attachment_bytes (a_attachment_id) as l_bytes
					then
						create l_body.make (l_bytes.count)
						from
							i := 0
						until
							i >= l_bytes.count
						loop
							l_body.append_code (l_bytes [i])
							i := i + 1
						variant
							l_bytes.count - i
						end
						Result := answered (create {CHAT_REPLY}.make (200, l_attachment.mime, l_body))
					else
							-- A row stored before Phase 4 Task 4 kept no bytes; still honest.
						Result := answered (create {CHAT_REPLY}.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_not_implemented, "Attachment bytes are not stored yet.", 501)))
					end
				else
					Result := answered (create {CHAT_REPLY}.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_refused, "No such attachment.", 404)))
				end
			else
				Result := answered (unauthorized)
			end
		ensure
			counted: request_count = old request_count + 1
		end

feature -- Answers: summary

	summary_gate (a_token: separate READABLE_STRING_8; a_room_id: INTEGER_64): INTEGER_64
			-- The id of the member `a_token' signs in as WHEN they may ask for
			-- a summary of `a_room_id' - a live session, and membership of that
			-- room; 0 for everyone else. One answer for both refusals: a
			-- stranger learns nothing about which rooms exist.
		do
			if attached user_for (local_8 (a_token)) as l_user and then attached member_room (l_user, a_room_id) then
				Result := l_user.id
			end
			request_count := request_count + 1
		ensure
			counted: request_count = old request_count + 1
			non_negative: Result >= 0
			only_members: Result > 0 implies (attached service.store.user (Result) as u and then service.store.is_member (u.id, a_room_id))
			nothing_stored: service.store.last_event_id = old service.store.last_event_id
		end

feature -- Answers: acting on a message

	edit_message (a_token: separate READABLE_STRING_8; a_room_id, a_event_id: INTEGER_64; a_body: separate READABLE_STRING_32): CHAT_REPLY
			-- 201 with the edit event. The original is never rewritten - the
			-- log is the record - so this appends an edit naming it.
		local
			l_body: STRING_32
			l_result: CHAT_RESULT [CHAT_EVENT]
		do
			l_body := local_32 (a_body)
			if not attached user_for (local_8 (a_token)) as l_user then
				Result := answered (unauthorized)
			elseif not attached member_room (l_user, a_room_id) as l_room then
				Result := answered (forbidden)
			elseif not attached target_message (a_event_id, a_room_id) as l_target then
				Result := answered (create {CHAT_REPLY}.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_refused, "No such message.", 404)))
			elseif l_body.is_empty or l_body.count > config.message_characters then
				Result := answered (error_reply (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_too_long, "message too long", 400)))
			else
				l_result := service.edit_message (l_user, l_room, l_target, l_body)
				if l_result.is_success and then attached l_result.value as e then
					Result := answered (create {CHAT_REPLY}.make_json (201, e.to_json, 1))
				else
					Result := answered (error_reply (l_result.error))
				end
			end
		ensure
			counted: request_count = old request_count + 1
			needs_session: old (user_for (local_8 (a_token)) = Void) implies Result.status = 401
			appended_on_success: Result.status = 201 implies service.store.last_event_id = old service.store.last_event_id + 1
			nothing_on_failure: Result.status /= 201 implies service.store.last_event_id = old service.store.last_event_id
		end

	delete_message (a_token: separate READABLE_STRING_8; a_room_id, a_event_id: INTEGER_64): CHAT_REPLY
			-- 201 with the tombstone event. Nothing leaves the log: the
			-- bubble will read "message deleted" rather than vanish.
		local
			l_result: CHAT_RESULT [CHAT_EVENT]
		do
			if not attached user_for (local_8 (a_token)) as l_user then
				Result := answered (unauthorized)
			elseif not attached member_room (l_user, a_room_id) as l_room then
				Result := answered (forbidden)
			elseif not attached target_message (a_event_id, a_room_id) as l_target then
				Result := answered (create {CHAT_REPLY}.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_refused, "No such message.", 404)))
			else
				l_result := service.delete_message (l_user, l_room, l_target)
				if l_result.is_success and then attached l_result.value as e then
					Result := answered (create {CHAT_REPLY}.make_json (201, e.to_json, 1))
				else
					Result := answered (error_reply (l_result.error))
				end
			end
		ensure
			counted: request_count = old request_count + 1
			needs_session: old (user_for (local_8 (a_token)) = Void) implies Result.status = 401
			nothing_removed: service.store.event (a_event_id) = old service.store.event (a_event_id)
		end

	react_to_message (a_token: separate READABLE_STRING_8; a_room_id, a_event_id: INTEGER_64; a_emoji: separate READABLE_STRING_32; a_on: BOOLEAN): CHAT_REPLY
			-- 201 with the reaction event: one person's emoji, on or off.
		local
			l_emoji: STRING_32
			l_result: CHAT_RESULT [CHAT_EVENT]
		do
			l_emoji := local_32 (a_emoji)
			if not attached user_for (local_8 (a_token)) as l_user then
				Result := answered (unauthorized)
			elseif not attached member_room (l_user, a_room_id) as l_room then
				Result := answered (forbidden)
			elseif not attached target_message (a_event_id, a_room_id) as l_target then
				Result := answered (create {CHAT_REPLY}.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_refused, "No such message.", 404)))
			elseif l_emoji.is_empty or l_emoji.count > {CHAT_SERVICE}.Reaction_maximum then
				Result := answered (bad_request ("emoji"))
			else
				l_result := service.react_to_message (l_user, l_room, l_target, l_emoji, a_on)
				if l_result.is_success and then attached l_result.value as e then
					Result := answered (create {CHAT_REPLY}.make_json (201, e.to_json, 1))
				else
					Result := answered (error_reply (l_result.error))
				end
			end
		ensure
			counted: request_count = old request_count + 1
			needs_session: old (user_for (local_8 (a_token)) = Void) implies Result.status = 401
		end

	post_reply (a_token: separate READABLE_STRING_8; a_room_id, a_parent_id: INTEGER_64; a_body: separate READABLE_STRING_32): CHAT_REPLY
			-- 201 with the reply: an ordinary message that names its parent.
		local
			l_body: STRING_32
			l_result: CHAT_RESULT [CHAT_EVENT]
		do
			l_body := local_32 (a_body)
			if not attached user_for (local_8 (a_token)) as l_user then
				Result := answered (unauthorized)
			elseif not attached member_room (l_user, a_room_id) as l_room then
				Result := answered (forbidden)
			elseif not attached target_message (a_parent_id, a_room_id) as l_parent then
				Result := answered (create {CHAT_REPLY}.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_refused, "No such message.", 404)))
			elseif l_body.is_empty or l_body.count > config.message_characters then
				Result := answered (error_reply (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_too_long, "message too long", 400)))
			else
				l_result := service.post_reply (l_user, l_room, l_parent, l_body)
				if l_result.is_success and then attached l_result.value as e then
					Result := answered (create {CHAT_REPLY}.make_json (201, e.to_json, 1))
				else
					Result := answered (error_reply (l_result.error))
				end
			end
		ensure
			counted: request_count = old request_count + 1
			needs_session: old (user_for (local_8 (a_token)) = Void) implies Result.status = 401
		end

	target_message (a_event_id, a_room_id: INTEGER_64): detachable CHAT_EVENT
			-- The MESSAGE `a_event_id' in `a_room_id', or Void. A fold event
			-- is never a target: you cannot edit an edit, and a reaction on a
			-- reaction is nonsense the fold would silently drop anyway.
		do
			if attached service.store.event (a_event_id) as e and then e.room_id = a_room_id and then e.is_message then
				Result := e
			end
		ensure
			messages_only: attached Result as r implies r.is_message
			same_room: attached Result as r implies r.room_id = a_room_id
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
			needs_session: old (user_for (local_8 (a_token)) = Void) implies Result.status = 401
		end

	post_image (a_token: separate READABLE_STRING_8; a_room_id: INTEGER_64; a_bytes: separate READABLE_STRING_8; a_file_name, a_caption: separate READABLE_STRING_32): CHAT_REPLY
			-- 201 with the stored image event; 413 too large; 415 not a PNG/JPEG by signature.
		local
			l_name, l_caption: STRING_32
			l_bytes: STRING_8
			l_rules: CHAT_ATTACHMENT_RULES
			l_upload: CHAT_RESULT [CHAT_ATTACHMENT]
			l_result: CHAT_RESULT [CHAT_EVENT]
		do
			if attached user_for (local_8 (a_token)) as l_user then
				if attached member_room (l_user, a_room_id) as l_room then
					l_bytes := local_8 (a_bytes)
					l_name := local_32 (a_file_name)
					l_caption := local_32 (a_caption)
					create l_rules
					if not l_rules.is_valid_name (l_name) then
						l_name := {STRING_32} "image"
					end
					if l_bytes.is_empty then
						Result := answered (bad_request ("image bytes are required"))
					elseif l_caption.count > config.message_characters then
						Result := answered (error_reply (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_too_long, "caption too long", 400)))
					else
						l_upload := service.store_upload (l_user, l_name, special_of (l_bytes))
						if l_upload.is_success and then attached l_upload.value as l_attachment then
							l_result := service.post_image (l_user, l_room, l_attachment, l_caption)
							if l_result.is_success and then attached l_result.value as e then
								Result := answered (create {CHAT_REPLY}.make_json (201, e.to_json, 1))
							else
								Result := answered (error_reply (l_result.error))
							end
						else
							Result := answered (error_reply (l_upload.error))
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
			nothing_on_failure: Result.status /= 201 implies service.store.last_event_id = old service.store.last_event_id
		end

feature -- Answers: account and administration

	change_password (a_token: separate READABLE_STRING_8; a_old, a_new: separate READABLE_STRING_32): CHAT_REPLY
		local
			l_old, l_new: STRING_32
			l_result: CHAT_RESULT [CHAT_USER]
		do
			if attached user_for (local_8 (a_token)) as l_user then
				l_old := local_32 (a_old)
				l_new := local_32 (a_new)
				if l_user.is_bot then
					Result := answered (create {CHAT_REPLY}.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_refused, "Bots have no password.", 403)))
				elseif l_old.is_empty then
					Result := answered (bad_request ("the old password is required"))
				elseif l_new.count < config.password_minimum then
					Result := answered (bad_request ("the new password is too short"))
				else
					l_result := service.change_password (l_user, l_old, l_new)
					if l_result.is_success then
						Result := answered (create {CHAT_REPLY}.make_json (200, create {SIMPLE_JSON_OBJECT}.make, 0))
					else
						Result := answered (error_reply (l_result.error))
					end
				end
			else
				Result := answered (unauthorized)
			end
		ensure
			counted: request_count = old request_count + 1
		end

	admin_users (a_token: separate READABLE_STRING_8): CHAT_REPLY
			-- {"users": [...]} - every stored user as its public view, never a hash.
		do
			if attached admin_for (a_token) then
				Result := answered (create {CHAT_REPLY}.make_json (200, users_json, 0))
			else
				Result := answered (admin_refused (a_token))
			end
		ensure
			counted: request_count = old request_count + 1
		end

	admin_create_user (a_token: separate READABLE_STRING_8; a_username: separate READABLE_STRING_8; a_display_name, a_password: separate READABLE_STRING_32; a_is_admin: BOOLEAN): CHAT_REPLY
			-- 201 with the new member; 400 invalid input, 409 taken.
		local
			l_username: STRING_8
			l_display, l_password: STRING_32
			l_rules: CHAT_USER_RULES
			l_result: CHAT_RESULT [CHAT_USER]
		do
			if attached admin_for (a_token) then
				l_username := local_8 (a_username)
				l_display := local_32 (a_display_name)
				l_password := local_32 (a_password)
				create l_rules
				if not l_rules.is_valid_username (l_username) then
					Result := answered (bad_request ("a username is 1..32 characters of [a-z0-9_]"))
				elseif not l_rules.is_valid_human_display_name (l_display) then
					Result := answered (bad_request ("a display name is 1..40 visible characters without the bot marker"))
				elseif l_password.count < config.password_minimum then
					Result := answered (bad_request ("the password is too short"))
				else
					l_result := service.create_user (l_username, l_display, l_password, a_is_admin)
					if l_result.is_success and then attached l_result.value as l_created then
						Result := answered (create {CHAT_REPLY}.make_json (201, codec.member_to_json (codec.member_of (l_created)), 0))
					else
						Result := answered (error_reply (l_result.error))
					end
				end
			else
				Result := answered (admin_refused (a_token))
			end
		ensure
			counted: request_count = old request_count + 1
		end

	admin_reset_password (a_token: separate READABLE_STRING_8; a_user_id: INTEGER_64; a_password: separate READABLE_STRING_32): CHAT_REPLY
			-- 200 and every session of that person dies; 404 for nobody or a bot.
		local
			l_password: STRING_32
			l_result: CHAT_RESULT [CHAT_USER]
		do
			if attached admin_for (a_token) then
				l_password := local_32 (a_password)
				if a_user_id > 0 and then attached service.store.user (a_user_id) as l_target and then not l_target.is_bot then
					if l_password.count < config.password_minimum then
						Result := answered (bad_request ("the password is too short"))
					else
						l_result := service.reset_password (l_target, l_password)
						if l_result.is_success then
							Result := answered (create {CHAT_REPLY}.make_json (200, create {SIMPLE_JSON_OBJECT}.make, 0))
						else
							Result := answered (error_reply (l_result.error))
						end
					end
				else
					Result := answered (create {CHAT_REPLY}.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_refused, "No such person.", 404)))
				end
			else
				Result := answered (admin_refused (a_token))
			end
		ensure
			counted: request_count = old request_count + 1
		end

	admin_create_bot (a_token: separate READABLE_STRING_8; a_username: separate READABLE_STRING_8; a_display_name: separate READABLE_STRING_32): CHAT_REPLY
			-- The bot's token is shown once, in this reply, and never stored in clear.
		local
			l_username: STRING_8
			l_display: STRING_32
			l_rules: CHAT_USER_RULES
			l_result: CHAT_RESULT [TUPLE [bot: CHAT_USER; token: STRING_8]]
		do
			if attached admin_for (a_token) then
				l_username := local_8 (a_username)
				l_display := local_32 (a_display_name)
				create l_rules
				if not l_display.is_empty and then not l_display.starts_with ({CHAT_EVENT_KINDS}.Bot_marker) then
					l_display := {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " " + l_display
				end
				if not l_rules.is_valid_username (l_username) then
					Result := answered (bad_request ("a username is 1..32 characters of [a-z0-9_]"))
				elseif not l_rules.is_marked_display_name (l_display) then
					Result := answered (bad_request ("a bot's display name is 1..40 visible characters"))
				else
					l_result := service.create_bot (l_username, l_display)
					if l_result.is_success and then attached l_result.value as l_created then
							-- The bot token travels in this one reply and nowhere else.
						Result := answered (create {CHAT_REPLY}.make_json (201,
							codec.login_to_json (l_created.token, codec.member_of (l_created.bot)), 0))
					else
						Result := answered (error_reply (l_result.error))
					end
				end
			else
				Result := answered (admin_refused (a_token))
			end
		ensure
			counted: request_count = old request_count + 1
		end

	admin_revoke_bot (a_token: separate READABLE_STRING_8; a_bot_id: INTEGER_64): CHAT_REPLY
			-- 200 and the bot's token dies; 404 for nobody or a person.
		do
			if attached admin_for (a_token) then
				if a_bot_id > 0 and then attached service.store.user (a_bot_id) as l_bot and then l_bot.is_bot then
					service.revoke_bot_token (l_bot)
					Result := answered (create {CHAT_REPLY}.make_json (200, create {SIMPLE_JSON_OBJECT}.make, 0))
				else
					Result := answered (create {CHAT_REPLY}.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_refused, "No such bot.", 404)))
				end
			else
				Result := answered (admin_refused (a_token))
			end
		ensure
			counted: request_count = old request_count + 1
		end

	admin_backup (a_token: separate READABLE_STRING_8): CHAT_REPLY
			-- {"path": ...}: the service writes the copy through the store
			-- (VACUUM INTO on SQLite) and answers where it landed; a store with
			-- no database file answers 503, never a half-written path.
		local
			l_result: CHAT_RESULT [STRING_32]
			l_json: SIMPLE_JSON_OBJECT
		do
			if attached admin_for (a_token) then
				l_result := service.backup
				if l_result.is_success and then attached l_result.value as l_path then
					create l_json.make
					l_json.put_string (l_path, {CHAT_JSON}.Key_path).do_nothing
					Result := answered (create {CHAT_REPLY}.make_json (200, l_json, 0))
				else
					Result := answered (error_reply (l_result.error))
				end
			else
				Result := answered (admin_refused (a_token))
			end
		ensure
			counted: request_count = old request_count + 1
		end

feature -- Answers: first-run bootstrap

	bootstrap_first_admin (a_username: separate READABLE_STRING_8; a_display_name, a_password: separate READABLE_STRING_32): CHAT_REPLY
			-- 201 with the first admin as a member, bringing the default room
			-- "main" to exist when no room does yet - the same assembly
			-- `--create-admin' performs on this processor (the service's
			-- creation order: room first, then `create_first_admin', so the
			-- admin joins the default room); 409 once any admin exists.
			-- ADDED for the doorbell assault (Phase 4 Task 3): the one
			-- cross-processor way to reach `service.create_first_admin',
			-- whose formals are not separate.
		local
			l_username: STRING_8
			l_display, l_password: STRING_32
			l_rules: CHAT_USER_RULES
			l_now: SIMPLE_DATE_TIME
			l_result: CHAT_RESULT [CHAT_USER]
		do
			l_username := local_8 (a_username)
			l_display := local_32 (a_display_name)
			l_password := local_32 (a_password)
			create l_rules
			if not l_rules.is_valid_username (l_username) then
				Result := answered (bad_request ("a username is 1..32 characters of [a-z0-9_]"))
			elseif not l_rules.is_valid_human_display_name (l_display) then
				Result := answered (bad_request ("a display name is 1..40 visible characters without the bot marker"))
			elseif l_password.count < config.password_minimum then
				Result := answered (bad_request ("the password is too short"))
			else
				if service.store.default_room = Void then
					create l_now.make_now
					service.store.add_room (create {CHAT_ROOM}.make (0, {STRING_32} "main", l_now))
				end
				l_result := service.create_first_admin (l_username, l_display, l_password)
				if l_result.is_success and then attached l_result.value as l_admin then
					Result := answered (create {CHAT_REPLY}.make_json (201, codec.member_to_json (codec.member_of (l_admin)), 0))
				else
					Result := answered (error_reply (l_result.error))
				end
			end
		ensure
			counted: request_count = old request_count + 1
			admin_on_success: Result.status = 201 implies service.store.has_admin
			room_on_success: Result.status = 201 implies service.store.default_room_id > 0
		end

feature {PARTICIPANT_DISPATCHER, DISPATCHER_HOST} -- The dispatcher's processor

	dispatcher_bot_id_of (a_index: INTEGER): INTEGER_64
			-- The stored, active bot user of [[participants]] entry `a_index'
			-- of THIS API's own configuration - resolved by username, created
			-- on first sight (the configuration drives the store the way
			-- --create-admin drives the first admin; the one-time bot token
			-- is dropped: a participant posts through this process, never the
			-- HTTP door). 0 - never an exception - for an index outside the
			-- configuration, a username a person holds, an inactive bot, or a
			-- failed creation. Only the expanded index crosses processors:
			-- the dispatcher must never ship its strings into a synchronous
			-- query here - the read-back while it blocks is a SCOOP deadlock.
		local
			l_list: ARRAYED_LIST [PARTICIPANT_CONFIG]
			l_entry: PARTICIPANT_CONFIG
			l_rules: CHAT_USER_RULES
		do
			l_list := config.participants
			if a_index >= 1 and a_index <= l_list.count then
				l_entry := l_list [a_index]
				create l_rules
				if l_rules.is_valid_username (l_entry.bot_username) and then l_rules.is_marked_display_name (l_entry.marked_display_name) then
					if attached service.store.user_by_username (l_entry.bot_username) as l_user then
						if l_user.is_bot and l_user.is_active then
							Result := l_user.id
						end
					elseif attached service.create_bot (l_entry.bot_username, l_entry.marked_display_name) as l_created and then l_created.is_success and then attached l_created.value as l_pair then
						Result := l_pair.bot.id
					end
				end
			end
			request_count := request_count + 1
		ensure
			counted: request_count = old request_count + 1
			resolved_or_zero: Result >= 0
			a_bot_when_positive: Result > 0 implies (attached service.store.user (Result) as u and then (u.is_bot and u.is_active))
		end

	dispatcher_last_event_sender (a_room_id: INTEGER_64): INTEGER_64
			-- The sender of the store's newest event when it belongs to
			-- `a_room_id'; 0 otherwise. The dispatcher's recovery probe: when
			-- a post's RETURN is eaten by a transient runtime failure (the
			-- EVE/Qs dirty-processor mark is consumed by the failing call),
			-- this tells whether the answer actually landed, so the books
			-- stay exact instead of over-counting failures.
		do
			if attached service.store.event (service.store.last_event_id) as e and then e.room_id = a_room_id then
				Result := e.sender_id
			end
			request_count := request_count + 1
		ensure
			counted: request_count = old request_count + 1
			non_negative: Result >= 0
		end

	dispatcher_start_after: INTEGER_64
			-- Where a new dispatcher begins: the store's last event id, so a
			-- restart never re-answers history (Issue 16).
		do
			Result := service.store.last_event_id
		ensure
			definition: Result = service.store.last_event_id
		end

	dispatcher_subscribe (a_subscriber: separate EVENT_SUBSCRIBER)
			-- Ring `a_subscriber' for every room from now on (NEW-1): the
			-- dispatcher is this process, so no token and no room check.
			-- The ticket is `last_subscription'.
		do
			service.bus.subscribe (a_subscriber)
			last_subscription := service.bus.last_ticket
		ensure
			live: last_subscription > 0 and service.bus.is_subscribed (last_subscription)
		end

	dispatcher_register (a_dispatcher: separate PARTICIPANT_DISPATCHER)
			-- Keep `a_dispatcher' so a request handler can reach an engine
			-- through `participant_dispatcher'. Held only as a reference and
			-- never called from this processor.
		do
			participant_dispatcher := a_dispatcher
		ensure
			kept: participant_dispatcher = a_dispatcher
			reachable: participant_dispatcher /= Void
			nothing_stored: service.store.last_event_id = old service.store.last_event_id
		end

	dispatcher_summary_allowed (a_key: separate READABLE_STRING_8): BOOLEAN
			-- One more SUMMARY under `a_key' if its own budget allows -
			-- decided and counted here, on the processor that owns the
			-- limiter. `a_key' is the caller's string, so it is copied to
			-- `last_summary_key' first and only the copy is spoken of below.
		require
			key_given: not a_key.is_empty
		do
			create last_summary_key.make_from_separate (a_key)
			Result := service.limits.is_allowed (last_summary_key)
			if Result then
				service.limits.record (last_summary_key)
			end
			request_count := request_count + 1
		ensure
			counted: request_count = old request_count + 1
			key_copied_here: not last_summary_key.is_empty
			summary_budget_only: last_summary_key.starts_with ("s:")
			recorded: Result implies service.limits.total (last_summary_key) >= 1
			nothing_when_refused: not Result implies service.limits.counts_model |=| old service.limits.counts_model
			nothing_stored: service.store.last_event_id = old service.store.last_event_id
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

	dispatcher_context (a_room_id, a_before_id: INTEGER_64; a_limit: INTEGER): STRING_8
			-- The `a_limit' events of `a_room_id' immediately BEFORE
			-- `a_before_id' as bytes - what `events_before' answers, without a
			-- token: the dispatcher is this process. The memory window a
			-- participant is given with a request (Phase 4): read from the
			-- room, so it holds the bot's own replies too and survives a
			-- restart. An unknown room gives an empty page.
		require
			before_positive: a_before_id > 0
			limit_in_range: a_limit > 0 and a_limit <= {CHAT_SERVICE}.Page_maximum
		local
			l_events: ARRAYED_LIST [CHAT_EVENT]
		do
			if a_room_id > 0 and then attached service.store.room (a_room_id) as l_room and then l_room.is_stored then
				l_events := service.events_before (l_room, a_before_id, a_limit)
			else
				create l_events.make (0)
			end
			Result := codec.bytes_of (codec.page_to_json (l_events, create {ARRAYED_LIST [CHAT_STATUS]}.make (0)))
			request_count := request_count + 1
		ensure
			counted: request_count = old request_count + 1
			decodable: codec.page_from_bytes (Result) /= Void
			bounded: attached codec.page_from_bytes (Result) as p implies p.events.count <= a_limit
			all_before: attached codec.page_from_bytes (Result) as p implies across p.events as e all e.id < a_before_id and e.room_id = a_room_id end
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
			recorded: Result implies service.limits.total (local_8 (a_key)) = old service.limits.total (local_8 (a_key)) + 1
			nothing_when_refused: not Result implies service.limits.counts_model |=| old service.limits.counts_model
		end

	dispatcher_post (a_bot_user_id, a_room_id: INTEGER_64; a_text: separate READABLE_STRING_32): INTEGER
			-- Post `a_text' as bot `a_bot_user_id' in `a_room_id': 201, else the
			-- service's error status - 403 when the bot cannot post there, 400
			-- for an empty or over-long text.
		local
			l_text: STRING_32
			l_result: CHAT_RESULT [CHAT_EVENT]
			l_muted: BOOLEAN
		do
			l_text := local_32 (a_text)
				-- The dispatcher is not rung for its OWN answer. This call
				-- carries the dispatcher's lock (`a_text' is the dispatcher's
				-- own string), so the ring inside the post below would re-enter
				-- `wake' on THIS thread while the dispatcher sits mid-drain -
				-- and a drain woken under its own feet breaks the frame it
				-- promises, unwinds with `is_dispatching' still True, and never
				-- answers again. Everyone else is rung exactly as before.
			service.bus.mute_dispatcher
			l_muted := True
			if attached service.store.user (a_bot_user_id) as u and then u.is_stored and then u.is_bot and then u.is_active
				and then attached service.store.room (a_room_id) as r and then r.is_stored and then service.store.is_member (u.id, r.id)
			then
				if l_text.is_empty or l_text.count > config.message_characters then
					check text_refused: True end
					Result := 400
				else
					check text_lawful: not l_text.is_empty and l_text.count <= config.message_characters end
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
			if l_muted then
				service.bus.unmute
				l_muted := False
			end
			request_count := request_count + 1
		ensure
			counted: request_count = old request_count + 1
			http_status: Result >= 200 and Result <= 599
			appended_on_success: Result = 201 implies service.store.last_event_id = old service.store.last_event_id + 1
			nothing_on_failure: Result /= 201 implies service.store.last_event_id = old service.store.last_event_id
			only_member_rooms: not dispatcher_can_post (a_bot_user_id, a_room_id) implies Result = 403
				-- The text rules (empty and over-long refused with 400) are `check' clauses in the
				-- body over the local copy: a postcondition must not re-read the SEPARATE `a_text' -
				-- ISE SCOOP evaluates a lock-passed call's postcondition after the caller's locks are
				-- returned, and that late reach into the caller's string surfaced as a phantom raise
				-- at the caller's next synchronization point (the answer posted, then "raised").
			nobody_left_muted: service.bus.muted_ticket = 0
		rescue
				-- A raise inside the post must not leave the dispatcher deaf.
			if l_muted then
				service.bus.unmute
				l_muted := False
			end
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

feature {NONE} -- Encodings

	members_json (a_room: CHAT_ROOM): SIMPLE_JSON_OBJECT
			-- {"members": [...]} - every stored member of `a_room', never a hash.
		require
			stored: a_room.is_stored
		local
			l_members: SIMPLE_JSON_ARRAY
		do
			create l_members.make
			across service.store.users as u loop
				if service.store.is_member (u.id, a_room.id) then
					l_members.add_object (codec.member_to_json (codec.member_of (u))).do_nothing
				end
			end
			create Result.make
			Result.put_array (l_members, {CHAT_JSON}.Key_members).do_nothing
		end

	rooms_json (a_user: CHAT_USER): SIMPLE_JSON_ARRAY
			-- [{id, name}] for `a_user''s rooms.
		require
			stored: a_user.is_stored
		local
			l_room: SIMPLE_JSON_OBJECT
		do
			create Result.make
			across service.rooms_of (a_user) as r loop
				create l_room.make
				l_room.put_integer (r.id, {CHAT_JSON}.Key_id).do_nothing
				l_room.put_string (r.name, {CHAT_JSON}.Key_name).do_nothing
				Result.add_object (l_room).do_nothing
			end
		end

	participants_json: SIMPLE_JSON_OBJECT
			-- {"participants": [{handle, username, display_name}]} from the configuration.
		local
			l_list: SIMPLE_JSON_ARRAY
			l_one: SIMPLE_JSON_OBJECT
		do
			create l_list.make
			across config.participants as p loop
				create l_one.make
				l_one.put_string (p.handle, {CHAT_JSON}.Key_handle).do_nothing
				l_one.put_string (p.bot_username.to_string_32, {CHAT_JSON}.Key_username).do_nothing
				l_one.put_string (p.bot_display_name, {CHAT_JSON}.Key_display_name).do_nothing
				l_list.add_object (l_one).do_nothing
			end
			create Result.make
			Result.put_array (l_list, {CHAT_JSON}.Key_participants).do_nothing
		end

	users_json: SIMPLE_JSON_OBJECT
			-- {"users": [...]} - every stored user as its public view, never a hash.
		local
			l_users: SIMPLE_JSON_ARRAY
		do
			create l_users.make
			across service.store.users as u loop
				l_users.add_object (codec.member_to_json (codec.member_of (u))).do_nothing
			end
			create Result.make
			Result.put_array (l_users, {CHAT_JSON}.Key_users).do_nothing
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

	admin_for (a_token: separate READABLE_STRING_8): detachable CHAT_USER
			-- The active admin behind `a_token', or Void.
		do
			if attached user_for (local_8 (a_token)) as l_user and then l_user.is_admin then
				Result := l_user
			end
		ensure
			admin: attached Result as u implies (u.is_admin and u.is_active)
		end

	admin_refused (a_token: separate READABLE_STRING_8): CHAT_REPLY
			-- 401 without a session, 403 for a person who is not an admin.
		do
			if user_for (local_8 (a_token)) = Void then
				Result := unauthorized
			else
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_refused, "admin only", 403))
			end
		ensure
			needs_session: old (user_for (local_8 (a_token)) = Void) implies Result.status = 401
			refusal: Result.status = 401 or Result.status = 403
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

	special_of (a_bytes: READABLE_STRING_8): SPECIAL [NATURAL_8]
			-- `a_bytes' as raw bytes.
		local
			i: INTEGER
		do
			create Result.make_filled (0, a_bytes.count)
			from
				i := 1
			until
				i > a_bytes.count
			loop
				Result [i - 1] := a_bytes.item (i).natural_32_code.to_natural_8
				i := i + 1
			end
		ensure
			same_size: Result.count = a_bytes.count
		end

feature {NONE} -- Implementation

	codec: CHAT_JSON

invariant
	counts_non_negative: request_count >= 0 and last_subscription >= 0
	store_open: service.store.is_open

end
