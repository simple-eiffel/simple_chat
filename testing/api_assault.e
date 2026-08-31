note
	description: "[
		CHAT_API under assault over a fresh in-memory service (Phase 4
		Task 2): the login reply is the only place a person's token
		travels and the bot-creation reply the only place a bot's does -
		other bodies are swept for a 64-hex token shape; the guards
		(401/403), the service's refusals mapped onto statuses (400,
		409, 415, 429, and the honest 404/501 attachment and backup
		answers), paging with merged statuses, and the admin surface.
	]"
	author: "Larry Rix"

class
	API_ASSAULT

inherit
	TEST_SET_BASE

feature -- Authentication through the API

	test_api_login_carries_token_once
		local
			l_api: CHAT_API
			l_reply: CHAT_REPLY
			l_codec: CHAT_JSON
		do
			l_api := fresh_api
			make_admin (l_api)
			create l_codec.make
			l_reply := l_api.health
			assert ("health open", l_reply.status = 200)
			assert_no_token_shape ("health carries no token", l_reply)
			l_reply := l_api.login ({STRING_32} "larry", {STRING_32} "open sesame 42", "127.0.0.1")
			assert ("login ok", l_reply.status = 200)
			assert ("token and member decodable", attached l_codec.login_from_bytes (l_reply.body) as l_login and then
				(l_login.token.count = 64 and l_login.member.username.same_string ("larry") and not l_login.member.is_bot))
			if attached l_codec.login_from_bytes (l_reply.body) as l_login2 then
				assert ("token appears exactly once", occurrences_of (l_login2.token, l_reply.body) = 1)
				assert ("token is live", attached l_api.service.session_for_token (l_login2.token))
				l_reply := l_api.me (l_login2.token)
				assert ("me answers the member", l_reply.status = 200 and l_reply.body.has_substring ("larry"))
				assert ("me never repeats the token", not l_reply.body.has_substring (l_login2.token))
				assert_no_token_shape ("me carries no token shape", l_reply)
			end
		end

	test_api_login_failure_and_lockout
		local
			l_api: CHAT_API
			l_reply: CHAT_REPLY
			i, l_limit: INTEGER
		do
			l_api := fresh_api
			make_admin (l_api)
			l_limit := l_api.config.login_failures_per_10_minutes
			from
				i := 1
			until
				i > l_limit
			loop
				l_reply := l_api.login ({STRING_32} "larry", {STRING_32} "not the password", "10.0.0.9")
				assert ("wrong password 401", l_reply.status = 401)
				assert_no_token_shape ("failure carries no token", l_reply)
				i := i + 1
			end
			l_reply := l_api.login ({STRING_32} "larry", {STRING_32} "open sesame 42", "10.0.0.9")
			assert ("locked out 429", l_reply.status = 429)
			assert_no_token_shape ("lockout carries no token", l_reply)
			l_reply := l_api.login ({STRING_32} "", {STRING_32} "x", "10.0.0.9")
			assert ("empty username 400", l_reply.status = 400)
		end

	test_api_bot_login_refused_and_bot_token_posts
		local
			l_api: CHAT_API
			l_reply: CHAT_REPLY
			l_codec: CHAT_JSON
			l_bot: CHAT_RESULT [TUPLE [bot: CHAT_USER; token: STRING_8]]
		do
			l_api := fresh_api
			make_admin (l_api)
			create l_codec.make
			l_bot := l_api.service.create_bot ("robot", {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " Robot")
			assert ("bot exists", l_bot.is_success)
			l_reply := l_api.login ({STRING_32} "robot", {STRING_32} "any password here", "127.0.0.1")
			assert ("bots cannot password-login", l_reply.status = 401)
			assert_no_token_shape ("bot refusal carries no token", l_reply)
			if attached l_bot.value as t then
				l_reply := l_api.post_message (t.token, l_api.service.store.default_room_id, {STRING_32} "beep")
				assert ("bot token posts", l_reply.status = 201)
				assert ("marker prefixed for the bot", attached l_codec.event_from_bytes (l_reply.body) as e and then
					(e.is_bot_authored and e.body.starts_with ({CHAT_EVENT_KINDS}.Bot_marker)))
				assert ("the reply never echoes the bot token", not l_reply.body.has_substring (t.token))
			end
		end

feature -- Reading through the API

	test_api_me_rooms_members_guards
		local
			l_api: CHAT_API
			l_reply: CHAT_REPLY
			l_token: STRING_8
		do
			l_api := fresh_api
			make_admin (l_api)
			assert ("malformed token 401", l_api.me ("deadbeef").status = 401)
			assert ("unknown token 401", l_api.me (Sixty_four_hex).status = 401)
			assert ("rooms needs a session", l_api.rooms (Sixty_four_hex).status = 401)
			assert ("members needs a session", l_api.members (Sixty_four_hex, l_api.service.store.default_room_id).status = 401)
			l_token := login_token (l_api)
			l_reply := l_api.rooms (l_token)
			assert ("rooms lists main as a JSON array", l_reply.status = 200 and l_reply.body.has_substring ("main") and l_reply.body.starts_with ("["))
			assert_no_token_shape ("rooms carries no token", l_reply)
			l_reply := l_api.members (l_token, l_api.service.store.default_room_id)
			assert ("roster decodes with larry alone", l_reply.status = 200 and attached (create {CHAT_JSON}.make).members_from_bytes (l_reply.body) as l_members and then
				(l_members.count = 1 and l_members.first.username.same_string ("larry")))
			assert ("never a hash", not l_reply.body.has_substring ("password_hash"))
			assert_no_token_shape ("members carries no token", l_reply)
		end

	test_api_events_paging_and_merged_statuses
		local
			l_api: CHAT_API
			l_reply: CHAT_REPLY
			l_token: STRING_8
			l_room: INTEGER_64
			l_codec: CHAT_JSON
			i: INTEGER
		do
			l_api := fresh_api
			make_admin (l_api)
			create l_codec.make
			l_token := login_token (l_api)
			l_room := l_api.service.store.default_room_id
			assert ("main room is 1", l_room = 1)
			from
				i := 1
			until
				i > 3
			loop
				assert ("posted", l_api.post_message (l_token, l_room, ("page me " + i.out).to_string_32).status = 201)
				i := i + 1
			end
			l_reply := l_api.events (l_token, l_room, 0, 2, "[]")
			assert ("page bounded", l_reply.status = 200 and l_reply.item_count = 2)
			assert ("page decodes ascending", attached l_codec.page_from_bytes (l_reply.body) as p and then
				(p.events.count = 2 and p.events.first.id = 1 and p.events.last.id = 2 and p.statuses.is_empty))
			l_reply := l_api.events (l_token, l_room, 2, 10, "[{%"room_id%":1,%"from%":%"Larry%",%"text%":%"typing%"}]")
			assert ("statuses merged", l_reply.status = 200 and attached l_codec.page_from_bytes (l_reply.body) as p2 and then
				(p2.events.count = 1 and p2.events.first.id = 3 and p2.statuses.count = 1 and p2.statuses.first.text.same_string ({STRING_32} "typing")))
			l_reply := l_api.events_before (l_token, l_room, 3, 10)
			assert ("history ascending before 3", l_reply.status = 200 and attached l_codec.page_from_bytes (l_reply.body) as p3 and then
				(p3.events.count = 2 and p3.events.first.id = 1 and p3.events.last.id = 2))
			assert_no_token_shape ("pages carry no token", l_reply)
			l_api.service.store.add_room (create {CHAT_ROOM}.make (0, {STRING_32} "private", create {SIMPLE_DATE_TIME}.make_now))
			l_reply := l_api.events (l_token, 2, 0, 10, "[]")
			assert ("not a member 403", l_reply.status = 403)
		end

feature -- Posting through the API

	test_api_post_message_echo_and_rate_limit
		local
			l_api: CHAT_API
			l_reply: CHAT_REPLY
			l_token: STRING_8
			l_room, l_before: INTEGER_64
			i: INTEGER
		do
			l_api := fresh_api
			make_admin (l_api)
			l_token := login_token (l_api)
			l_room := l_api.service.store.default_room_id
			l_reply := l_api.post_message (l_token, l_room, {STRING_32} "an honest hello")
			assert ("echo 201", l_reply.status = 201 and l_reply.body.has_substring ("an honest hello"))
			assert_no_token_shape ("echo carries no token", l_reply)
			assert ("empty body 400", l_api.post_message (l_token, l_room, {STRING_32} "").status = 400)
			from
				i := 2
			until
				i > l_api.config.posts_per_minute
			loop
				assert ("accepted", l_api.post_message (l_token, l_room, {STRING_32} "filler").status = 201)
				i := i + 1
			end
			l_before := l_api.service.store.last_event_id
			l_reply := l_api.post_message (l_token, l_room, {STRING_32} "one too many")
			assert ("limit 429", l_reply.status = 429)
			assert ("nothing appended", l_api.service.store.last_event_id = l_before)
			assert ("unknown room 403", l_api.post_message (l_token, 999, {STRING_32} "into the void").status = 403)
		end

	test_api_post_image_upload_rules_and_attachment
		local
			l_api: CHAT_API
			l_reply: CHAT_REPLY
			l_token: STRING_8
			l_room, l_attachment_id: INTEGER_64
			l_codec: CHAT_JSON
		do
			l_api := fresh_api
			make_admin (l_api)
			create l_codec.make
			l_token := login_token (l_api)
			l_room := l_api.service.store.default_room_id
			l_reply := l_api.post_image (l_token, l_room, png_string (16), {STRING_32} "pic.png", {STRING_32} "sunset")
			assert ("image 201", l_reply.status = 201)
			assert ("image event with attachment", attached l_codec.event_from_bytes (l_reply.body) as e and then
				(e.is_image and e.body.same_string ({STRING_32} "sunset") and attached e.attachment as a and then a.id > 0))
			assert ("image reply never carries the token", not l_reply.body.has_substring (l_token))
			if attached l_codec.event_from_bytes (l_reply.body) as e2 and then attached e2.attachment as a2 then
				l_attachment_id := a2.id
			end
			assert ("stored metadata, bytes honestly 501", l_api.attachment (l_token, l_attachment_id).status = 501)
			assert ("unknown attachment 404", l_api.attachment (l_token, 9999).status = 404)
			assert ("attachment needs a session", l_api.attachment (Sixty_four_hex, l_attachment_id).status = 401)
			l_reply := l_api.post_image (l_token, l_room, "GIF89a not an image", {STRING_32} "pic.gif", {STRING_32} "")
			assert ("wrong signature 415", l_reply.status = 415)
			assert_no_token_shape ("refusal carries no token", l_reply)
			assert ("empty bytes 400", l_api.post_image (l_token, l_room, "", {STRING_32} "pic.png", {STRING_32} "x").status = 400)
		end

feature -- Account and administration through the API

	test_api_change_password_flow
		local
			l_api: CHAT_API
			l_reply: CHAT_REPLY
			l_token: STRING_8
		do
			l_api := fresh_api
			make_admin (l_api)
			l_token := login_token (l_api)
			assert ("wrong old refused", l_api.change_password (l_token, {STRING_32} "not the old one", {STRING_32} "wanted new pass").status = 401)
			assert ("short new refused", l_api.change_password (l_token, {STRING_32} "open sesame 42", {STRING_32} "no").status = 400)
			l_reply := l_api.change_password (l_token, {STRING_32} "open sesame 42", {STRING_32} "wanted new pass")
			assert ("changed 200", l_reply.status = 200)
			assert_no_token_shape ("change reply carries no token", l_reply)
			assert ("session survives a change", l_api.me (l_token).status = 200)
			assert ("new password lives", l_api.login ({STRING_32} "larry", {STRING_32} "wanted new pass", "127.0.0.1").status = 200)
		end

	test_api_admin_gate_and_create_user
		local
			l_api: CHAT_API
			l_reply: CHAT_REPLY
			l_token: STRING_8
			l_codec: CHAT_JSON
		do
			l_api := fresh_api
			make_admin (l_api)
			create l_codec.make
			assert ("admin needs a session", l_api.admin_users (Sixty_four_hex).status = 401)
			l_token := login_token (l_api)
			l_reply := l_api.admin_create_user (l_token, "nick", {STRING_32} "Nick", {STRING_32} "fresh pass nine 9", False)
			assert ("created 201", l_reply.status = 201 and l_reply.body.has_substring ("nick"))
			assert_no_token_shape ("created member carries no token", l_reply)
			assert ("duplicate 409", l_api.admin_create_user (l_token, "nick", {STRING_32} "Nick Two", {STRING_32} "fresh pass nine 9", False).status = 409)
			assert ("bad username 400", l_api.admin_create_user (l_token, "Not Valid!", {STRING_32} "Nick", {STRING_32} "fresh pass nine 9", False).status = 400)
			l_reply := l_api.admin_users (l_token)
			assert ("roster lists both, no hashes", l_reply.status = 200 and l_reply.body.has_substring ("larry")
				and l_reply.body.has_substring ("nick") and not l_reply.body.has_substring ("password_hash"))
			assert_no_token_shape ("roster carries no token", l_reply)
			if attached l_codec.login_from_bytes (l_api.login ({STRING_32} "nick", {STRING_32} "fresh pass nine 9", "127.0.0.1").body) as l_login then
				assert ("not an admin 403", l_api.admin_users (l_login.token).status = 403)
			else
				assert ("nick logs in", False)
			end
		end

	test_api_admin_reset_password_kills_sessions
		local
			l_api: CHAT_API
			l_reply: CHAT_REPLY
			l_admin_token, l_nick_token: STRING_8
			l_codec: CHAT_JSON
			l_nick_id: INTEGER_64
		do
			l_api := fresh_api
			make_admin (l_api)
			create l_codec.make
			l_admin_token := login_token (l_api)
			assert ("nick created", l_api.admin_create_user (l_admin_token, "nick", {STRING_32} "Nick", {STRING_32} "fresh pass nine 9", False).status = 201)
			if attached l_api.service.store.user_by_username ("nick") as u then
				l_nick_id := u.id
			end
			if attached l_codec.login_from_bytes (l_api.login ({STRING_32} "nick", {STRING_32} "fresh pass nine 9", "127.0.0.1").body) as l_login then
				l_nick_token := l_login.token
				assert ("nick's session lives", l_api.me (l_nick_token).status = 200)
				assert ("non-admin cannot reset", l_api.admin_reset_password (l_nick_token, l_nick_id, {STRING_32} "another pass here").status = 403)
				l_reply := l_api.admin_reset_password (l_admin_token, l_nick_id, {STRING_32} "another pass here")
				assert ("reset 200", l_reply.status = 200)
				assert_no_token_shape ("reset reply carries no token", l_reply)
				assert ("nick's old session is dead", l_api.me (l_nick_token).status = 401)
				assert ("new password lives", l_api.login ({STRING_32} "nick", {STRING_32} "another pass here", "127.0.0.1").status = 200)
				assert ("unknown person 404", l_api.admin_reset_password (l_admin_token, 9999, {STRING_32} "another pass here").status = 404)
			else
				assert ("nick logs in", False)
			end
		end

	test_api_admin_bot_token_once_and_revoke
		local
			l_api: CHAT_API
			l_reply: CHAT_REPLY
			l_admin_token, l_bot_token: STRING_8
			l_codec: CHAT_JSON
			l_bot_id: INTEGER_64
		do
			l_api := fresh_api
			make_admin (l_api)
			create l_codec.make
			l_admin_token := login_token (l_api)
			l_reply := l_api.admin_create_bot (l_admin_token, "robot", {STRING_32} "Robot")
			assert ("bot 201", l_reply.status = 201)
			assert ("bot token and marked member decodable", attached l_codec.login_from_bytes (l_reply.body) as l_login and then
				(l_login.token.count = 64 and l_login.member.is_bot and l_login.member.display_name.starts_with ({CHAT_EVENT_KINDS}.Bot_marker)))
			if attached l_codec.login_from_bytes (l_reply.body) as l_login2 then
				l_bot_token := l_login2.token
				l_bot_id := l_login2.member.id
				assert ("bot token appears exactly once", occurrences_of (l_bot_token, l_reply.body) = 1)
				assert ("bot token posts", l_api.post_message (l_bot_token, l_api.service.store.default_room_id, {STRING_32} "beep").status = 201)
				l_reply := l_api.admin_revoke_bot (l_admin_token, l_bot_id)
				assert ("revoked 200", l_reply.status = 200)
				assert_no_token_shape ("revoke reply carries no token", l_reply)
				assert ("revoked bot token is dead", l_api.post_message (l_bot_token, l_api.service.store.default_room_id, {STRING_32} "beep").status = 401)
				assert ("unknown bot 404", l_api.admin_revoke_bot (l_admin_token, 9999).status = 404)
				assert ("duplicate bot 409", l_api.admin_create_bot (l_admin_token, "robot", {STRING_32} "Robot").status = 409)
			end
		end

	test_api_participants_and_backup_answers
		local
			l_api: CHAT_API
			l_reply: CHAT_REPLY
			l_token: STRING_8
		do
			l_api := fresh_api
			make_admin (l_api)
			l_token := login_token (l_api)
			l_reply := l_api.participants (l_token)
			assert ("participants 200 with the list key", l_reply.status = 200 and l_reply.body.has_substring ("participants"))
			assert_no_token_shape ("participants carry no token", l_reply)
			l_reply := l_api.admin_backup (l_token)
			assert ("backup is honestly 501 until SQLite", l_reply.status = 501)
			assert_no_token_shape ("backup carries no token", l_reply)
		end

feature {NONE} -- Fixtures

	fresh_api: CHAT_API
			-- An API over a fresh service: an open memory store with one room
			-- "main", default configuration, a 3600-second limiter and a
			-- redacting log (SERVICE_ASSAULT's assembly).
		local
			l_config: SERVER_CONFIG
			l_store: MEMORY_CHAT_STORE
			l_bus: EVENT_BUS
			l_limits: RATE_LIMITER
			l_log: CHAT_LOG
			l_logger: SIMPLE_LOGGER
			l_now: SIMPLE_DATE_TIME
			l_service: CHAT_SERVICE
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
			create l_service.make (l_store, l_bus, l_limits, l_config, l_log)
			create Result.make (l_service, l_config)
		end

	make_admin (a_api: CHAT_API)
			-- The first admin "larry" (password "open sesame 42").
		do
			if not a_api.service.create_first_admin ("larry", {STRING_32} "Larry", {STRING_32} "open sesame 42").is_success then
				check first_admin_created: False then end
			end
		end

	login_token (a_api: CHAT_API): STRING_8
			-- Larry's clear token, read from the API's login answer alone.
		do
			create Result.make_empty
			if attached (create {CHAT_JSON}.make).login_from_bytes (a_api.login ({STRING_32} "larry", {STRING_32} "open sesame 42", "127.0.0.1").body) as l_login then
				Result := l_login.token
			else
				check login_reply_decodes: False then end
			end
		ensure
			shape: Result.count = 64
		end

	png_string (a_count: INTEGER): STRING_8
			-- `a_count' bytes beginning with the eight-byte PNG signature.
		require
			room_for_signature: a_count >= 8
		do
			create Result.make (a_count)
			Result.append_code (0x89)
			Result.append_code (0x50)
			Result.append_code (0x4E)
			Result.append_code (0x47)
			Result.append_code (0x0D)
			Result.append_code (0x0A)
			Result.append_code (0x1A)
			Result.append_code (0x0A)
			from
			until
				Result.count = a_count
			loop
				Result.append_code (0)
			end
		ensure
			sized: Result.count = a_count
		end

feature {NONE} -- The token sweep

	Sixty_four_hex: STRING_8 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
			-- Token-shaped, matching no session.

	assert_no_token_shape (a_tag: STRING; a_reply: CHAT_REPLY)
			-- Fail unless `a_reply''s body is free of any 64-hex run.
		do
			assert (a_tag, not has_token_shape (a_reply.body))
		end

	has_token_shape (a_body: STRING_8): BOOLEAN
			-- A run of 64 or more hexadecimal characters anywhere in `a_body'?
		local
			i, l_run: INTEGER
			c: CHARACTER_8
		do
			from
				i := 1
			until
				i > a_body.count or Result
			loop
				c := a_body [i]
				if (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') then
					l_run := l_run + 1
					Result := l_run >= 64
				else
					l_run := 0
				end
				i := i + 1
			end
		end

	occurrences_of (a_needle, a_hay: STRING_8): INTEGER
			-- How many times `a_needle' occurs in `a_hay' (non-overlapping).
		require
			needle_given: not a_needle.is_empty
		local
			i: INTEGER
		do
			from
				i := 1
			until
				i = 0 or i > a_hay.count - a_needle.count + 1
			loop
				i := a_hay.substring_index (a_needle, i)
				if i > 0 then
					Result := Result + 1
					i := i + a_needle.count
				end
			end
		ensure
			non_negative: Result >= 0
		end

end
