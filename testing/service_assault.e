note
	description: "[
		CHAT_SERVICE's Phase 4 bodies under assault, over the memory store:
		the first admin's uniqueness, login lockout and recovery, the user
		limiter never fed by made-up names, the marker law on both kinds of
		author, the post limit hitting and recovering, the upload rules
		(signature, size, hash and path pinned), gapless paging, session
		round trips for people and bots, and the password commands.
		Hand-computed expectations throughout.
	]"
	author: "Larry Rix"

class
	SERVICE_ASSAULT

inherit
	TEST_SET_BASE

feature -- Administration

	test_first_admin_created_once
		local
			l_service: CHAT_SERVICE
			l_result: CHAT_RESULT [CHAT_USER]
		do
			l_service := service
			l_result := l_service.create_first_admin ("larry", {STRING_32} "Larry", {STRING_32} "open sesame 42")
			assert ("admin created", l_result.is_success and attached l_result.value as u and then (u.is_admin and u.is_stored and l_service.store.has_admin))
			assert ("joined the default room", attached l_result.value as u2 and then l_service.store.is_member (u2.id, l_service.store.default_room_id))
			l_result := l_service.create_first_admin ("mallory", {STRING_32} "Mallory", {STRING_32} "open sesame 42")
			assert ("second admin refused", not l_result.is_success and attached l_result.error as e and then e.code.same_string ({CHAT_ERROR}.Code_exists))
			l_result := l_service.create_user ("larry", {STRING_32} "Larry Two", {STRING_32} "open sesame 42", False)
			assert ("duplicate username refused", not l_result.is_success and attached l_result.error as e2 and then e2.code.same_string ({CHAT_ERROR}.Code_exists))
			l_result := l_service.create_user ("nick", {STRING_32} "Nick", {STRING_32} "open sesame 42", False)
			assert ("second person fresh", l_result.is_success and l_service.store.user_count = 2)
		end

	test_ordinary_member_created_by_the_host
			-- What `--create-user' does: the host mints an ordinary member,
			-- who joins the default room and can log in, and who is NOT an
			-- administrator. There is no self-registration anywhere.
			--
			-- The ordering rule `--create-user' enforces is `store.has_admin':
			-- CHAT_SERVICE.create_user itself has no such guard (it is the
			-- shared body `create_first_admin' calls), so the flag has to ask
			-- before it calls. Both states of that discriminator are pinned
			-- here.
		local
			l_service: CHAT_SERVICE
			l_result: CHAT_RESULT [CHAT_USER]
			l_login: CHAT_RESULT [CHAT_SESSION]
		do
			l_service := service

				-- On a fresh store there is no admin: this is the state in
				-- which `--create-user' refuses and sends the host to
				-- `--create-admin' instead.
			assert ("no admin on a fresh store", not l_service.store.has_admin)

			l_result := l_service.create_first_admin ("larry", {STRING_32} "Larry", {STRING_32} "open sesame 42")
			assert ("admin created", l_result.is_success)
			assert ("now there is an admin", l_service.store.has_admin)

				-- The ordinary member. A display name that is not the username,
				-- and one the console must carry as UTF-8.
			l_result := l_service.create_user ("nick", {STRING_32} "Nick", {STRING_32} "open sesame 42", False)
			assert ("member created", l_result.is_success)
			assert ("member is not an admin", attached l_result.value as u and then not u.is_admin)
			assert ("member is stored", attached l_result.value as u2 and then u2.is_stored)
			assert ("member joined the default room", attached l_result.value as u3 and then l_service.store.is_member (u3.id, l_service.store.default_room_id))
			assert ("the display name is kept as given", attached l_result.value as u4 and then u4.display_name.same_string ({STRING_32} "Nick"))
			assert ("two people now", l_service.store.user_count = 2)

				-- A non-ASCII display name survives the whole way through the
				-- store: this is what reading the console as UTF-8 is for.
				-- "משה" as code points (U+05DE U+05E9 U+05D4) - never as
				-- literal glyphs, which this compiler would read as their raw
				-- UTF-8 bytes.
			l_result := l_service.create_user ("moshe", {STRING_32} "%/1502/%/1513/%/1492/", {STRING_32} "open sesame 42", False)
			assert ("Hebrew display name accepted", l_result.is_success)
			assert ("Hebrew display name round-trips", attached l_result.value as u5 and then u5.display_name.same_string ({STRING_32} "%/1502/%/1513/%/1492/"))

				-- Minting an account is only useful if it can be used.
			l_login := l_service.authenticate ("nick", {STRING_32} "open sesame 42", "127.0.0.1")
			assert ("the member can log in", l_login.is_success)

				-- Creating one twice is refused, and creating a member never
				-- makes a second administrator.
			l_result := l_service.create_user ("nick", {STRING_32} "Nick Again", {STRING_32} "open sesame 42", False)
			assert ("duplicate member refused", not l_result.is_success and attached l_result.error as e and then e.code.same_string ({CHAT_ERROR}.Code_exists))
			l_result := l_service.create_first_admin ("mallory", {STRING_32} "Mallory", {STRING_32} "open sesame 42")
			assert ("still only one admin may be minted", not l_result.is_success)
		end

	test_reset_password_revokes_sessions
		local
			l_service: CHAT_SERVICE
			l_admin: CHAT_USER
			l_login: CHAT_RESULT [CHAT_SESSION]
			l_result: CHAT_RESULT [CHAT_USER]
		do
			l_service := service
			l_admin := admin_of (l_service)
			l_login := l_service.authenticate ("larry", {STRING_32} "open sesame 42", "127.0.0.1")
			assert ("logged in", l_login.is_success and l_service.store.has_session_of (l_admin.id))
			l_result := l_service.reset_password (l_admin, {STRING_32} "brand new pass 7")
			assert ("reset succeeds and revokes", l_result.is_success and not l_service.store.has_session_of (l_admin.id))
			l_login := l_service.authenticate ("larry", {STRING_32} "open sesame 42", "127.0.0.1")
			assert ("old password dead", not l_login.is_success)
			l_login := l_service.authenticate ("larry", {STRING_32} "brand new pass 7", "127.0.0.1")
			assert ("new password lives", l_login.is_success)
		end

	test_password_reset_by_the_host
			-- What `--reset-password' does. The host is at a console holding
			-- NO session and no token: the member is found BY USERNAME in the
			-- store, and given a new password through
			-- CHAT_SERVICE.reset_password. This is the way back into a room
			-- whose only administrator forgot theirs; before the flag existed
			-- the remedy was to delete the database and lose the room.
			--
			-- Both gates the flag puts in front of `reset_password's
			-- preconditions are pinned in the state that matters: an unknown
			-- username finds nobody to reset, and a bot is not a person with
			-- a password.
		local
			l_service: CHAT_SERVICE
			l_admin: CHAT_USER
			l_app: SERVER_APP
			l_created, l_result: CHAT_RESULT [CHAT_USER]
			l_bot: CHAT_RESULT [TUPLE [bot: CHAT_USER; token: STRING_8]]
			l_login: CHAT_RESULT [CHAT_SESSION]
		do
			l_service := service
			l_admin := admin_of (l_service)
			assert ("the admin is there to be locked out", l_admin.is_stored)
			create l_app.make_idle

			l_created := l_service.create_user ("nick", {STRING_32} "Nick", {STRING_32} "open sesame 42", False)
			assert ("member minted", l_created.is_success)

				-- A username this room does not know: the lookup the flag
				-- makes finds nothing, so there is nothing to reset and the
				-- command must refuse rather than call.
			assert ("an unknown username finds nobody", l_service.store.user_by_username ("mallory") = Void)
			assert ("the room is unchanged by the miss", l_service.store.user_count = 2)

				-- A bot has no password, only a token. The flag's own gate
				-- says so before `reset_password' could trip `person'.
			l_bot := l_service.create_bot ("helper", {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " Helper")
			assert ("bot minted", l_bot.is_success)
			if attached l_service.store.user_by_username ("helper") as b then
				assert ("a bot is refused a password reset", not l_app.is_resettable_member (b))
			else
				assert ("the bot is in the store", False)
			end

				-- The member is logged in when the host resets: the session
				-- must not survive it, or a leaked password would still be
				-- worth something to whoever holds the token.
			l_login := l_service.authenticate ("nick", {STRING_32} "open sesame 42", "127.0.0.1")
			assert ("logged in first", l_login.is_success)
			if attached l_service.store.user_by_username ("nick") as u then
				assert ("a stored person may be reset", l_app.is_resettable_member (u))
				assert ("that member holds a session", l_service.store.has_session_of (u.id))
				l_result := l_service.reset_password (u, {STRING_32} "quite another pass")
				assert ("the reset succeeds", l_result.is_success)
				assert ("every live session was signed out", not l_service.store.has_session_of (u.id))
			else
				assert ("the member is in the store", False)
			end

			l_login := l_service.authenticate ("nick", {STRING_32} "open sesame 42", "127.0.0.1")
			assert ("the old password is dead", not l_login.is_success)
			l_login := l_service.authenticate ("nick", {STRING_32} "quite another pass", "127.0.0.1")
			assert ("the new password lives", l_login.is_success)

				-- The reset reaches one account and no other: the admin's own
				-- password still works and nobody was added or removed.
			l_login := l_service.authenticate ("larry", {STRING_32} "open sesame 42", "127.0.0.1")
			assert ("the admin is untouched", l_login.is_success)
			assert ("the population is unchanged", l_service.store.user_count = 3)
		end

	test_change_password_needs_the_old_one
		local
			l_service: CHAT_SERVICE
			l_admin: CHAT_USER
			l_result: CHAT_RESULT [CHAT_USER]
			l_login: CHAT_RESULT [CHAT_SESSION]
		do
			l_service := service
			l_admin := admin_of (l_service)
			l_result := l_service.change_password (l_admin, {STRING_32} "not the old one", {STRING_32} "wanted new pass")
			assert ("wrong old refused", not l_result.is_success and attached l_result.error as e and then e.code.same_string ({CHAT_ERROR}.Code_bad_credentials))
			l_login := l_service.authenticate ("larry", {STRING_32} "open sesame 42", "127.0.0.1")
			assert ("old still works after the refusal", l_login.is_success)
			l_result := l_service.change_password (l_admin, {STRING_32} "open sesame 42", {STRING_32} "wanted new pass")
			assert ("right old accepted", l_result.is_success)
			l_login := l_service.authenticate ("larry", {STRING_32} "wanted new pass", "127.0.0.1")
			assert ("new password lives", l_login.is_success)
		end

feature -- Authentication

	test_login_lockout_and_recovery
		local
			l_service: CHAT_SERVICE
			l_admin: CHAT_USER
			l_login: CHAT_RESULT [CHAT_SESSION]
			i, l_limit: INTEGER
		do
			l_service := service
			l_admin := admin_of (l_service)
			l_limit := l_service.config.login_failures_per_10_minutes
			from i := 1 until i > l_limit loop
				l_login := l_service.authenticate ("larry", {STRING_32} "not the password", "10.0.0.9")
				assert ("wrong password refused", not l_login.is_success and attached l_login.error as e and then e.code.same_string ({CHAT_ERROR}.Code_bad_credentials))
				i := i + 1
			end
			assert ("failures counted per user and address", l_service.limits.total (l_service.login_user_key ("larry")) = l_limit
				and l_service.limits.total (l_service.login_ip_key ("10.0.0.9")) = l_limit)
			assert ("locked now", not l_service.limits.is_allowed (l_service.login_user_key ("larry")))
			l_login := l_service.authenticate ("larry", {STRING_32} "open sesame 42", "10.0.0.9")
			assert ("right password still locked out", not l_login.is_success and attached l_login.error as e2 and then e2.code.same_string ({CHAT_ERROR}.Code_locked_out))
			assert ("lockout itself uncounted", l_service.limits.total (l_service.login_user_key ("larry")) = l_limit)
			l_service.limits.advance (601)
			l_login := l_service.authenticate ("larry", {STRING_32} "open sesame 42", "10.0.0.9")
			assert ("window passed, login works", l_login.is_success and attached l_login.value as l_session and then l_session.user_id = l_admin.id)
		end

	test_unknown_names_never_fill_the_user_limiter
		local
			l_service: CHAT_SERVICE
			l_login: CHAT_RESULT [CHAT_SESSION]
		do
			l_service := service
			l_login := l_service.authenticate ("ghost_rider", {STRING_32} "whatever pass", "10.0.0.7")
			assert ("unknown name refused", not l_login.is_success)
			assert ("no user-key entry", l_service.limits.count (l_service.login_user_key ("ghost_rider")) = 0
				and l_service.limits.total (l_service.login_user_key ("ghost_rider")) = 0)
			assert ("address counted", l_service.limits.total (l_service.login_ip_key ("10.0.0.7")) = 1)
			l_login := l_service.authenticate ({STRING_32} "Not A Valid Name!", {STRING_32} "whatever pass", "10.0.0.7")
			assert ("implausible refused", not l_login.is_success)
			assert ("address counted again", l_service.limits.total (l_service.login_ip_key ("10.0.0.7")) = 2)
		end

	test_session_round_trip
		local
			l_service: CHAT_SERVICE
			l_admin: CHAT_USER
			l_login: CHAT_RESULT [CHAT_SESSION]
			l_token: STRING_8
		do
			l_service := service
			l_admin := admin_of (l_service)
			l_login := l_service.authenticate ("larry", {STRING_32} "open sesame 42", "127.0.0.1")
			assert ("login succeeds", l_login.is_success)
			l_token := l_service.last_issued_token
			assert ("clear token issued, 64 characters", l_token.count = 64)
			assert ("only the hash is stored", attached l_login.value as l_session and then
				(l_session.token_hash.same_string (l_service.token_hash_of (l_token)) and not l_session.token_hash.same_string (l_token)))
			assert ("token finds its live session", attached l_service.session_for_token (l_token) as l_found and then l_found.user_id = l_admin.id)
			if attached l_login.value as l_session2 then
				l_service.revoke (l_session2)
			end
			assert ("revoked token finds nothing", l_service.session_for_token (l_token) = Void)
		end

	test_bot_token_round_trip_and_bot_login_refused
		local
			l_service: CHAT_SERVICE
			l_bot_result: CHAT_RESULT [TUPLE [bot: CHAT_USER; token: STRING_8]]
			l_login: CHAT_RESULT [CHAT_SESSION]
		do
			l_service := service
			l_bot_result := l_service.create_bot ("robot", {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " Robot")
			assert ("bot exists", l_bot_result.is_success)
			if attached l_bot_result.value as t then
				assert ("bot token finds a bot session", attached l_service.session_for_token (t.token) as l_session and then
					(l_session.is_bot_token and l_session.user_id = t.bot.id))
				l_login := l_service.authenticate ("robot", {STRING_32} "any password here", "127.0.0.1")
				assert ("bots cannot password-login", not l_login.is_success)
				assert ("the refusal is counted for the known name", l_service.limits.total (l_service.login_user_key ("robot")) = 1)
				l_service.revoke_bot_token (t.bot)
				assert ("revoked bot token gone", l_service.session_for_token (t.token) = Void and not l_service.store.has_session_of (t.bot.id))
			end
		end

feature -- Posting

	test_bot_marker_is_the_bots_alone
		local
			l_service: CHAT_SERVICE
			l_admin: CHAT_USER
			l_room: CHAT_ROOM
			l_bot_result: CHAT_RESULT [TUPLE [bot: CHAT_USER; token: STRING_8]]
			l_result: CHAT_RESULT [CHAT_EVENT]
		do
			l_service := service
			l_admin := admin_of (l_service)
			l_room := main_room (l_service)
			l_bot_result := l_service.create_bot ("robot", {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " Robot")
			assert ("bot created with a 64-character token", l_bot_result.is_success and attached l_bot_result.value as t and then (t.bot.is_bot and t.token.count = 64))
			if attached l_bot_result.value as t2 then
				l_result := l_service.post_message (t2.bot, l_room, {STRING_32} "beep")
				assert ("marker prepended once", l_result.is_success and attached l_result.value as e and then
					(e.body.starts_with ({CHAT_EVENT_KINDS}.Bot_marker) and e.body.ends_with ({STRING_32} " beep") and e.is_bot_authored))
				l_result := l_service.post_message (t2.bot, l_room, {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " already marked")
				assert ("marked body kept as is", l_result.is_success and attached l_result.value as e2 and then
					e2.body.same_string ({CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " already marked"))
			end
			l_result := l_service.post_message (l_admin, l_room, {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " pretending")
			assert ("person with the marker refused", not l_result.is_success and attached l_result.error as e3 and then e3.code.same_string ({CHAT_ERROR}.Code_refused))
			l_result := l_service.post_message (l_admin, l_room, {STRING_32} "an honest hello")
			assert ("person's body kept exactly", l_result.is_success and attached l_result.value as e4 and then
				(e4.body.same_string ({STRING_32} "an honest hello") and not e4.is_bot_authored))
		end

	test_post_rate_limit_hits_and_recovers
		local
			l_service: CHAT_SERVICE
			l_admin: CHAT_USER
			l_room: CHAT_ROOM
			l_result: CHAT_RESULT [CHAT_EVENT]
			i: INTEGER
		do
			l_service := service
			l_admin := admin_of (l_service)
			l_room := main_room (l_service)
			from i := 1 until i > l_service.config.posts_per_minute loop
				l_result := l_service.post_message (l_admin, l_room, "m" + i.out)
				assert ("post accepted", l_result.is_success)
				i := i + 1
			end
			l_result := l_service.post_message (l_admin, l_room, {STRING_32} "one too many")
			assert ("limit reached", not l_result.is_success and attached l_result.error as e and then e.code.same_string ({CHAT_ERROR}.Code_rate_limited))
			assert ("nothing appended", l_service.store.last_event_id = l_service.config.posts_per_minute.to_integer_64)
			l_service.limits.advance (61)
			l_result := l_service.post_message (l_admin, l_room, {STRING_32} "after the window")
			assert ("window passed, posting works", l_result.is_success and l_service.store.last_event_id = l_service.config.posts_per_minute.to_integer_64 + 1)
		end

	test_image_system_and_status_posts
		local
			l_service: CHAT_SERVICE
			l_admin: CHAT_USER
			l_room: CHAT_ROOM
			l_upload: CHAT_RESULT [CHAT_ATTACHMENT]
			l_result: CHAT_RESULT [CHAT_EVENT]
			l_before: INTEGER_64
		do
			l_service := service
			l_admin := admin_of (l_service)
			l_room := main_room (l_service)
			l_upload := l_service.store_upload (l_admin, {STRING_32} "pic.png", png_bytes (16))
			assert ("upload ok", l_upload.is_success)
			if attached l_upload.value as a then
				l_result := l_service.post_image (l_admin, l_room, a, {STRING_32} "sunset over the lake")
				assert ("image event carries caption and attachment", l_result.is_success and attached l_result.value as e and then
					(e.is_image and e.body.same_string ({STRING_32} "sunset over the lake") and attached e.attachment as ea and then ea.id = a.id))
			end
			l_result := l_service.post_system (l_room, {STRING_32} "the server greets the room")
			assert ("system event from sender zero", l_result.is_success and attached l_result.value as e2 and then (e2.is_system and e2.sender_id = 0))
			l_before := l_service.store.last_event_id
			l_service.publish_status (l_room, l_admin, {STRING_32} "thinking...")
			assert ("status rung, nothing stored", l_service.bus.status_count = 1 and l_service.store.last_event_id = l_before)
		end

feature -- Reading

	test_events_since_pages_gapless
		local
			l_service: CHAT_SERVICE
			l_admin: CHAT_USER
			l_room: CHAT_ROOM
			l_result: CHAT_RESULT [CHAT_EVENT]
			l_page: ARRAYED_LIST [CHAT_EVENT]
			l_seen, l_cursor: INTEGER_64
			i: INTEGER
		do
			l_service := service
			l_admin := admin_of (l_service)
			l_room := main_room (l_service)
			from i := 1 until i > 5 loop
				l_result := l_service.post_message (l_admin, l_room, "page me " + i.out)
				assert ("posted", l_result.is_success)
				i := i + 1
			end
			from
				l_cursor := 0
			until
				l_service.events_since (l_room, l_cursor, 2).is_empty
			loop
				l_page := l_service.events_since (l_room, l_cursor, 2)
				assert ("page bounded", l_page.count <= 2)
				across l_page as e loop
					assert ("gapless ascent", e.id = l_seen + 1)
					l_seen := e.id
				end
				l_cursor := l_page.last.id
			end
			assert ("all five paged", l_seen = 5)
			l_page := l_service.events_before (l_room, 4, 2)
			assert ("history page is 2 and 3, ascending", l_page.count = 2 and l_page [1].id = 2 and l_page [2].id = 3)
		end

feature -- Uploads

	test_upload_signature_size_and_pinning
		local
			l_service: CHAT_SERVICE
			l_admin: CHAT_USER
			l_result: CHAT_RESULT [CHAT_ATTACHMENT]
			l_bytes: SPECIAL [NATURAL_8]
			l_rules: CHAT_ATTACHMENT_RULES
		do
			l_service := service
			l_admin := admin_of (l_service)
			create l_rules
			l_bytes := png_bytes (64)
			l_result := l_service.store_upload (l_admin, {STRING_32} "photo.png", l_bytes)
			assert ("png accepted", l_result.is_success and attached l_result.value as a and then
				(a.mime.same_string ({CHAT_ATTACHMENT}.Mime_png) and a.size = 64 and l_service.store.has_attachment (a.id)))
			assert ("hash and path pinned", attached l_result.value as a2 and then
				(a2.sha256.same_string (l_service.sha256_hex_of (l_bytes)) and a2.stored_relpath.same_string (l_rules.stored_path_for (a2.sha256, a2.mime))))
			l_result := l_service.store_upload (l_admin, {STRING_32} "photo.jpg", jpeg_bytes (32))
			assert ("jpeg detected", l_result.is_success and attached l_result.value as a3 and then
				(a3.mime.same_string ({CHAT_ATTACHMENT}.Mime_jpeg) and a3.stored_relpath.ends_with (".jpg")))
			create l_bytes.make_filled ({NATURAL_8} 65, 16)
			l_result := l_service.store_upload (l_admin, {STRING_32} "notes.txt", l_bytes)
			assert ("junk refused", not l_result.is_success and attached l_result.error as e and then e.code.same_string ({CHAT_ERROR}.Code_bad_type))
			l_result := l_service.store_upload (l_admin, {STRING_32} "big.png", png_bytes ((l_service.config.upload_bytes + 1).to_integer_32))
			assert ("oversize refused", not l_result.is_success and attached l_result.error as e2 and then e2.code.same_string ({CHAT_ERROR}.Code_too_large))
			assert ("only the two stored", l_service.store.attachment_count = 2)
		end

feature -- Backup (Phase 4 Task 9b)

	test_backup_writes_a_copy_that_opens_as_a_database
			-- Over a REAL SQLite store in a scratch data_dir: `backup' answers a path
			-- under <data_dir>/backups/, the file is there, and re-opening it with a
			-- second store reads back the event that was posted before the copy.
		local
			l_store, l_copy: SQLITE_CHAT_STORE
			l_service: CHAT_SERVICE
			l_admin: CHAT_USER
			l_room: CHAT_ROOM
			l_posted: CHAT_RESULT [CHAT_EVENT]
			l_result: CHAT_RESULT [STRING_32]
			l_path: STRING_32
			l_events: ARRAYED_LIST [CHAT_EVENT]
		do
			prepare_backup_scratch
			create l_store.make (Backup_database_path)
			l_store.open
			assert ("the scratch store opened - " + store_error_text (l_store), l_store.is_open)
			l_store.add_room (create {CHAT_ROOM}.make (0, {STRING_32} "main", time_now))
			l_service := scratch_service (l_store)
			l_admin := admin_of (l_service)
			l_room := main_room (l_service)
			l_posted := l_service.post_message (l_admin, l_room, {STRING_32} "before the backup")
			assert ("something to find in the copy", l_posted.is_success)

			l_result := l_service.backup
			assert ("the backup succeeded - " + result_error_text (l_result), l_result.is_success)
			check attached l_result.value as p then
				l_path := p
			end
			assert ("a path came back", not l_path.is_empty)
			assert ("the copy is under data/backups/", l_path.as_lower.has_substring ({STRING_32} "backups"))
			assert ("the copy is there", file_is_at (l_path))
			assert ("the original is untouched", file_is_at (Backup_database_path))

			l_store.close
			create l_copy.make (l_path)
			l_copy.open
			assert ("the copy opens as a database at the current schema - " + store_error_text (l_copy),
				l_copy.is_open and l_copy.schema_version = {CHAT_SCHEMA}.Current_version)
			l_events := l_copy.events_since (l_room.id, 0, 100)
			assert ("the posted event is in the copy", across l_events as e some
				e.body.same_string_general ({STRING_32} "before the backup") end)
			assert ("the admin is in the copy", l_copy.user_count = 1 and l_copy.has_admin)
			l_copy.close
			wipe_backup_scratch
		end

	test_two_backups_in_the_same_second_are_two_files
			-- The name is proved free before the store is asked to write, so a second
			-- backup within the same second does not silently overwrite the first.
		local
			l_store: SQLITE_CHAT_STORE
			l_service: CHAT_SERVICE
			l_first, l_second: CHAT_RESULT [STRING_32]
			l_a, l_b: STRING_32
		do
			prepare_backup_scratch
			create l_store.make (Backup_database_path)
			l_store.open
			assert ("the scratch store opened - " + store_error_text (l_store), l_store.is_open)
			l_store.add_room (create {CHAT_ROOM}.make (0, {STRING_32} "main", time_now))
			l_service := scratch_service (l_store)
			l_first := l_service.backup
			l_second := l_service.backup
			assert ("the first backup succeeded - " + result_error_text (l_first), l_first.is_success)
			assert ("the second backup succeeded - " + result_error_text (l_second), l_second.is_success)
			check attached l_first.value as a and attached l_second.value as b then
				l_a := a
				l_b := b
			end
			assert ("two distinct paths", not l_a.same_string (l_b))
			assert ("two files on disk", file_is_at (l_a) and file_is_at (l_b))
			l_store.close
			wipe_backup_scratch
		end

	test_backup_over_the_memory_store_is_an_error_never_a_raise
			-- The oracle has nothing on disk. `backup_to' answers False and writes
			-- nothing; the service turns that into a 503 result and comes back.
		local
			l_store: MEMORY_CHAT_STORE
			l_service: CHAT_SERVICE
			l_result: CHAT_RESULT [STRING_32]
		do
			prepare_backup_scratch
			create l_store.make
			l_store.open
			l_store.add_room (create {CHAT_ROOM}.make (0, {STRING_32} "main", time_now))
			l_service := scratch_service (l_store)
			l_result := l_service.backup
			assert ("refused, not raised", not l_result.is_success)
			assert ("as unavailable", attached l_result.error as e and then
				(e.http_status = 503 and e.code.same_string ({CHAT_ERROR}.Code_unavailable)))
			assert ("no backup file was left behind", backup_file_count = 0)
			wipe_backup_scratch
		end

feature {NONE} -- Fixtures

	service: CHAT_SERVICE
			-- A fresh service over an open memory store with one room "main",
			-- default configuration, a 3600-second limiter and a redacting log.
		local
			l_config: SERVER_CONFIG
			l_store: MEMORY_CHAT_STORE
			l_bus: EVENT_BUS
			l_limits: RATE_LIMITER
			l_log: CHAT_LOG
			l_logger: SIMPLE_LOGGER
			l_now: SIMPLE_DATE_TIME
		do
			create l_config.make_defaults
			create l_store.make
			l_store.open
			create l_now.make_now
			l_store.add_room (create {CHAT_ROOM}.make (0, {STRING_32} "main", l_now))
			create l_bus.make
			create l_limits.make (3600)
			create l_logger
			create l_log.make (l_logger)
			create Result.make (l_store, l_bus, l_limits, l_config, l_log)
		end

	admin_of (a_service: CHAT_SERVICE): CHAT_USER
			-- The first admin "larry" (password "open sesame 42"), created through the service.
		do
			if attached a_service.create_first_admin ("larry", {STRING_32} "Larry", {STRING_32} "open sesame 42").value as l_user then
				Result := l_user
			else
				check first_admin_created: False then end
			end
		end

	main_room (a_service: CHAT_SERVICE): CHAT_ROOM
		do
			if attached a_service.store.default_room as l_room then
				Result := l_room
			else
				check default_room_exists: False then end
			end
		end

	png_bytes (a_count: INTEGER): SPECIAL [NATURAL_8]
			-- `a_count' zero bytes beginning with the eight-byte PNG signature.
		require
			room_for_signature: a_count >= 8
		do
			create Result.make_filled ({NATURAL_8} 0, a_count)
			Result [0] := {NATURAL_8} 0x89
			Result [1] := {NATURAL_8} 0x50
			Result [2] := {NATURAL_8} 0x4E
			Result [3] := {NATURAL_8} 0x47
			Result [4] := {NATURAL_8} 0x0D
			Result [5] := {NATURAL_8} 0x0A
			Result [6] := {NATURAL_8} 0x1A
			Result [7] := {NATURAL_8} 0x0A
		end

	jpeg_bytes (a_count: INTEGER): SPECIAL [NATURAL_8]
			-- `a_count' zero bytes beginning with the JPEG signature FF D8 FF.
		require
			room_for_signature: a_count >= 3
		do
			create Result.make_filled ({NATURAL_8} 0, a_count)
			Result [0] := {NATURAL_8} 0xFF
			Result [1] := {NATURAL_8} 0xD8
			Result [2] := {NATURAL_8} 0xFF
		end

feature {NONE} -- Backup fixtures (Phase 4 Task 9b)

	scratch_service (a_store: CHAT_STORE): CHAT_SERVICE
			-- A service over `a_store' whose configuration's `data_dir' is the
			-- scratch directory, so `backup' writes under it and nowhere near
			-- the project's own data/.
		require
			open: a_store.is_open
		local
			l_config: SERVER_CONFIG
			l_bus: EVENT_BUS
			l_limits: RATE_LIMITER
			l_log: CHAT_LOG
			l_logger: SIMPLE_LOGGER
		do
			create l_config.make_from_file (write_backup_toml)
			check config_valid: l_config.is_valid and l_config.data_dir.same_string (Backup_scratch_directory.to_string_32) end
			create l_bus.make
			create l_limits.make (3600)
			create l_logger
			create l_log.make (l_logger)
			create Result.make (a_store, l_bus, l_limits, l_config, l_log)
		ensure
			over_the_store: Result.store = a_store
		end

	write_backup_toml: STRING_32
			-- <scratch>/server.toml naming the scratch directory as `data_dir'
			-- (forward slashes: a TOML basic string treats backslash as an escape).
		local
			l_file: PLAIN_TEXT_FILE
		do
			Result := Backup_scratch_directory.to_string_32 + {STRING_32} "/server.toml"
			create l_file.make_create_read_write (Result)
			l_file.put_string ("port = 8080%Ndata_dir = %"" + Backup_scratch_directory + "%"%N")
			l_file.close
		end

	prepare_backup_scratch
			-- A clean testing/backup_scratch, whatever a dead run left there.
		local
			l_directory: DIRECTORY
		do
			wipe_backup_scratch
			create l_directory.make (Backup_scratch_directory)
			if not l_directory.exists then
				l_directory.recursive_create_dir
			end
		ensure
			there: (create {DIRECTORY}.make (Backup_scratch_directory)).exists
		end

	wipe_backup_scratch
			-- Remove the scratch directory and everything under it.
		local
			l_directory: DIRECTORY
			l_failed: BOOLEAN
		do
			if not l_failed then
				create l_directory.make (Backup_scratch_directory)
				if l_directory.exists then
					l_directory.recursive_delete
				end
			end
		rescue
			l_failed := True
			retry
		end

	backup_file_count: INTEGER
			-- How many real entries the scratch backups directory holds (0 when it
			-- is not even there): what `backup' left behind, "." and ".." aside.
		local
			l_directory: DIRECTORY
		do
			create l_directory.make (Backup_scratch_directory + "/backups")
			if l_directory.exists then
				across l_directory.entries as e loop
					if not e.name.same_string ({STRING_32} ".") and not e.name.same_string ({STRING_32} "..") then
						Result := Result + 1
					end
				end
			end
		ensure
			non_negative: Result >= 0
		end

	file_is_at (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Is there a file at `a_path'?
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			Result := l_file.exists
		end

	store_error_text (a_store: SQLITE_CHAT_STORE): STRING_8
			-- Why the store did not open, for a failing assertion's tag.
		do
			if attached a_store.last_open_error as l_error then
				Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (l_error.message)
			else
				Result := "no error recorded"
			end
		end

	result_error_text (a_result: CHAT_RESULT [STRING_32]): STRING_8
			-- Why a backup result failed, for a failing assertion's tag.
		do
			if attached a_result.error as l_error then
				Result := l_error.http_status.out + " " + l_error.code + ": "
					+ {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (l_error.message)
			else
				Result := "no error recorded"
			end
		end

	time_now: SIMPLE_DATE_TIME
		do
			create Result.make_now
		end

	Backup_scratch_directory: STRING_8 = "testing/backup_scratch"

	Backup_database_path: STRING_32 = "testing/backup_scratch/simple_chat.db"
			-- The store file inside the scratch data_dir. `backup' never reads it:
			-- it asks the store to write the copy, so only the store and this test
			-- need to know the name.

end
