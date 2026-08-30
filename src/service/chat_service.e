note
	description: "[
		Every domain operation with every rule, in one place (Single
		Choice): authentication and sessions, posting, reading, uploads,
		administration. Returns CHAT_RESULT; never raises for a user's
		mistake. Depends on CHAT_STORE, not on SQLite; on EVENT_BUS as a
		doorbell (intent-v2 Q3): after a successful append it rings the
		room, and readers pull from the store.

		Lock order, never inverted: store < limiter < bus, and no lock is
		held while calling out to a subscriber (Q2).

		`store', `bus', `limits', `config' and `hasher' are public queries
		because the contracts speak of them (VAPE): a client that may call
		`post_message' may also ask whether it would be allowed.
	]"
	author: "Larry Rix"

class
	CHAT_SERVICE

create
	make

feature {NONE} -- Initialization

	make (a_store: CHAT_STORE; a_bus: EVENT_BUS; a_limits: RATE_LIMITER; a_config: SERVER_CONFIG; a_log: CHAT_LOG)
		require
			open: a_store.is_open
			valid_config: a_config.is_valid
		do
			store := a_store
			bus := a_bus
			limits := a_limits
			config := a_config
			log := a_log
			create hasher.make
			create issuer.make
			create crypto.make
		ensure
			set: store = a_store and bus = a_bus and limits = a_limits and config = a_config and log = a_log
		end

feature -- Access (the parts the contracts speak of)

	store: CHAT_STORE
	bus: EVENT_BUS
	limits: RATE_LIMITER
	config: SERVER_CONFIG
	hasher: PASSWORD_HASHER

feature -- Authentication

	authenticate (a_username, a_password: READABLE_STRING_GENERAL; a_client_ip: READABLE_STRING_8): CHAT_RESULT [CHAT_SESSION]
			-- A session for a person who proves their password; failures are
			-- counted per user and per client address (DR-013).
		require
			username_given: not a_username.is_empty
			password_given: not a_password.is_empty
			ip_given: not a_client_ip.is_empty
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4
		ensure
			never_void: Result /= Void
			success_has_session: Result.is_success implies attached Result.value
			session_is_fresh: (Result.is_success and then attached Result.value as s) implies s.created_at < s.expires_at
			locked_out_stays_out: (old not limits.is_allowed (login_user_key (a_username))) implies not Result.is_success
			failure_counted: not Result.is_success implies limits.count (login_user_key (a_username)) = old limits.count (login_user_key (a_username)) + 1
		end

	session_for_token (a_token: READABLE_STRING_8): detachable CHAT_SESSION
			-- The live session `a_token' identifies, or Void.
		require
			token_shape: a_token.count = 64
		do
			-- Implementation in Phase 4: store.session_by_hash (issuer.hash_of (a_token)), expiry checked
		ensure
			not_expired: attached Result as s implies not s.is_expired_at (now)
		end

	revoke (a_session: CHAT_SESSION)
		do
			-- Implementation in Phase 4
		ensure
			gone: store.session_by_hash (a_session.token_hash) = Void
		end

feature -- Posting

	post_message (a_sender: CHAT_USER; a_room: CHAT_ROOM; a_body: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_EVENT]
			-- Append a text message and ring the room.
		require
			active_sender: a_sender.is_active
			sender_stored: a_sender.is_stored
			room_stored: a_room.is_stored
			member: store.is_member (a_sender.id, a_room.id)
			body_given: not a_body.is_empty
			within_limit: a_body.count <= config.message_characters
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4
		ensure
			never_void: Result /= Void
			appended_on_success: Result.is_success implies store.last_event_id = old store.last_event_id + 1
			rung_on_success: Result.is_success implies bus.ring_count = old bus.ring_count + 1
			marker_enforced: (Result.is_success and a_sender.is_bot and then attached Result.value as e) implies e.body.starts_with ({CHAT_EVENT_KINDS}.Bot_marker)
			nothing_on_failure: not Result.is_success implies store.last_event_id = old store.last_event_id
			rate_limited: (old not limits.is_allowed (post_key (a_sender.id))) implies not Result.is_success
		end

	post_image (a_sender: CHAT_USER; a_room: CHAT_ROOM; a_attachment: CHAT_ATTACHMENT; a_caption: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_EVENT]
		require
			active_sender: a_sender.is_active
			sender_stored: a_sender.is_stored
			room_stored: a_room.is_stored
			member: store.is_member (a_sender.id, a_room.id)
			attachment_stored: a_attachment.id > 0
			own_upload: a_attachment.uploader_id = a_sender.id
			caption_within_limit: a_caption.count <= config.message_characters
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4
		ensure
			never_void: Result /= Void
			appended_on_success: Result.is_success implies store.last_event_id = old store.last_event_id + 1
			rung_on_success: Result.is_success implies bus.ring_count = old bus.ring_count + 1
			image_kind: (Result.is_success and then attached Result.value as e) implies e.is_image and e.attachment = a_attachment
			nothing_on_failure: not Result.is_success implies store.last_event_id = old store.last_event_id
		end

	post_system (a_room: CHAT_ROOM; a_text: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_EVENT]
			-- A notice from the server itself.
		require
			room_stored: a_room.is_stored
			text_given: not a_text.is_empty
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4
		ensure
			never_void: Result /= Void
			system_kind: (Result.is_success and then attached Result.value as e) implies e.is_system
		end

	publish_status (a_room: CHAT_ROOM; a_from: CHAT_USER; a_text: READABLE_STRING_GENERAL)
			-- An ephemeral notice on the stream; never stored (DR-009).
		require
			room_stored: a_room.is_stored
			text_given: not a_text.is_empty
		do
			-- Implementation in Phase 4: bus.ring_status (create {CHAT_STATUS}.make (...))
		ensure
			not_stored: store.last_event_id = old store.last_event_id
			rung: bus.status_count = old bus.status_count + 1
		end

