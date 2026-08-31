note
	description: "[
		Every domain operation with every rule, in one place (Single
		Choice): authentication and sessions, posting, reading, uploads,
		administration. Returns CHAT_RESULT; never raises for a user's
		mistake. Depends on CHAT_STORE, not on SQLite; on EVENT_BUS as a
		doorbell (intent-v2 Q3): after a successful append it rings the
		room, and readers pull from the store.

		Concurrency (D1, SCOOP): one processor - the API's - owns this
		service and the store, bus, limiter and log with it, so one request
		executes here at a time and every postcondition below is exact.
		Nothing here blocks: waiting for news is the request handler's job
		(POLL_WAITER + POLL_WAIT on the request's processor). The bus wakes
		subscribers with asynchronous separate commands.

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
			configure_limits
		ensure
			set: store = a_store and bus = a_bus and limits = a_limits and config = a_config and log = a_log
			posts_limited: limits.limit_for (post_key (1)) = a_config.posts_per_minute and limits.window_for (post_key (1)) = Minute_seconds
			logins_limited: limits.limit_for (login_ip_key ("0")) = a_config.login_failures_per_10_minutes and limits.window_for (login_ip_key ("0")) = Ten_minutes_seconds
				and limits.limit_for (login_user_key ("x")) = a_config.login_failures_per_10_minutes and limits.window_for (login_user_key ("x")) = Ten_minutes_seconds
			participants_limited: across a_config.participants as p all
				limits.limit_for (participant_prefix (p.handle) + "1") = p.requests_per_hour and limits.window_for (participant_prefix (p.handle) + "1") = Hour_seconds end
		end

	configure_limits
			-- The configuration's limits become the limiter's rules: posts per minute,
			-- login failures per ten minutes (per user and per address), and each
			-- participant's requests per hour under its own "p:<handle>:" prefix.
		do
			limits.set_limit (Post_prefix, config.posts_per_minute, Minute_seconds)
			limits.set_limit (Login_user_prefix, config.login_failures_per_10_minutes, Ten_minutes_seconds)
			limits.set_limit (Login_ip_prefix, config.login_failures_per_10_minutes, Ten_minutes_seconds)
			across config.participants as p loop
				limits.set_limit (participant_prefix (p.handle), p.requests_per_hour, Hour_seconds)
			end
		ensure
			rules: limits.has_rule_for (post_key (1)) and limits.has_rule_for (login_user_key ("x")) and limits.has_rule_for (login_ip_key ("0"))
			counts_unchanged: limits.counts_model |=| old limits.counts_model
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
			failure_counted: (not Result.is_success and is_known_person (a_username) and old limits.is_allowed (login_user_key (a_username)))
				implies limits.total (login_user_key (a_username)) = old limits.total (login_user_key (a_username)) + 1
			unknown_names_uncounted: not is_known_person (a_username) implies limits.total (login_user_key (a_username)) = old limits.total (login_user_key (a_username))
				-- an attacker's made-up names are counted under the address only, so they cannot fill the limiter with keys
			ip_locked_out_stays_out: (old not limits.is_allowed (login_ip_key (a_client_ip))) implies not Result.is_success
			ip_failure_counted: (not Result.is_success and old limits.is_allowed (login_ip_key (a_client_ip)))
				implies limits.total (login_ip_key (a_client_ip)) = old limits.total (login_ip_key (a_client_ip)) + 1
			success_uncounted: Result.is_success implies (limits.total (login_user_key (a_username)) = old limits.total (login_user_key (a_username))
				and limits.total (login_ip_key (a_client_ip)) = old limits.total (login_ip_key (a_client_ip)))
			no_session_on_failure: not Result.is_success implies Result.value = Void
			invalid_username_refused: not is_plausible_username (a_username) implies not Result.is_success
			bots_and_inactive_refused: (is_plausible_username (a_username) and then attached store.user_by_username (a_username.to_string_8) as u and then (u.is_bot or not u.is_active)) implies not Result.is_success
		end

	session_for_token (a_token: READABLE_STRING_8): detachable CHAT_SESSION
			-- The live session `a_token' identifies, or Void.
		require
			token_shape: a_token.count = 64
		do
			-- Implementation in Phase 4: store.session_by_hash (issuer.hash_of (a_token)), expiry checked
		ensure
			not_expired: attached Result as s implies not s.is_expired_at (now)
			right_one: attached Result as s2 implies s2.token_hash.same_string (token_hash_of (a_token))
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
			room_known: store.has_room (a_room.id)
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
			recorded_on_success: Result.is_success implies limits.total (post_key (a_sender.id)) = old limits.total (post_key (a_sender.id)) + 1
			unrecorded_on_failure: not Result.is_success implies limits.total (post_key (a_sender.id)) = old limits.total (post_key (a_sender.id))
			right_event: (Result.is_success and then attached Result.value as e) implies (e.room_id = a_room.id and e.sender_id = a_sender.id and e.is_message and e.is_bot_authored = a_sender.is_bot)
			body_kept: (Result.is_success and not a_sender.is_bot and then attached Result.value as e) implies e.body.same_string_general (a_body)
			bot_body_kept: (Result.is_success and a_sender.is_bot and then attached Result.value as e) implies e.body.ends_with_general (a_body)
			humans_unmarked: (Result.is_success and not a_sender.is_bot and then attached Result.value as e) implies not e.body.starts_with ({CHAT_EVENT_KINDS}.Bot_marker)
		end

	post_image (a_sender: CHAT_USER; a_room: CHAT_ROOM; a_attachment: CHAT_ATTACHMENT; a_caption: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_EVENT]
		require
			active_sender: a_sender.is_active
			sender_stored: a_sender.is_stored
			room_stored: a_room.is_stored
			room_known: store.has_room (a_room.id)
			member: store.is_member (a_sender.id, a_room.id)
			attachment_stored: store.has_attachment (a_attachment.id)
			own_upload: a_attachment.uploader_id = a_sender.id
			caption_within_limit: a_caption.count <= config.message_characters
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4
		ensure
			never_void: Result /= Void
			appended_on_success: Result.is_success implies store.last_event_id = old store.last_event_id + 1
			rung_on_success: Result.is_success implies bus.ring_count = old bus.ring_count + 1
			image_kind: (Result.is_success and then attached Result.value as e) implies (e.is_image and then attached e.attachment as ea and then ea.id = a_attachment.id)
			nothing_on_failure: not Result.is_success implies store.last_event_id = old store.last_event_id
			rate_limited: (old not limits.is_allowed (post_key (a_sender.id))) implies not Result.is_success
			recorded_on_success: Result.is_success implies limits.total (post_key (a_sender.id)) = old limits.total (post_key (a_sender.id)) + 1
			unrecorded_on_failure: not Result.is_success implies limits.total (post_key (a_sender.id)) = old limits.total (post_key (a_sender.id))
			right_event: (Result.is_success and then attached Result.value as e) implies (e.room_id = a_room.id and e.sender_id = a_sender.id and e.is_bot_authored = a_sender.is_bot)
			caption_kept: (Result.is_success and then attached Result.value as e) implies e.body.ends_with_general (a_caption)
		end

	post_system (a_room: CHAT_ROOM; a_text: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_EVENT]
			-- A notice from the server itself (sender 0).
		require
			room_stored: a_room.is_stored
			room_known: store.has_room (a_room.id)
			text_given: not a_text.is_empty
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4
		ensure
			never_void: Result /= Void
			system_kind: (Result.is_success and then attached Result.value as e) implies (e.is_system and e.sender_id = 0 and e.room_id = a_room.id)
			appended_on_success: Result.is_success implies store.last_event_id = old store.last_event_id + 1
			rung_on_success: Result.is_success implies bus.ring_count = old bus.ring_count + 1
			nothing_on_failure: not Result.is_success implies store.last_event_id = old store.last_event_id
		end

	publish_status (a_room: CHAT_ROOM; a_from: CHAT_USER; a_text: READABLE_STRING_GENERAL)
			-- An ephemeral notice on the stream; never stored (DR-009).
		require
			room_stored: a_room.is_stored
			room_known: store.has_room (a_room.id)
			from_stored: a_from.is_stored
			text_given: not a_text.is_empty
			text_bounded: a_text.count <= {CHAT_STATUS}.Text_maximum
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
			room_known: store.has_room (a_room.id)
			since_non_negative: a_since_id >= 0
			limit_in_range: a_limit > 0 and a_limit <= Page_maximum
		do
			Result := store.events_since (a_room.id, a_since_id, a_limit)
		ensure
			bounded: Result.count <= a_limit
			all_after: across Result as e all e.id > a_since_id end
		end

	events_before (a_room: CHAT_ROOM; a_before_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
		require
			room_stored: a_room.is_stored
			room_known: store.has_room (a_room.id)
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
			valid_name: (create {CHAT_ATTACHMENT_RULES}).is_valid_name (a_original_name)
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4
		ensure
			never_void: Result /= Void
			limited: a_bytes.count > config.upload_bytes implies not Result.is_success
			typed: not is_image_signature (a_bytes) implies not Result.is_success
			stored_on_success: (Result.is_success and then attached Result.value as a) implies (a.id > 0 and a.uploader_id = a_uploader.id and store.has_attachment (a.id))
			sized: (Result.is_success and then attached Result.value as a2) implies a2.size = a_bytes.count
			typed_mime: (Result.is_success and then attached Result.value as a3) implies (a3.mime.same_string ({CHAT_ATTACHMENT}.Mime_png) = is_png_signature (a_bytes))
			hashed: (Result.is_success and then attached Result.value as a4) implies a4.sha256.same_string (sha256_hex_of (a_bytes))
			named: (Result.is_success and then attached Result.value as a5) implies a5.original_name.same_string_general (a_original_name)
			nothing_on_failure: not Result.is_success implies store.attachment_count = old store.attachment_count
		end

feature -- Administration

	create_user (a_username: READABLE_STRING_8; a_display_name, a_password: READABLE_STRING_GENERAL; a_is_admin: BOOLEAN): CHAT_RESULT [CHAT_USER]
		require
			valid_username: (create {CHAT_USER_RULES}).is_valid_username (a_username)
			valid_display: (create {CHAT_USER_RULES}).is_valid_human_display_name (a_display_name)
			password_long_enough: a_password.count >= config.password_minimum
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4
		ensure
			never_void: Result /= Void
			duplicate_refused: old store.has_username (a_username) implies not Result.is_success
			success_is_fresh: Result.is_success implies not (old store.has_username (a_username))
			hashed_properly: (Result.is_success and then attached Result.value as u) implies hasher.iterations_of (u.password_hash) >= {PASSWORD_HASHER}.Minimum_iterations
			joined_default_room: (Result.is_success and then attached Result.value as u and then attached store.default_room as r) implies store.is_member (u.id, r.id)
		end

	create_first_admin (a_username: READABLE_STRING_8; a_display_name, a_password: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_USER]
			-- The one way the first admin comes to exist (`--create-admin'); refused once any admin exists.
		require
			valid_username: (create {CHAT_USER_RULES}).is_valid_username (a_username)
			valid_display: (create {CHAT_USER_RULES}).is_valid_human_display_name (a_display_name)
			password_long_enough: a_password.count >= config.password_minimum
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4: if not store.has_admin then create_user (..., True)
		ensure
			never_void: Result /= Void
			refused_when_admin_exists: old store.has_admin implies not Result.is_success
			duplicate_refused: old store.has_username (a_username) implies not Result.is_success
			admin_on_success: (Result.is_success and then attached Result.value as u) implies (u.is_admin and store.has_admin)
		end

	create_bot (a_username: READABLE_STRING_8; a_display_name: READABLE_STRING_GENERAL): CHAT_RESULT [TUPLE [bot: CHAT_USER; token: STRING_8]]
			-- A bot user and its one-time-shown token.
		require
			valid_username: (create {CHAT_USER_RULES}).is_valid_username (a_username)
			valid_display: (create {CHAT_USER_RULES}).is_marked_display_name (a_display_name)
		do
			create Result.make_error (not_implemented_error)
			-- Implementation in Phase 4
		ensure
			never_void: Result /= Void
			duplicate_refused: old store.has_username (a_username) implies not Result.is_success
			success_is_fresh: Result.is_success implies not (old store.has_username (a_username))
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
			verifiable: Result.is_success implies (attached store.user (a_user.id) as u and then hasher.verify (a_password, u.password_hash))
			sessions_revoked: Result.is_success implies not store.has_session_of (a_user.id)
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
			verifiable: Result.is_success implies (attached store.user (a_user.id) as u and then hasher.verify (a_new, u.password_hash))
		end

	revoke_bot_token (a_bot: CHAT_USER)
		require
			bot: a_bot.is_bot and a_bot.is_stored
		do
			-- Implementation in Phase 4: store.remove_sessions_of (a_bot.id)
		ensure
			revoked: not store.has_session_of (a_bot.id)
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

	token_hash_of (a_token: READABLE_STRING_8): STRING_8
			-- What the store keeps for `a_token' (its SHA-256, hex).
		do
			Result := issuer.hash_of (a_token)
		ensure
			shape: Result.count = 64
		end

	login_user_key (a_username: READABLE_STRING_GENERAL): STRING_8
		do
			Result := Login_user_prefix + {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_username.as_lower)
		ensure
			prefixed: Result.starts_with (Login_user_prefix)
		end

	login_ip_key (a_ip: READABLE_STRING_8): STRING_8
		do
			Result := Login_ip_prefix + a_ip.to_string_8
		ensure
			prefixed: Result.starts_with (Login_ip_prefix)
		end

	participant_prefix (a_handle: READABLE_STRING_GENERAL): STRING_8
			-- The limiter prefix of every asker's key for the participant `a_handle' (PARTICIPANT.limit_key).
		do
			Result := "p:" + {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_handle) + ":"
		ensure
			shape: Result.starts_with ("p:") and Result.ends_with (":")
		end

	is_known_person (a_username: READABLE_STRING_GENERAL): BOOLEAN
			-- A plausible username that names a stored user?
		do
			Result := is_plausible_username (a_username) and then store.has_username (a_username.to_string_8)
		end

	sha256_hex_of (a_bytes: SPECIAL [NATURAL_8]): STRING_8
			-- The SHA-256 of `a_bytes' as 64 lowercase hex digits.
		local
			l_data: STRING_8
			i: INTEGER
		do
			create l_data.make (a_bytes.count)
			from i := 0 until i >= a_bytes.count loop
				l_data.append_code (a_bytes [i])
				i := i + 1
			end
			Result := crypto.sha256 (l_data).as_lower
		ensure
			shape: Result.count = 64
		end

	Post_prefix: STRING_8 = "post:"
	Login_user_prefix: STRING_8 = "login:user:"
	Login_ip_prefix: STRING_8 = "login:ip:"

	Minute_seconds: INTEGER = 60
	Ten_minutes_seconds: INTEGER = 600
	Hour_seconds: INTEGER = 3600

	is_plausible_username (a_username: READABLE_STRING_GENERAL): BOOLEAN
			-- ASCII and within the username rules - the only names a lookup may be attempted for.
		do
			Result := a_username.is_valid_as_string_8 and then (create {CHAT_USER_RULES}).is_valid_username (a_username.to_string_8)
		end

	post_key (a_user_id: INTEGER_64): STRING_8
		do
			Result := "post:" + a_user_id.out
		end

	is_image_signature (a_bytes: SPECIAL [NATURAL_8]): BOOLEAN
			-- PNG or JPEG by signature?
		do
			Result := is_png_signature (a_bytes) or is_jpeg_signature (a_bytes)
		end

	is_png_signature (a_bytes: SPECIAL [NATURAL_8]): BOOLEAN
			-- 89 50 4E 47 0D 0A 1A 0A - all eight bytes.
		do
			Result := a_bytes.count >= 8 and then (a_bytes [0] = 0x89 and a_bytes [1] = 0x50 and a_bytes [2] = 0x4E and a_bytes [3] = 0x47
				and a_bytes [4] = 0x0D and a_bytes [5] = 0x0A and a_bytes [6] = 0x1A and a_bytes [7] = 0x0A)
		end

	is_jpeg_signature (a_bytes: SPECIAL [NATURAL_8]): BOOLEAN
			-- FF D8 FF.
		do
			Result := a_bytes.count >= 3 and then (a_bytes [0] = 0xFF and a_bytes [1] = 0xD8 and a_bytes [2] = 0xFF)
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
