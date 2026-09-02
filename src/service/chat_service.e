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
			create last_issued_token.make_empty
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

	last_issued_token: STRING_8
			-- The clear token of the latest successful `authenticate' (DR-006:
			-- the store keeps only its hash). The login reply is the one place
			-- it travels (CHAT_API, Task 2); empty before the first success.

feature -- Authentication

	authenticate (a_username, a_password: READABLE_STRING_GENERAL; a_client_ip: READABLE_STRING_8): CHAT_RESULT [CHAT_SESSION]
			-- A session for a person who proves their password; failures are
			-- counted per user and per client address (DR-013).
		require
			username_given: not a_username.is_empty
			password_given: not a_password.is_empty
			ip_given: not a_client_ip.is_empty
		local
			l_user_key, l_ip_key: STRING_8
			l_user_allowed, l_ip_allowed: BOOLEAN
			l_issued: TUPLE [token: STRING_8; session: CHAT_SESSION]
		do
			l_user_key := login_user_key (a_username)
			l_ip_key := login_ip_key (a_client_ip)
			l_user_allowed := limits.is_allowed (l_user_key)
			l_ip_allowed := limits.is_allowed (l_ip_key)
			if not is_plausible_username (a_username) then
				if l_ip_allowed then
					limits.record (l_ip_key)
				end
				create Result.make_error (bad_credentials_error)
			elseif not l_user_allowed or not l_ip_allowed then
				if is_known_person (a_username) and l_user_allowed then
					limits.record (l_user_key)
				end
				if l_ip_allowed then
					limits.record (l_ip_key)
				end
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_locked_out, "Too many login failures; try again later.", 429))
				log.warn ("login locked out")
			elseif attached store.user_by_username (a_username.to_string_8) as l_user then
				if l_user.is_bot or not l_user.is_active then
					limits.record (l_user_key)
					limits.record (l_ip_key)
					create Result.make_error (bad_credentials_error)
				elseif hasher.verify (a_password, l_user.password_hash) then
					l_issued := issuer.issue (l_user, config.session_days.to_integer_64 * Day_seconds, False)
					store.put_session (l_issued.session)
					last_issued_token := l_issued.token
					log.info ("login ok user=" + l_user.id.out)
					create Result.make_success (l_issued.session)
				else
					limits.record (l_user_key)
					limits.record (l_ip_key)
					create Result.make_error (bad_credentials_error)
				end
			else
				limits.record (l_ip_key)
				create Result.make_error (bad_credentials_error)
			end
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
			if attached store.session_by_hash (token_hash_of (a_token)) as l_session then
				if l_session.is_expired_at (now) then
					store.remove_session (l_session.token_hash)
				else
					Result := l_session
				end
			end
		ensure
			not_expired: attached Result as s implies not s.is_expired_at (now)
			right_one: attached Result as s2 implies s2.token_hash.same_string (token_hash_of (a_token))
		end

	revoke (a_session: CHAT_SESSION)
		do
			store.remove_session (a_session.token_hash)
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
		local
			l_body: STRING_32
			l_event: CHAT_EVENT
		do
			if not limits.is_allowed (post_key (a_sender.id)) then
				create Result.make_error (rate_limited_error)
			elseif not a_sender.is_bot and then a_body.to_string_32.starts_with ({CHAT_EVENT_KINDS}.Bot_marker) then
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_refused, "The bot marker is reserved for bot messages.", 403))
			else
				l_body := a_body.to_string_32
				if a_sender.is_bot and then not l_body.starts_with ({CHAT_EVENT_KINDS}.Bot_marker) then
					l_body := {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " " + l_body
				end
				l_event := store.append_event (create {CHAT_EVENT_DRAFT}.make (a_room.id, a_sender.id,
					{CHAT_EVENT_KINDS}.Kind_message, l_body, Void, create {SIMPLE_JSON_OBJECT}.make, a_sender.is_bot))
				limits.record (post_key (a_sender.id))
				bus.ring (a_room.id)
				log.info ("post message event=" + l_event.id.out + " room=" + a_room.id.out + " sender=" + a_sender.id.out)
				create Result.make_success (l_event)
			end
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
		local
			l_event: CHAT_EVENT
		do
			if not limits.is_allowed (post_key (a_sender.id)) then
				create Result.make_error (rate_limited_error)
			else
				l_event := store.append_event (create {CHAT_EVENT_DRAFT}.make (a_room.id, a_sender.id,
					{CHAT_EVENT_KINDS}.Kind_image, a_caption, a_attachment, create {SIMPLE_JSON_OBJECT}.make, a_sender.is_bot))
				limits.record (post_key (a_sender.id))
				bus.ring (a_room.id)
				log.info ("post image event=" + l_event.id.out + " room=" + a_room.id.out + " sender=" + a_sender.id.out)
				create Result.make_success (l_event)
			end
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
		local
			l_event: CHAT_EVENT
		do
			l_event := store.append_event (create {CHAT_EVENT_DRAFT}.make (a_room.id, 0,
				{CHAT_EVENT_KINDS}.Kind_system, a_text, Void, create {SIMPLE_JSON_OBJECT}.make, False))
			bus.ring (a_room.id)
			log.info ("post system event=" + l_event.id.out + " room=" + a_room.id.out)
			create Result.make_success (l_event)
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
			bus.ring_status (create {CHAT_STATUS}.make (a_room.id, a_from.display_name, a_text))
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
			-- Keep `a_bytes' if they are a PNG or JPEG by signature and
			-- within the size limit (intent-v2 Q5): the metadata row and,
			-- since Phase 4 Task 4, the bytes themselves through the
			-- store's `put_attachment_bytes'.
		require
			active: a_uploader.is_active and a_uploader.is_stored
			has_bytes: a_bytes.count > 0
			valid_name: (create {CHAT_ATTACHMENT_RULES}).is_valid_name (a_original_name)
			uploader_known: store.has_user (a_uploader.id)
		local
			l_mime: STRING_8
			l_attachment: CHAT_ATTACHMENT
		do
			if a_bytes.count > config.upload_bytes then
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_too_large, "The upload is larger than the server allows.", 413))
			elseif not is_image_signature (a_bytes) then
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_bad_type, "Only PNG and JPEG images are accepted.", 415))
			else
				if is_png_signature (a_bytes) then
					l_mime := {CHAT_ATTACHMENT}.Mime_png
				else
					l_mime := {CHAT_ATTACHMENT}.Mime_jpeg
				end
				create l_attachment.make (0, a_uploader.id, a_original_name, l_mime, a_bytes.count, sha256_hex_of (a_bytes), now)
				store.add_attachment (l_attachment)
				store.put_attachment_bytes (l_attachment.id, a_bytes)
				log.info ("upload attachment=" + l_attachment.id.out + " uploader=" + a_uploader.id.out + " bytes=" + a_bytes.count.out)
				create Result.make_success (l_attachment)
			end
		ensure
			never_void: Result /= Void
			limited: a_bytes.count > config.upload_bytes implies not Result.is_success
			typed: not is_image_signature (a_bytes) implies not Result.is_success
			stored_on_success: (Result.is_success and then attached Result.value as a) implies (a.id > 0 and a.uploader_id = a_uploader.id and store.has_attachment (a.id))
			sized: (Result.is_success and then attached Result.value as a2) implies a2.size = a_bytes.count
			typed_mime: (Result.is_success and then attached Result.value as a3) implies (a3.mime.same_string ({CHAT_ATTACHMENT}.Mime_png) = is_png_signature (a_bytes))
			hashed: (Result.is_success and then attached Result.value as a4) implies a4.sha256.same_string (sha256_hex_of (a_bytes))
			named: (Result.is_success and then attached Result.value as a5) implies a5.original_name.same_string_general (a_original_name)
			bytes_kept: (Result.is_success and then attached Result.value as a6) implies store.has_attachment_bytes (a6.id)
			nothing_on_failure: not Result.is_success implies store.attachment_count = old store.attachment_count
		end