feature -- Reading

	events_since (a_room: CHAT_ROOM; a_since_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
		require
			room_stored: a_room.is_stored
			since_non_negative: a_since_id >= 0
			limit_in_range: a_limit > 0 and a_limit <= Page_maximum
		do
			Result := store.events_since (a_room.id, a_since_id, a_limit)
		ensure
			bounded: Result.count <= a_limit
			all_after: across Result as e all e.id > a_since_id end
		end

	wait_for_events (a_room: CHAT_ROOM; a_since_id: INTEGER_64; a_limit, a_seconds: INTEGER): ARRAYED_LIST [CHAT_EVENT]
			-- The long-poll (D-018): what is after `a_since_id' now; else wait on the
			-- doorbell up to `a_seconds' and return what arrived, or nothing.
			-- Arms a POLL_WAITER, checks the store, waits, checks again.
		require
			room_stored: a_room.is_stored
			since_non_negative: a_since_id >= 0
			limit_in_range: a_limit > 0 and a_limit <= Page_maximum
			seconds_in_range: a_seconds >= 0 and a_seconds <= Max_wait_seconds
		do
			Result := store.events_since (a_room.id, a_since_id, a_limit)
			-- Implementation in Phase 4: if Result.is_empty and a_seconds > 0 then
			--   waiter.arm (a_room.id); bus.subscribe (waiter); Result := store.events_since (...);
			--   if Result.is_empty and then waiter.wait (a_seconds * 1000) then Result := store.events_since (...) end;
			--   bus.unsubscribe (waiter) end
		ensure
			bounded: Result.count <= a_limit
			all_after: across Result as e all e.id > a_since_id end
			nothing_appended: store.last_event_id = old store.last_event_id
		end

	events_before (a_room: CHAT_ROOM; a_before_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
		require
			room_stored: a_room.is_stored
			before_positive: a_before_id > 0
			limit_in_range: a_limit > 0 and a_limit <= Page_maximum
		do
			Result := store.events_before (a_room.id, a_before_id, a_limit)
		ensure
			bounded: Result.count <= a_limit
			all_before: across Result as e all e.id < a_before_id end
		end

	rooms_of (a_user: CHAT_USER): ARRAYED_LIST [CHAT_ROOM]
		require
			stored: a_user.is_stored
		do
			Result := store.rooms_of (a_user.id)
		end

	is_member (a_user: CHAT_USER; a_room: CHAT_ROOM): BOOLEAN
		require
			stored: a_user.is_stored and a_room.is_stored
		do
			Result := store.is_member (a_user.id, a_room.id)
		end

feature -- Uploads

	store_upload (a_uploader: CHAT_USER; a_original_name: READABLE_STRING_GENERAL; a_bytes: SPECIAL [NATURAL_8]): CHAT_RESULT [CHAT_ATTACHMENT]
			-- Keep `a_bytes' as uploads/<sha256>.<ext> if they are a PNG or
			-- JPEG by signature and within the size limit (intent-v2 Q5).
		require
			active: a_uploader.is_active and a_uploader.is_stored
			has_bytes: a_bytes.count > 0
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4
		ensure
			never_void: Result /= Void
			limited: a_bytes.count > config.upload_bytes implies not Result.is_success
			typed: not is_image_signature (a_bytes) implies not Result.is_success
			stored_on_success: (Result.is_success and then attached Result.value as a) implies a.id > 0 and a.uploader_id = a_uploader.id
		end

feature -- Administration

	create_user (a_username: READABLE_STRING_8; a_display_name, a_password: READABLE_STRING_GENERAL; a_is_admin: BOOLEAN): CHAT_RESULT [CHAT_USER]
		require
			valid_username: (create {CHAT_USER_RULES}).is_valid_username (a_username)
			valid_display: (create {CHAT_USER_RULES}).is_valid_display_name (a_display_name)
			password_long_enough: a_password.count >= config.password_minimum
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4
		ensure
			never_void: Result /= Void
			unique_or_error: Result.is_success = not (old store.has_username (a_username))
			hashed_properly: (Result.is_success and then attached Result.value as u) implies hasher.iterations_of (u.password_hash) >= {PASSWORD_HASHER}.Minimum_iterations
			joined_default_room: (Result.is_success and then attached Result.value as u and then attached store.default_room as r) implies store.is_member (u.id, r.id)
		end

	create_bot (a_username: READABLE_STRING_8; a_display_name: READABLE_STRING_GENERAL): CHAT_RESULT [TUPLE [bot: CHAT_USER; token: STRING_8]]
			-- A bot user and its one-time-shown token.
		require
			valid_username: (create {CHAT_USER_RULES}).is_valid_username (a_username)
			valid_display: (create {CHAT_USER_RULES}).is_valid_display_name (a_display_name)
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4
		ensure
			never_void: Result /= Void
			unique_or_error: Result.is_success = not (old store.has_username (a_username))
			is_bot: (Result.is_success and then attached Result.value as t) implies t.bot.is_bot
			token_shape: (Result.is_success and then attached Result.value as t) implies t.token.count = 64
		end

	reset_password (a_user: CHAT_USER; a_password: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_USER]
		require
			person: not a_user.is_bot
			stored: a_user.is_stored
			password_long_enough: a_password.count >= config.password_minimum
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4: hash, update_user, remove_sessions_of
		ensure
			never_void: Result /= Void
			verifiable: Result.is_success implies hasher.verify (a_password, a_user.password_hash)
		end

	change_password (a_user: CHAT_USER; a_old, a_new: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_USER]
		require
			person: not a_user.is_bot
			stored: a_user.is_stored
			old_given: not a_old.is_empty
			new_long_enough: a_new.count >= config.password_minimum
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4
		ensure
			never_void: Result /= Void
			old_required: not (old hasher.verify (a_old, a_user.password_hash)) implies not Result.is_success
			verifiable: Result.is_success implies hasher.verify (a_new, a_user.password_hash)
		end

	revoke_bot_token (a_bot: CHAT_USER)
		require
			bot: a_bot.is_bot and a_bot.is_stored
		do
			-- Implementation in Phase 4: store.remove_sessions_of (a_bot.id)
		end

	backup: CHAT_RESULT [STRING_32]
			-- A consistent copy of the database under data/backups/; its path.
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4
		ensure
			never_void: Result /= Void
		end

feature -- Access (contract support)

	now: SIMPLE_DATE_TIME
		do
			create Result.make_now
		end

	login_user_key (a_username: READABLE_STRING_GENERAL): STRING_8
		do
			Result := "login:user:" + a_username.as_lower.to_string_8
		end

	login_ip_key (a_ip: READABLE_STRING_8): STRING_8
		do
			Result := "login:ip:" + a_ip.to_string_8
		end

	post_key (a_user_id: INTEGER_64): STRING_8
		do
			Result := "post:" + a_user_id.out
		end

	is_image_signature (a_bytes: SPECIAL [NATURAL_8]): BOOLEAN
			-- PNG (89 50 4E 47 0D 0A 1A 0A) or JPEG (FF D8 FF)?
		do
			if a_bytes.count >= 8 then
				Result := (a_bytes [0] = 0x89 and a_bytes [1] = 0x50 and a_bytes [2] = 0x4E and a_bytes [3] = 0x47)
					or (a_bytes [0] = 0xFF and a_bytes [1] = 0xD8 and a_bytes [2] = 0xFF)
			end
		end

feature -- Constants

	Page_maximum: INTEGER = 500

	Max_wait_seconds: INTEGER = 25
			-- The longest a long-poll may hold a handler thread (intent-v3 Q15).

feature {NONE} -- Implementation

	log: CHAT_LOG
	issuer: SESSION_ISSUER
	crypto: SIMPLE_ENCRYPTION

	not_implemented_error: CHAT_ERROR
			-- Phase 1 stub outcome.
		do
			create Result.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501)
		end

invariant
	store_open: store.is_open

end
