note
	description: "[
		The store and domain laws under assault (Phase 1b): the memory
		oracle's real bodies, its value semantics (D5), the marker as
		authentication (D4), gap-free pages, history paging, revocation,
		the attachment path pinned to its hash, the user rules, and the
		decoder's refusals. Hand-computed expectations throughout.
	]"
	author: "Larry Rix"

class
	STORE_ASSAULT

inherit
	TEST_SET_BASE

feature -- Store laws

	test_events_are_gapless_and_pages_are_newest
		local
			s: MEMORY_CHAT_STORE
			l_page: ARRAYED_LIST [CHAT_EVENT]
			i: INTEGER
		do
			s := populated_store
			from i := 1 until i > 7 loop
				post (s, 1, 1, "m" + i.out)
				i := i + 1
			end
			post (s, 2, 1, "other room")
			assert ("eight events, ids 1..8", s.event_count = 8 and s.last_event_id = 8)
			l_page := s.events_since (1, 0, 3)
			assert ("full page is the first three of room 1", l_page.count = 3 and l_page [1].id = 1 and l_page [3].id = 3)
			l_page := s.events_since (1, 3, 100)
			assert ("catch-up after 3 is 4..7", l_page.count = 4 and l_page.first.id = 4 and l_page.last.id = 7)
			assert ("count_after agrees", s.count_after (1, 3) = 4 and s.count_after (1, 7) = 0 and s.count_after (2, 0) = 1)
			l_page := s.events_before (1, 6, 2)
			assert ("history: the two immediately before 6 are 4 and 5, ascending", l_page.count = 2 and l_page [1].id = 4 and l_page [2].id = 5)
			l_page := s.events_before (1, 2, 10)
			assert ("history at the start is just 1", l_page.count = 1 and l_page.first.id = 1)
			assert ("count_before agrees", s.count_before (1, 6) = 5 and s.count_before (2, 100) = 1)
		end

	test_oracle_returns_copies
			-- D5: a change to a returned user reaches the store only through update_user.
		local
			s: MEMORY_CHAT_STORE
		do
			s := populated_store
			if attached s.user (1) as u then
				u.set_active (False)
				assert ("store unchanged without update_user", attached s.user (1) as u2 and then u2.is_active)
				s.update_user (u)
				assert ("persisted through the command", attached s.user (1) as u3 and then not u3.is_active)
			else
				assert ("user 1 exists", False)
			end
		end

	test_marker_authenticates
			-- D4: the bot flag must agree with the sender; a person's draft with the flag set is refused.
		local
			s: MEMORY_CHAT_STORE
			l_payload: SIMPLE_JSON_OBJECT
			l_draft: CHAT_EVENT_DRAFT
			l_refused: BOOLEAN
		do
			s := populated_store
			create l_payload.make
			create l_draft.make (1, 1, {CHAT_EVENT_KINDS}.Kind_message, {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " pretending", Void, l_payload, True)
			l_refused := not accepts (s, l_draft)
			assert ("person flagged as bot refused by the store", l_refused)
			create l_draft.make (1, 3, {CHAT_EVENT_KINDS}.Kind_message, {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " real bot", Void, l_payload, True)
			assert ("bot with the flag accepted", accepts (s, l_draft))
		end

	test_membership_and_default_room
		local
			s: MEMORY_CHAT_STORE
			l_dup: CHAT_MEMBERSHIP
			l_now: SIMPLE_DATE_TIME
		do
			s := populated_store
			assert ("first room is the default", s.default_room_id = 1 and attached s.default_room as r and then r.id = 1)
			assert ("member queries", s.is_member (1, 1) and not s.is_member (1, 2) and attached s.membership (1, 1) as m and then m.role.same_string ({CHAT_MEMBERSHIP}.Role_member))
			create l_now.make_now
			create l_dup.make (1, 1, {CHAT_MEMBERSHIP}.Role_member, l_now)
			assert ("duplicate membership refused", not adds_membership (s, l_dup))
			assert ("rooms_of", s.rooms_of (1).count = 1 and s.rooms_of (2).count = 2)
		end

	test_sessions_and_revocation
		local
			s: MEMORY_CHAT_STORE
			l_now, l_later: SIMPLE_DATE_TIME
			l_a, l_b: CHAT_SESSION
		do
			s := populated_store
			create l_now.make (2026, 8, 29, 12, 0, 0)
			l_later := l_now.plus_seconds (3600)
			create l_a.make (0, 1, hex64, l_now, l_later, False)
			create l_b.make (0, 1, hex64_b, l_now, l_later, False)
			s.put_session (l_a)
			s.put_session (l_b)
			assert ("two sessions for user 1", s.session_count = 2 and s.has_session_of (1) and not s.has_session_of (2) and l_a.id = 1 and l_b.id = 2)
			s.remove_session (hex64)
			assert ("one removed", s.session_count = 1 and s.session_by_hash (hex64) = Void and attached s.session_by_hash (hex64_b))
			s.remove_sessions_of (1)
			assert ("revocation empties the user's sessions", not s.has_session_of (1) and s.session_count = 0)
		end

	test_oracle_copies_strings
			-- Issue 23 / M-D3: the oracle stores and returns fresh strings -
			-- mutating a returned object's text never reaches the store, and
			-- what was stored compares `~' with what comes back. The memory
			-- store always opens, with nothing to explain (M-D8).
		local
			s: MEMORY_CHAT_STORE
			u: CHAT_USER
			e: CHAT_EVENT
			l_now: SIMPLE_DATE_TIME
			l_payload, l_fluent: SIMPLE_JSON_OBJECT
		do
			s := populated_store
			assert ("memory opens with nothing to explain", s.is_open and s.last_open_error = Void)
			if attached s.user (1) as u1 then
				u1.display_name.append ({STRING_32} "!")
				assert ("display mutation does not reach the oracle",
					attached s.user (1) as u2 and then u2.display_name.same_string ({STRING_32} "Larry"))
			else
				assert ("user 1 exists", False)
			end
			create l_now.make_now
			create u.make (0, "zed", {STRING_32} "Zed", hex32 + "$600000$" + hex64, False, False, l_now)
			s.add_user (u)
			assert ("stored user equals the argument by value, as a distinct object",
				attached s.user (u.id) as u3 and then (u3 ~ u and u3 /= u))
			create l_payload.make
			l_fluent := l_payload.put_string ({STRING_32} "v", {STRING_32} "k")
			e := s.append_event (create {CHAT_EVENT_DRAFT}.make (1, 1, {CHAT_EVENT_KINDS}.Kind_message, {STRING_32} "hello", Void, l_payload, False))
			assert ("returned event equals the stored one by value, as a distinct object",
				attached s.event (e.id) as f and then (f ~ e and f /= e))
			e.body.append ({STRING_32} " changed")
			l_fluent := e.payload.put_string ({STRING_32} "evil", {STRING_32} "k")
			if attached s.event (e.id) as f2 then
				assert ("body mutation does not reach the oracle", f2.body.same_string ({STRING_32} "hello"))
				assert ("payload mutation does not reach the oracle",
					attached f2.payload.string_item ({STRING_32} "k") as v and then v.same_string ({STRING_32} "v"))
			else
				assert ("event stored", False)
			end
		end

feature -- Domain rules

	test_attachment_path_is_pinned_to_its_hash
		local
			a: CHAT_ATTACHMENT
			l_now: SIMPLE_DATE_TIME
			l_rules: CHAT_ATTACHMENT_RULES
		do
			create l_now.make_now
			create l_rules
			create a.make (0, 1, {STRING_32} "meme.png", {CHAT_ATTACHMENT}.Mime_png, 10, hex64, l_now)
			assert ("computed path", a.stored_relpath.same_string ("uploads/" + hex64 + ".png"))
			assert ("traversal hash refused", not l_rules.is_sha256_hex ("../../../../../../../../../../../../../../../../../../../../../x"))
			assert ("uppercase hex refused", not l_rules.is_sha256_hex (hex64.as_upper))
			assert ("name with separators refused", not l_rules.is_valid_name ({STRING_32} "..\evil.png") and not l_rules.is_valid_name ({STRING_32} "a/b"))
		end

	test_user_rules
		local
			r: CHAT_USER_RULES
		do
			create r
			assert ("zero-width name refused", not r.is_valid_display_name ({STRING_32} "%/0x200B/%/0x200B/"))
			assert ("control refused", not r.is_valid_display_name ({STRING_32} "a%/1/b"))
			assert ("newline refused", not r.is_valid_display_name ({STRING_32} "a%Nb"))
			assert ("hebrew accepted", r.is_valid_display_name ({STRING_32} "%/1513/%/1500/%/1493/%/1501/"))
			assert ("pbkdf2 shape", r.is_pbkdf2 ("0123456789abcdef0123456789abcdef$600000$" + hex64))
			assert ("short salt refused", not r.is_pbkdf2 ("aa$600000$" + hex64))
			assert ("below the floor refused", not r.is_pbkdf2 ("0123456789abcdef0123456789abcdef$1000$" + hex64))
			assert ("two dollars alone refused", not r.is_pbkdf2 ("$$"))
		end

	test_decoder_refuses_hostile_fields
		local
			j: CHAT_JSON
		do
			create j.make
			assert ("hebrew kind is void, not an exception", j.event_from_bytes ("{%"id%":1,%"room_id%":1,%"sender_id%":1,%"kind%":%"%/215/%/169/%",%"created_at%":%"2026-08-29T12:00:00%",%"body%":%"x%"}") = Void)
			assert ("garbage created_at is void", j.event_from_bytes ("{%"id%":1,%"room_id%":1,%"sender_id%":1,%"kind%":%"message%",%"created_at%":%"yesterday%",%"body%":%"x%"}") = Void)
			assert ("negative system sender is void", j.event_from_bytes ("{%"id%":1,%"room_id%":1,%"sender_id%":-7,%"kind%":%"system%",%"created_at%":%"2026-08-29T12:00:00%",%"body%":%"x%"}") = Void)
			assert ("attachment on a message is void", j.event_from_bytes ("{%"id%":1,%"room_id%":1,%"sender_id%":1,%"kind%":%"message%",%"created_at%":%"2026-08-29T12:00:00%",%"body%":%"x%",%"attachment%":{%"id%":3,%"mime%":%"image/png%",%"size%":5,%"name%":%"a.png%",%"sha256%":%"" + hex64 + "%"}}") = Void)
			assert ("unstored attachment is void", j.event_from_bytes ("{%"id%":1,%"room_id%":1,%"sender_id%":1,%"kind%":%"image%",%"created_at%":%"2026-08-29T12:00:00%",%"body%":%"%",%"attachment%":{%"id%":0,%"mime%":%"image/png%",%"size%":5,%"name%":%"a.png%",%"sha256%":%"" + hex64 + "%"}}") = Void)
			assert ("empty error message is void", j.error_from_bytes ("{%"code%":%"refused%",%"message%":%"%"}", 400) = Void)
			assert ("error with a non-error status is void", j.error_from_bytes ("{%"code%":%"refused%",%"message%":%"no%"}", 200) = Void)
			assert ("unknown code maps to unavailable", attached j.error_from_bytes ("{%"code%":%"weird%",%"message%":%"no%"}", 400) as e and then e.code.same_string ({CHAT_ERROR}.Code_unavailable))
			assert ("non-hex token is void", j.login_from_bytes ("{%"token%":%"" + hex64.as_upper + "%",%"member%":{%"id%":1,%"username%":%"a%",%"display_name%":%"A%",%"is_admin%":false,%"is_bot%":false}}") = Void)
			assert ("iso shape", j.is_iso8601 ("2026-08-29T12:00:00") and j.is_iso8601 ("2026-08-29T12:00:00Z") and not j.is_iso8601 ("2026-08-29 12:00:00"))
		end

feature {NONE} -- Fixtures

	populated_store: MEMORY_CHAT_STORE
			-- Users 1 (person, admin), 2 (person), 3 (bot); rooms 1 (default) and 2; 1 in room 1, 2 in both.
		local
			l_now: SIMPLE_DATE_TIME
			u: CHAT_USER
			r: CHAT_ROOM
		do
			create Result.make
			Result.open
			create l_now.make_now
			create u.make (0, "larry", {STRING_32} "Larry", hex32 + "$600000$" + hex64, True, False, l_now)
			Result.add_user (u)
			create u.make (0, "nick", {STRING_32} "Nick", hex32 + "$600000$" + hex64, False, False, l_now)
			Result.add_user (u)
			create u.make (0, "robot", {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " Robot", "", False, True, l_now)
			Result.add_user (u)
			create r.make (0, {STRING_32} "General", l_now)
			Result.add_room (r)
			create r.make (0, {STRING_32} "Side", l_now)
			Result.add_room (r)
			Result.add_membership (create {CHAT_MEMBERSHIP}.make (1, 1, {CHAT_MEMBERSHIP}.Role_member, l_now))
			Result.add_membership (create {CHAT_MEMBERSHIP}.make (1, 2, {CHAT_MEMBERSHIP}.Role_member, l_now))
			Result.add_membership (create {CHAT_MEMBERSHIP}.make (2, 2, {CHAT_MEMBERSHIP}.Role_member, l_now))
			Result.add_membership (create {CHAT_MEMBERSHIP}.make (1, 3, {CHAT_MEMBERSHIP}.Role_member, l_now))
		ensure
			three_users: Result.user_count = 3 and Result.has_admin
			two_rooms: Result.room_count = 2
		end

	post (a_store: MEMORY_CHAT_STORE; a_room_id, a_sender_id: INTEGER_64; a_body: STRING_8)
		local
			l_payload: SIMPLE_JSON_OBJECT
			l_event: CHAT_EVENT
		do
			create l_payload.make
			l_event := a_store.append_event (create {CHAT_EVENT_DRAFT}.make (a_room_id, a_sender_id, {CHAT_EVENT_KINDS}.Kind_message, a_body, Void, l_payload, False))
		end

	accepts (a_store: MEMORY_CHAT_STORE; a_draft: CHAT_EVENT_DRAFT): BOOLEAN
			-- Does `append_event' accept `a_draft' (its precondition holds)?
		local
			l_event: CHAT_EVENT
			l_failed: BOOLEAN
		do
			if not l_failed then
				l_event := a_store.append_event (a_draft)
				Result := True
			end
		rescue
			l_failed := True
			retry
		end

	adds_membership (a_store: MEMORY_CHAT_STORE; a_membership: CHAT_MEMBERSHIP): BOOLEAN
		local
			l_failed: BOOLEAN
		do
			if not l_failed then
				a_store.add_membership (a_membership)
				Result := True
			end
		rescue
			l_failed := True
			retry
		end

	hex64: STRING_8
		do
			Result := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
		end

	hex64_b: STRING_8
		do
			Result := "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
		end

	hex32: STRING_8
		do
			Result := "0123456789abcdef0123456789abcdef"
		end

end