feature -- Administration

	create_user (a_username: READABLE_STRING_8; a_display_name, a_password: READABLE_STRING_GENERAL; a_is_admin: BOOLEAN): CHAT_RESULT [CHAT_USER]
		require
			valid_username: (create {CHAT_USER_RULES}).is_valid_username (a_username)
			valid_display: (create {CHAT_USER_RULES}).is_valid_human_display_name (a_display_name)
			password_long_enough: a_password.count >= config.password_minimum
		local
			l_user: CHAT_USER
		do
			if store.has_username (a_username) then
				create Result.make_error (exists_error)
			else
				create l_user.make (0, a_username, a_display_name, hasher.hash (a_password), a_is_admin, False, now)
				store.add_user (l_user)
				if attached store.default_room as l_room then
					store.add_membership (create {CHAT_MEMBERSHIP}.make (l_room.id, l_user.id, {CHAT_MEMBERSHIP}.Role_member, now))
				end
				log.info ("user created id=" + l_user.id.out)
				create Result.make_success (l_user)
			end
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
			if store.has_admin then
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_exists, "An administrator already exists.", 409))
			else
				if store.default_room = Void then
						-- The first admin brings the room to exist: a fresh database has none,
						-- and an administrator with nowhere to post is no chat (found by the
						-- first live smoke test - rooms answered [] and every post not_member).
					store.add_room (create {CHAT_ROOM}.make (0, {STRING_32} "main", now))
				end
				Result := create_user (a_username, a_display_name, a_password, True)
			end
		ensure
			never_void: Result /= Void
			refused_when_admin_exists: old store.has_admin implies not Result.is_success
			duplicate_refused: old store.has_username (a_username) implies not Result.is_success
			admin_on_success: (Result.is_success and then attached Result.value as u) implies (u.is_admin and store.has_admin)
			room_on_success: Result.is_success implies store.default_room_id > 0
			admin_is_member: (Result.is_success and then attached Result.value as u2) implies store.is_member (u2.id, store.default_room_id)
		end

	create_bot (a_username: READABLE_STRING_8; a_display_name: READABLE_STRING_GENERAL): CHAT_RESULT [TUPLE [bot: CHAT_USER; token: STRING_8]]
			-- A bot user and its one-time-shown token.
		require
			valid_username: (create {CHAT_USER_RULES}).is_valid_username (a_username)
			valid_display: (create {CHAT_USER_RULES}).is_marked_display_name (a_display_name)
		local
			l_bot: CHAT_USER
			l_issued: TUPLE [token: STRING_8; session: CHAT_SESSION]
		do
			if store.has_username (a_username) then
				create Result.make_error (exists_error)
			else
				create l_bot.make (0, a_username, a_display_name, "", False, True, now)
				store.add_user (l_bot)
				if attached store.default_room as l_room then
					store.add_membership (create {CHAT_MEMBERSHIP}.make (l_room.id, l_bot.id, {CHAT_MEMBERSHIP}.Role_member, now))
				end
				l_issued := issuer.issue (l_bot, Bot_token_lifetime_seconds, True)
				store.put_session (l_issued.session)
				log.info ("bot created id=" + l_bot.id.out)
				create Result.make_success ([l_bot, l_issued.token])
			end
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
			if attached store.user (a_user.id) as l_user and then not l_user.is_bot then
				l_user.set_password_hash (hasher.hash (a_password))
				store.update_user (l_user)
				store.remove_sessions_of (a_user.id)
				log.info ("password reset user=" + a_user.id.out)
				create Result.make_success (l_user)
			else
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_refused, "That user is not stored here.", 404))
			end
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
			if not hasher.verify (a_old, a_user.password_hash) then
				create Result.make_error (bad_credentials_error)
			elseif attached store.user (a_user.id) as l_user and then not l_user.is_bot then
				l_user.set_password_hash (hasher.hash (a_new))
				store.update_user (l_user)
				log.info ("password changed user=" + a_user.id.out)
				create Result.make_success (l_user)
			else
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_refused, "That user is not stored here.", 404))
			end
		ensure
			never_void: Result /= Void
			old_required: not (old hasher.verify (a_old, a_user.password_hash)) implies not Result.is_success
			verifiable: Result.is_success implies (attached store.user (a_user.id) as u and then hasher.verify (a_new, u.password_hash))
		end

	revoke_bot_token (a_bot: CHAT_USER)
		require
			bot: a_bot.is_bot and a_bot.is_stored
		do
			store.remove_sessions_of (a_bot.id)
		ensure
			revoked: not store.has_session_of (a_bot.id)
		end

	backup: CHAT_RESULT [STRING_32]
			-- A consistent copy of the database under data/backups/; its path.
			-- The store writes the copy (CHAT_STORE.backup_to, Task 9b): the
			-- SQLite store through SQLite's own VACUUM INTO, the memory oracle
			-- not at all - it has nothing on disk, and says so as a 503 result
			-- rather than pretending. A failure is a result, never an exception:
			-- an administrator asking for a backup must not bring the server down.
		local
			l_path: STRING_32
		do
			l_path := fresh_backup_path
			if not l_path.is_empty and then store.backup_to (l_path) then
				log.info ("backup written")
				create Result.make_success (l_path)
			else
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable,
					"The database could not be copied; nothing was written.", 503))
			end
		ensure
			never_void: Result /= Void
			path_on_success: (Result.is_success and then attached Result.value as p) implies
				(not p.is_empty and store.is_file_at (p))
			store_untouched: store.last_event_id = old store.last_event_id
				and store.event_count = old store.event_count
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
	Day_seconds: INTEGER = 86400

	Bot_token_lifetime_seconds: INTEGER = 315360000
			-- Ten years: a bot token lives until it is revoked.

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

	fresh_backup_path: STRING_32
			-- <data_dir>/backups/simple_chat-YYYYMMDD-HHMMSS[-N].db, with the
			-- directory made and the name proved free, so two backups taken in
			-- the same second are two files; empty when the directory cannot be
			-- made or every candidate name is taken. Never raises.
		local
			l_directory: DIRECTORY
			l_folder: PATH
			l_base, l_candidate: STRING_32
			l_failed: BOOLEAN
			i: INTEGER
		do
			if l_failed then
				create Result.make_empty
			else
				create l_folder.make_from_string (config.data_dir)
				l_folder := l_folder.extended (Backups_directory_name)
				create l_directory.make_with_path (l_folder)
				if not l_directory.exists then
					l_directory.recursive_create_dir
				end
				l_base := {STRING_32} "simple_chat-" + compact_stamp (now)
				l_candidate := l_folder.extended (l_base + Backup_extension).name
				from
					i := 1
				until
					not store.is_file_at (l_candidate) or i > Backup_name_attempts
				loop
					l_candidate := l_folder.extended (l_base + {STRING_32} "-" + i.out.to_string_32 + Backup_extension).name
					i := i + 1
				variant
					Backup_name_attempts + 1 - i
				end
				if store.is_file_at (l_candidate) then
					create Result.make_empty
				else
					Result := l_candidate
				end
			end
		ensure
			free_when_given: not Result.is_empty implies not store.is_file_at (Result)
		rescue
			l_failed := True
			retry
		end

	compact_stamp (a_when: SIMPLE_DATE_TIME): STRING_32
			-- `a_when' as YYYYMMDD-HHMMSS: ISO 8601's colons are not legal in a
			-- Windows file name, so the punctuation goes and the date stays sortable.
		local
			l_iso: STRING_8
		do
			l_iso := a_when.to_iso8601
			create Result.make (15)
			Result.append_string_general (l_iso.substring (1, 4))
			Result.append_string_general (l_iso.substring (6, 7))
			Result.append_string_general (l_iso.substring (9, 10))
			Result.append_string_general ("-")
			Result.append_string_general (l_iso.substring (12, 13))
			Result.append_string_general (l_iso.substring (15, 16))
			Result.append_string_general (l_iso.substring (18, 19))
		ensure
			shaped: Result.count = 15
		end

	Backups_directory_name: STRING_32 = "backups"
	Backup_extension: STRING_32 = ".db"
	Backup_name_attempts: INTEGER = 1000
			-- A thousand backups in one second is not a backup, it is a loop.

	bad_credentials_error: CHAT_ERROR
			-- The one refusal a guesser sees (no username oracle).
		do
			create Result.make ({CHAT_ERROR}.Code_bad_credentials, "The username or password is not right.", 401)
		end

	rate_limited_error: CHAT_ERROR
		do
			create Result.make ({CHAT_ERROR}.Code_rate_limited, "Too many posts; wait a moment.", 429)
		end

	exists_error: CHAT_ERROR
		do
			create Result.make ({CHAT_ERROR}.Code_exists, "That username is already taken.", 409)
		end

invariant
	store_open: store.is_open

end
