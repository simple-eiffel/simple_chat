note
	description: "[
		The store equivalence assault (Phase 4 Task 4): one scripted drive
		runs against the memory oracle and the SQLite store through the
		CHAT_STORE interface alone, and comparator helpers check the
		outcome of every step - counts, ids, refusals, ordering, paging,
		round-tripped text (Hebrew and the robot marker included) and
		attachment bytes with their sha256 intact. Events are compared
		field by field without their timestamps (each store stamps its
		own); everything else carries explicit dates, so whole-value `~'
		comparison works across the SQL boundary.

		Then the SQLite-only laws: a close and reopen loses nothing; a
		file stamped AHEAD of {CHAT_SCHEMA}.Current_version is refused
		through `last_open_error' with `is_open' False; a file BEHIND is
		copied to `.bak' before it is migrated. Database files live under
		testing/equivalence_scratch and are wiped by each test's teardown
		(and again by the next run's setup, should an assault die mid-way).
	]"
	author: "Larry Rix"

class
	EQUIVALENCE_ASSAULT

inherit
	TEST_SET_BASE

feature -- Store equivalence

	test_store_equivalence_drive
			-- The one scripted drive, against both stores, compared step by step.
		local
			l_oracle: MEMORY_CHAT_STORE
			l_subject: SQLITE_CHAT_STORE
			l_path: STRING_32
		do
			l_path := fresh_database_path ("drive")
			create l_oracle.make
			create l_subject.make (l_path)
			l_oracle.open
			l_subject.open
			assert ("both open with nothing to explain", l_oracle.is_open and l_subject.is_open
				and l_oracle.last_open_error = Void and l_subject.last_open_error = Void)
			assert ("both at the current schema", l_oracle.schema_version = {CHAT_SCHEMA}.Current_version
				and l_subject.schema_version = {CHAT_SCHEMA}.Current_version)
			drive (l_oracle, l_subject)
			l_subject.close
			wipe_database (l_path)
		end

	test_sqlite_survives_close_and_reopen
			-- Everything written before `close' is still there after `open'.
		local
			l_store: SQLITE_CHAT_STORE
			l_path: STRING_32
			l_before_events: ARRAYED_LIST [CHAT_EVENT]
			l_before_user: detachable CHAT_USER
			l_before_bytes: detachable SPECIAL [NATURAL_8]
		do
			l_path := fresh_database_path ("reopen")
			create l_store.make (l_path)
			l_store.open
			assert ("opened with nothing to explain", l_store.is_open and l_store.last_open_error = Void)
			populate (l_store)
			l_before_events := l_store.events_since (1, 0, 100)
			l_before_user := l_store.user (2)
			l_before_bytes := l_store.attachment_bytes (1)
			l_store.close
			assert ("closed", not l_store.is_open)
			l_store.open
			assert ("reopened with nothing to explain", l_store.is_open and l_store.last_open_error = Void)
			assert ("still the current schema", l_store.schema_version = {CHAT_SCHEMA}.Current_version)
			assert ("no backup for a current file", not file_exists (l_store.backup_path))
			assert ("counts survived", l_store.user_count = 3 and l_store.room_count = 2
				and l_store.event_count = 4 and l_store.last_event_id = 4
				and l_store.session_count = 1 and l_store.attachment_count = 1)
			assert_same_events ("events survived to the second", l_before_events, l_store.events_since (1, 0, 100), True)
			assert ("hebrew display survived", attached l_before_user as l_captured
				and then attached l_store.user (2) as l_reread and then l_captured ~ l_reread)
			assert ("attachment bytes survived", attached l_before_bytes as l_captured_bytes
				and then attached l_store.attachment_bytes (1) as l_reread_bytes
				and then same_bytes (l_captured_bytes, l_reread_bytes))
			assert ("membership and session survived", l_store.is_member (2, 1)
				and attached l_store.session_by_hash (hex_a))
			l_store.close
			wipe_database (l_path)
		end

	test_sqlite_refuses_ahead_schema
			-- A file stamped ahead of Current_version is refused, never migrated down (M-D8).
		local
			l_store: SQLITE_CHAT_STORE
			l_path: STRING_32
			l_raw: SIMPLE_SQL_DATABASE
		do
			l_path := fresh_database_path ("ahead")
			create l_store.make (l_path)
			l_store.open
			assert ("a current file to stamp", l_store.is_open)
			l_store.close
			create l_raw.make (l_path)
			l_raw.perform ("UPDATE schema_version SET version = 99")
			l_raw.close
			l_store.open
			assert ("ahead file refused", not l_store.is_open)
			assert ("refusal explained as unavailable", attached l_store.last_open_error as l_error
				and then l_error.code.same_string ({CHAT_ERROR}.Code_unavailable))
			wipe_database (l_path)
		end

	test_sqlite_backs_up_a_behind_file
			-- A behind-version file is copied to `.bak' before migration touches it.
		local
			l_store: SQLITE_CHAT_STORE
			l_path: STRING_32
			l_raw: SIMPLE_SQL_DATABASE
			l_when: SIMPLE_DATE_TIME
		do
			l_path := fresh_database_path ("behind")
				-- A real SQLite file with content and no schema_version: version 0.
			create l_raw.make (l_path)
			l_raw.perform ("CREATE TABLE keepsake (x INTEGER)")
			l_raw.perform ("INSERT INTO keepsake (x) VALUES (7)")
			l_raw.close
			assert ("a version zero file with content", file_exists (l_path))
			create l_store.make (l_path)
			l_store.open
			assert ("behind file opens after migration - " + open_error_text (l_store), l_store.is_open and l_store.last_open_error = Void)
			assert ("migrated to the current version", l_store.schema_version = {CHAT_SCHEMA}.Current_version)
			assert ("the backup appeared first", file_exists (l_store.backup_path))
			create l_when.make (2026, 8, 30, 12, 0, 0)
			add_user_to (l_store, "larry", {STRING_32} "Larry", True, False, l_when)
			assert ("the migrated store works", l_store.user_count = 1 and l_store.has_admin)
			l_store.close
			wipe_database (l_path)
		end

feature {NONE} -- The drive

	drive (a_oracle, a_subject: CHAT_STORE)
			-- The one script, every step's outcome compared between the stores.
		require
			both_open: a_oracle.is_open and a_subject.is_open
			both_empty: a_oracle.event_count = 0 and a_subject.event_count = 0
		local
			l_when: SIMPLE_DATE_TIME
			l_first, l_second: CHAT_EVENT
			l_bytes: SPECIAL [NATURAL_8]
			i: INTEGER
		do
			create l_when.make (2026, 8, 30, 12, 0, 0)

				-- Users: add, duplicate refusal through the has_username guard, update, deactivate.
			add_user_to (a_oracle, "larry", {STRING_32} "Larry", True, False, l_when)
			add_user_to (a_subject, "larry", {STRING_32} "Larry", True, False, l_when)
			add_user_to (a_oracle, "nick", {STRING_32} "Nick", False, False, l_when)
			add_user_to (a_subject, "nick", {STRING_32} "Nick", False, False, l_when)
			add_user_to (a_oracle, "robot", {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " Robot", False, True, l_when)
			add_user_to (a_subject, "robot", {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " Robot", False, True, l_when)
			assert_same_state ("three users", a_oracle, a_subject)
			assert ("subject assigned the oracle's ids", a_subject.has_user (1) and a_subject.has_user (3) and not a_subject.has_user (4))
			assert ("duplicate username refused by both",
				not accepts_user (a_oracle, "larry", l_when) and not accepts_user (a_subject, "larry", l_when))
			assert_same_state ("after the refusals", a_oracle, a_subject)
			assert_same_user ("larry compares", a_oracle, a_subject, 1)
			assert_same_user ("robot compares", a_oracle, a_subject, 3)
			assert ("lookup by username agrees", attached a_oracle.user_by_username ("nick") as l_left_user
				and then attached a_subject.user_by_username ("nick") as l_right_user and then l_left_user ~ l_right_user)
			assert ("users lists agree", a_oracle.users.count = a_subject.users.count)
			update_to_hebrew_and_deactivate (a_oracle, 2)
			update_to_hebrew_and_deactivate (a_subject, 2)
			assert_same_user ("nick updated on both", a_oracle, a_subject, 2)
			assert ("hebrew display round trips the disk", attached a_subject.user (2) as l_nick
				and then l_nick.display_name.same_string (hebrew_name) and then not l_nick.is_active)

				-- Rooms and memberships: add, double-membership refusal, member queries.
			add_room_to (a_oracle, {STRING_32} "General", l_when)
			add_room_to (a_subject, {STRING_32} "General", l_when)
			add_room_to (a_oracle, {STRING_32} "Side", l_when)
			add_room_to (a_subject, {STRING_32} "Side", l_when)
			assert ("first room is the default on both", a_oracle.default_room_id = 1 and a_subject.default_room_id = 1)
			assert ("default room compares", attached a_oracle.default_room as l_left_room
				and then attached a_subject.default_room as l_right_room and then l_left_room ~ l_right_room)
			join (a_oracle, 1, 1, l_when)
			join (a_subject, 1, 1, l_when)
			join (a_oracle, 1, 2, l_when)
			join (a_subject, 1, 2, l_when)
			join (a_oracle, 2, 2, l_when)
			join (a_subject, 2, 2, l_when)
			join (a_oracle, 1, 3, l_when)
			join (a_subject, 1, 3, l_when)
			assert ("double membership refused by both",
				not accepts_membership (a_oracle, 1, 1, l_when) and not accepts_membership (a_subject, 1, 1, l_when))
			assert_same_membership ("larry in general", a_oracle, a_subject, 1, 1)
			assert ("member matrix agrees",
				a_oracle.is_member (1, 1) = a_subject.is_member (1, 1)
				and a_oracle.is_member (1, 2) = a_subject.is_member (1, 2)
				and a_oracle.is_member (2, 2) = a_subject.is_member (2, 2)
				and a_oracle.is_member (3, 1) = a_subject.is_member (3, 1)
				and not a_subject.is_member (3, 2))
			assert ("rooms_of agrees", same_room_lists (a_oracle.rooms_of (2), a_subject.rooms_of (2))
				and same_room_lists (a_oracle.rooms_of (1), a_subject.rooms_of (1))
				and a_subject.rooms_of (2).count = 2)

				-- Events: text, bot-marked, system, payload, Hebrew, image; gapless ids.
			from
				i := 1
			until
				i > 7
			loop
				l_first := posted (a_oracle, 1, 1, "m" + i.out)
				l_second := posted (a_subject, 1, 1, "m" + i.out)
				assert ("post " + i.out + " agrees", event_matches (l_first, l_second, False))
				i := i + 1
			variant
				8 - i
			end
			l_first := posted (a_oracle, 2, 2, "other room")
			l_second := posted (a_subject, 2, 2, "other room")
			assert ("room 2 post agrees", event_matches (l_first, l_second, False))
			assert ("eight events, ids 1..8, on both", a_oracle.last_event_id = 8 and a_subject.last_event_id = 8
				and a_oracle.event_count = 8 and a_subject.event_count = 8)
			assert ("person flagged as a bot refused by both",
				not accepts_draft (a_oracle, person_pretending_draft) and not accepts_draft (a_subject, person_pretending_draft))
			assert ("nothing burned by the refusals", a_oracle.last_event_id = 8 and a_subject.last_event_id = 8)
			l_first := bot_posted (a_oracle)
			l_second := bot_posted (a_subject)
			assert ("bot post agrees and is ninth", event_matches (l_first, l_second, False) and l_second.id = 9)
			l_first := system_posted (a_oracle)
			l_second := system_posted (a_subject)
			assert ("system post agrees", event_matches (l_first, l_second, False) and l_second.sender_id = 0)
			l_first := payload_posted (a_oracle)
			l_second := payload_posted (a_subject)
			assert ("payload post agrees", event_matches (l_first, l_second, False))
			assert ("payload round trips the disk", attached a_subject.event (l_second.id) as l_reread
				and then attached l_reread.payload.string_item ({STRING_32} "k") as l_value
				and then l_value.same_string (hebrew_name))
			l_first := posted (a_oracle, 1, 1, hebrew_body)
			l_second := posted (a_subject, 1, 1, hebrew_body)
			assert ("hebrew and robot body agrees", event_matches (l_first, l_second, False))
			assert ("hebrew body round trips the disk", attached a_subject.event (l_second.id) as l_hebrew
				and then l_hebrew.body.same_string (hebrew_body))

				-- Attachments: metadata, bytes round trip, sha256 intact, an image event riding one.
			l_bytes := sample_bytes (64)
			add_attachment_to (a_oracle, 1, l_bytes, l_when)
			add_attachment_to (a_subject, 1, l_bytes, l_when)
			assert_same_state ("one attachment", a_oracle, a_subject)
			assert ("attachment metadata compares", attached a_oracle.attachment (1) as l_left_meta
				and then attached a_subject.attachment (1) as l_right_meta and then l_left_meta ~ l_right_meta)
			assert ("no bytes yet on either", not a_oracle.has_attachment_bytes (1) and not a_subject.has_attachment_bytes (1)
				and a_oracle.attachment_bytes (1) = Void and a_subject.attachment_bytes (1) = Void)
			a_oracle.put_attachment_bytes (1, l_bytes)
			a_subject.put_attachment_bytes (1, l_bytes)
			assert ("bytes kept on both", a_oracle.has_attachment_bytes (1) and a_subject.has_attachment_bytes (1))
			assert ("bytes round trip intact on both", attached a_oracle.attachment_bytes (1) as l_left_bytes
				and then attached a_subject.attachment_bytes (1) as l_right_bytes
				and then same_bytes (l_left_bytes, l_right_bytes) and then same_bytes (l_right_bytes, l_bytes))
			assert ("sha256 of what comes back equals the record's", attached a_subject.attachment_bytes (1) as l_disk_bytes
				and then attached a_subject.attachment (1) as l_meta
				and then hash_of (l_disk_bytes).same_string (l_meta.sha256))
			l_first := image_posted (a_oracle, 1, 1, 1)
			l_second := image_posted (a_subject, 1, 1, 1)
			assert ("image post agrees", event_matches (l_first, l_second, False))
			assert ("image event re-reads with its attachment", attached a_subject.event (l_second.id) as l_image
				and then attached l_image.attachment as l_riding
				and then (l_riding.id = 1 and l_riding.mime.same_string ({CHAT_ATTACHMENT}.Mime_png)))

				-- Paging: across boundaries, history, counts.
			assert_same_events ("first full page", a_oracle.events_since (1, 0, 3), a_subject.events_since (1, 0, 3), False)
			assert_same_events ("catch-up after 3", a_oracle.events_since (1, 3, 100), a_subject.events_since (1, 3, 100), False)
			assert_same_events ("page across the other room's id", a_oracle.events_since (1, 7, 2), a_subject.events_since (1, 7, 2), False)
			assert ("the page skips id 8 yet stays gapless for room 1", a_subject.events_since (1, 7, 2).first.id = 9
				and a_subject.events_since (1, 7, 2).last.id = 10)
			assert ("count_after agrees", a_oracle.count_after (1, 3) = a_subject.count_after (1, 3)
				and a_oracle.count_after (2, 0) = a_subject.count_after (2, 0)
				and a_subject.count_after (2, 0) = 1
				and a_oracle.count_after (1, a_oracle.last_event_id) = 0
				and a_subject.count_after (1, a_subject.last_event_id) = 0)
			assert_same_events ("history before 6", a_oracle.events_before (1, 6, 2), a_subject.events_before (1, 6, 2), False)
			assert_same_events ("history at the start", a_oracle.events_before (1, 2, 10), a_subject.events_before (1, 2, 10), False)
			assert_same_events ("history across the other room's id", a_oracle.events_before (1, 10, 3), a_subject.events_before (1, 10, 3), False)
			assert ("history across the gap is 6, 7, 9 ascending", a_subject.events_before (1, 10, 3).count = 3
				and a_subject.events_before (1, 10, 3).first.id = 6 and a_subject.events_before (1, 10, 3).last.id = 9)
			assert ("count_before agrees", a_oracle.count_before (1, 6) = a_subject.count_before (1, 6)
				and a_oracle.count_before (1, 10) = a_subject.count_before (1, 10)
				and a_subject.count_before (1, 10) = 8)

				-- Sessions: put, by hash, update in place, remove, revoke.
			put_session_to (a_oracle, 1, hex_a, False, l_when, 3600)
			put_session_to (a_subject, 1, hex_a, False, l_when, 3600)
			put_session_to (a_oracle, 1, hex_b, False, l_when, 3600)
			put_session_to (a_subject, 1, hex_b, False, l_when, 3600)
			put_session_to (a_oracle, 3, hex_c, True, l_when, 3600)
			put_session_to (a_subject, 3, hex_c, True, l_when, 3600)
			assert_same_state ("three sessions", a_oracle, a_subject)
			assert ("session by hash compares", attached a_oracle.session_by_hash (hex_a) as l_left_session
				and then attached a_subject.session_by_hash (hex_a) as l_right_session
				and then (l_left_session ~ l_right_session and l_left_session.id = 1))
			put_session_to (a_oracle, 1, hex_a, False, l_when, 7200)
			put_session_to (a_subject, 1, hex_a, False, l_when, 7200)
			assert ("same hash updated in place on both", a_oracle.session_count = 3 and a_subject.session_count = 3
				and attached a_oracle.session_by_hash (hex_a) as l_left_updated
				and then attached a_subject.session_by_hash (hex_a) as l_right_updated
				and then (l_left_updated ~ l_right_updated and l_left_updated.id = 1))
			a_oracle.remove_session (hex_b)
			a_subject.remove_session (hex_b)
			assert ("one removed on both", a_oracle.session_count = 2 and a_subject.session_count = 2
				and a_oracle.session_by_hash (hex_b) = Void and a_subject.session_by_hash (hex_b) = Void)
			a_oracle.remove_sessions_of (1)
			a_subject.remove_sessions_of (1)
			assert ("revocation agrees", not a_oracle.has_session_of (1) and not a_subject.has_session_of (1)
				and a_oracle.has_session_of (3) and a_subject.has_session_of (3)
				and a_oracle.session_count = 1 and a_subject.session_count = 1)
			assert_same_state ("at the end of the drive", a_oracle, a_subject)
		end

feature {NONE} -- Comparators

	assert_same_state (a_tag: STRING_8; a_oracle, a_subject: CHAT_STORE)
			-- Every count and default agrees between the stores.
		do
			assert (a_tag + ": counts", a_oracle.user_count = a_subject.user_count
				and a_oracle.room_count = a_subject.room_count
				and a_oracle.event_count = a_subject.event_count
				and a_oracle.last_event_id = a_subject.last_event_id
				and a_oracle.session_count = a_subject.session_count
				and a_oracle.attachment_count = a_subject.attachment_count)
			assert (a_tag + ": defaults", a_oracle.default_room_id = a_subject.default_room_id
				and a_oracle.has_admin = a_subject.has_admin)
		end

	assert_same_user (a_tag: STRING_8; a_oracle, a_subject: CHAT_STORE; a_user_id: INTEGER_64)
		do
			assert (a_tag + ": presence", a_oracle.has_user (a_user_id) = a_subject.has_user (a_user_id)
				and ((a_oracle.user (a_user_id) = Void) = (a_subject.user (a_user_id) = Void)))
			if attached a_oracle.user (a_user_id) as l_left and then attached a_subject.user (a_user_id) as l_right then
				assert (a_tag + ": id", l_left.id = l_right.id)
				assert (a_tag + ": username", l_left.username.same_string (l_right.username))
				assert (a_tag + ": display", l_left.display_name.same_string (l_right.display_name))
				assert (a_tag + ": hash", l_left.password_hash.same_string (l_right.password_hash))
				assert (a_tag + ": flags", l_left.is_admin = l_right.is_admin
					and l_left.is_bot = l_right.is_bot and l_left.is_active = l_right.is_active)
				assert (a_tag + ": created_at left=" + l_left.created_at.to_iso8601 + " ts=" + l_left.created_at.to_timestamp.out
					+ " right=" + l_right.created_at.to_iso8601 + " ts=" + l_right.created_at.to_timestamp.out,
					l_left.created_at ~ l_right.created_at)
				assert (a_tag + ": whole value", l_left ~ l_right)
			end
		end

	assert_same_membership (a_tag: STRING_8; a_oracle, a_subject: CHAT_STORE; a_user_id, a_room_id: INTEGER_64)
		do
			assert (a_tag, a_oracle.is_member (a_user_id, a_room_id) = a_subject.is_member (a_user_id, a_room_id)
				and (attached a_oracle.membership (a_user_id, a_room_id) as l_left implies
					(attached a_subject.membership (a_user_id, a_room_id) as l_right and then l_left ~ l_right)))
		end

	assert_same_events (a_tag: STRING_8; a_left, a_right: ARRAYED_LIST [CHAT_EVENT]; a_with_dates: BOOLEAN)
			-- Same length, same events pairwise; timestamps compared only when `a_with_dates'.
		local
			i: INTEGER
			l_same: BOOLEAN
		do
			l_same := a_left.count = a_right.count
			from
				i := 1
			until
				i > a_left.count or not l_same
			loop
				l_same := event_matches (a_left [i], a_right [i], a_with_dates)
				i := i + 1
			variant
				a_left.count - i + 2
			end
			assert (a_tag, l_same)
		end

	event_matches (a_first, a_second: CHAT_EVENT; a_with_dates: BOOLEAN): BOOLEAN
			-- Field-for-field agreement; `a_with_dates' adds the timestamp
			-- (excluded across stores: each store stamps its own).
		do
			Result := a_first.id = a_second.id
				and a_first.room_id = a_second.room_id
				and a_first.sender_id = a_second.sender_id
				and a_first.kind.same_string (a_second.kind)
				and a_first.body.same_string (a_second.body)
				and a_first.is_bot_authored = a_second.is_bot_authored
				and ((a_first.attachment = Void) = (a_second.attachment = Void))
				and (attached a_first.attachment as l_first_riding implies
					(attached a_second.attachment as l_second_riding and then l_first_riding.id = l_second_riding.id))
				and a_first.payload.to_json_string.same_string (a_second.payload.to_json_string)
				and (a_with_dates implies a_first.created_at ~ a_second.created_at)
		end

	same_room_lists (a_left, a_right: ARRAYED_LIST [CHAT_ROOM]): BOOLEAN
		local
			i: INTEGER
		do
			Result := a_left.count = a_right.count
			from
				i := 1
			until
				i > a_left.count or not Result
			loop
				Result := a_left [i] ~ a_right [i]
				i := i + 1
			variant
				a_left.count - i + 2
			end
		end

	same_bytes (a_left, a_right: SPECIAL [NATURAL_8]): BOOLEAN
		local
			i: INTEGER
		do
			Result := a_left.count = a_right.count
			from
				i := 0
			until
				i >= a_left.count or not Result
			loop
				Result := a_left [i] = a_right [i]
				i := i + 1
			variant
				a_left.count - i + 1
			end
		end

feature {NONE} -- Script helpers

	add_user_to (a_store: CHAT_STORE; a_username: STRING_8; a_display: READABLE_STRING_GENERAL; a_admin, a_bot: BOOLEAN; a_when: SIMPLE_DATE_TIME)
		local
			l_user: CHAT_USER
		do
			if a_bot then
				create l_user.make (0, a_username, a_display, "", False, True, a_when)
			else
				create l_user.make (0, a_username, a_display, sample_hash, a_admin, False, a_when)
			end
			a_store.add_user (l_user)
		end

	update_to_hebrew_and_deactivate (a_store: CHAT_STORE; a_user_id: INTEGER_64)
		do
			if attached a_store.user (a_user_id) as l_user then
				l_user.set_display_name (hebrew_name)
				l_user.set_active (False)
				a_store.update_user (l_user)
			end
		end

	add_room_to (a_store: CHAT_STORE; a_name: READABLE_STRING_GENERAL; a_when: SIMPLE_DATE_TIME)
		local
			l_room: CHAT_ROOM
		do
			create l_room.make (0, a_name, a_when)
			a_store.add_room (l_room)
		end

	join (a_store: CHAT_STORE; a_room_id, a_user_id: INTEGER_64; a_when: SIMPLE_DATE_TIME)
		do
			a_store.add_membership (create {CHAT_MEMBERSHIP}.make (a_room_id, a_user_id, {CHAT_MEMBERSHIP}.Role_member, a_when))
		end

	posted (a_store: CHAT_STORE; a_room_id, a_sender_id: INTEGER_64; a_body: READABLE_STRING_GENERAL): CHAT_EVENT
		local
			l_payload: SIMPLE_JSON_OBJECT
		do
			create l_payload.make
			Result := a_store.append_event (create {CHAT_EVENT_DRAFT}.make (a_room_id, a_sender_id,
				{CHAT_EVENT_KINDS}.Kind_message, a_body, Void, l_payload, False))
		end

	bot_posted (a_store: CHAT_STORE): CHAT_EVENT
		local
			l_payload: SIMPLE_JSON_OBJECT
		do
			create l_payload.make
			Result := a_store.append_event (create {CHAT_EVENT_DRAFT}.make (1, 3, {CHAT_EVENT_KINDS}.Kind_message,
				{CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " beep", Void, l_payload, True))
		end

	system_posted (a_store: CHAT_STORE): CHAT_EVENT
		local
			l_payload: SIMPLE_JSON_OBJECT
		do
			create l_payload.make
			Result := a_store.append_event (create {CHAT_EVENT_DRAFT}.make (1, 0, {CHAT_EVENT_KINDS}.Kind_system,
				{STRING_32} "nick joined", Void, l_payload, False))
		end

	payload_posted (a_store: CHAT_STORE): CHAT_EVENT
		local
			l_payload, l_fluent: SIMPLE_JSON_OBJECT
		do
			create l_payload.make
			l_fluent := l_payload.put_string (hebrew_name, {STRING_32} "k")
			Result := a_store.append_event (create {CHAT_EVENT_DRAFT}.make (1, 1, {CHAT_EVENT_KINDS}.Kind_message,
				{STRING_32} "with payload", Void, l_payload, False))
		end

	image_posted (a_store: CHAT_STORE; a_room_id, a_sender_id, a_attachment_id: INTEGER_64): CHAT_EVENT
		require
			stored: a_store.has_attachment (a_attachment_id)
		local
			l_payload: SIMPLE_JSON_OBJECT
		do
			create l_payload.make
			check attachment_there: attached a_store.attachment (a_attachment_id) as l_attachment then
				Result := a_store.append_event (create {CHAT_EVENT_DRAFT}.make (a_room_id, a_sender_id,
					{CHAT_EVENT_KINDS}.Kind_image, {STRING_32} "sunset", l_attachment, l_payload, False))
			end
		end

	add_attachment_to (a_store: CHAT_STORE; a_uploader_id: INTEGER_64; a_bytes: SPECIAL [NATURAL_8]; a_when: SIMPLE_DATE_TIME)
			-- Store the metadata row whose sha256 really is the hash of `a_bytes'.
		local
			l_attachment: CHAT_ATTACHMENT
		do
			create l_attachment.make (0, a_uploader_id, {STRING_32} "meme.png", {CHAT_ATTACHMENT}.Mime_png,
				a_bytes.count, hash_of (a_bytes), a_when)
			a_store.add_attachment (l_attachment)
		end

	put_session_to (a_store: CHAT_STORE; a_user_id: INTEGER_64; a_hash: STRING_8; a_bot: BOOLEAN; a_when: SIMPLE_DATE_TIME; a_seconds: INTEGER)
		local
			l_session: CHAT_SESSION
		do
			create l_session.make (0, a_user_id, a_hash, a_when, a_when.plus_seconds (a_seconds), a_bot)
			a_store.put_session (l_session)
		end

	person_pretending_draft: CHAT_EVENT_DRAFT
			-- A person's draft dressed as a bot's; every store must refuse it (D4).
		local
			l_payload: SIMPLE_JSON_OBJECT
		do
			create l_payload.make
			create Result.make (1, 1, {CHAT_EVENT_KINDS}.Kind_message,
				{CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " pretending", Void, l_payload, True)
		end

feature {NONE} -- Refusal probes

	accepts_user (a_store: CHAT_STORE; a_username: STRING_8; a_when: SIMPLE_DATE_TIME): BOOLEAN
			-- Does `add_user' accept another user named `a_username'?
		local
			l_failed: BOOLEAN
		do
			if not l_failed then
				add_user_to (a_store, a_username, {STRING_32} "Copycat", False, False, a_when)
				Result := True
			end
		rescue
			l_failed := True
			retry
		end

	accepts_membership (a_store: CHAT_STORE; a_room_id, a_user_id: INTEGER_64; a_when: SIMPLE_DATE_TIME): BOOLEAN
		local
			l_failed: BOOLEAN
		do
			if not l_failed then
				join (a_store, a_room_id, a_user_id, a_when)
				Result := True
			end
		rescue
			l_failed := True
			retry
		end

	accepts_draft (a_store: CHAT_STORE; a_draft: CHAT_EVENT_DRAFT): BOOLEAN
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

feature {NONE} -- Fixtures

	populate (a_store: CHAT_STORE)
			-- Users, rooms, memberships, events (Hebrew body, image with
			-- bytes) and a session, all on explicit dates.
		local
			l_when: SIMPLE_DATE_TIME
			l_event: CHAT_EVENT
			l_bytes: SPECIAL [NATURAL_8]
		do
			create l_when.make (2026, 8, 30, 12, 0, 0)
			add_user_to (a_store, "larry", {STRING_32} "Larry", True, False, l_when)
			add_user_to (a_store, "nick", hebrew_name, False, False, l_when)
			add_user_to (a_store, "robot", {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " Robot", False, True, l_when)
			add_room_to (a_store, {STRING_32} "General", l_when)
			add_room_to (a_store, {STRING_32} "Side", l_when)
			join (a_store, 1, 1, l_when)
			join (a_store, 1, 2, l_when)
			l_event := posted (a_store, 1, 1, {STRING_32} "m1")
			l_event := posted (a_store, 1, 2, {STRING_32} "m2")
			l_event := posted (a_store, 1, 1, hebrew_body)
			l_bytes := sample_bytes (48)
			add_attachment_to (a_store, 1, l_bytes, l_when)
			a_store.put_attachment_bytes (1, l_bytes)
			l_event := image_posted (a_store, 1, 1, 1)
			put_session_to (a_store, 1, hex_a, False, l_when, 3600)
		end

	fresh_database_path (a_tag: STRING_8): STRING_32
			-- A per-test database path under the scratch directory, wiped of
			-- any leftovers a dead run may have abandoned.
		local
			l_directory: DIRECTORY
		do
			create l_directory.make (Scratch_directory)
			if not l_directory.exists then
				l_directory.recursive_create_dir
			end
			Result := Scratch_directory.to_string_32 + {STRING_32} "/" + a_tag.to_string_32 + {STRING_32} ".db"
			wipe_database (Result)
		ensure
			named: Result.ends_with ({STRING_32} ".db")
		end

	wipe_database (a_path: STRING_32)
			-- Remove the database file and its WAL, shared-memory and backup companions.
		do
			delete_file (a_path)
			delete_file (a_path + {STRING_32} "-wal")
			delete_file (a_path + {STRING_32} "-shm")
			delete_file (a_path + {STRING_32} ".bak")
		end

	delete_file (a_path: READABLE_STRING_GENERAL)
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			if l_file.exists then
				l_file.delete
			end
		end

	file_exists (a_path: READABLE_STRING_GENERAL): BOOLEAN
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			Result := l_file.exists
		end

	open_error_text (a_store: SQLITE_CHAT_STORE): STRING_8
			-- The refusal's message, for a failing assertion's tag.
		do
			if attached a_store.last_open_error as l_error then
				Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (l_error.message)
			else
				Result := "no error recorded"
			end
		end

	sample_bytes (a_count: INTEGER): SPECIAL [NATURAL_8]
			-- `a_count' bytes: the PNG signature, then every value climbing
			-- through the full byte range.
		require
			room_for_signature: a_count >= 8
		local
			i: INTEGER
		do
			create Result.make_empty (a_count)
			Result.extend ({NATURAL_8} 0x89)
			Result.extend ({NATURAL_8} 0x50)
			Result.extend ({NATURAL_8} 0x4E)
			Result.extend ({NATURAL_8} 0x47)
			Result.extend ({NATURAL_8} 0x0D)
			Result.extend ({NATURAL_8} 0x0A)
			Result.extend ({NATURAL_8} 0x1A)
			Result.extend ({NATURAL_8} 0x0A)
			from
				i := 8
			until
				i >= a_count
			loop
				Result.extend (((i * 7) \\ 256).to_natural_8)
				i := i + 1
			variant
				a_count - i
			end
		ensure
			sized: Result.count = a_count
		end

	hash_of (a_bytes: SPECIAL [NATURAL_8]): STRING_8
			-- The SHA-256 of `a_bytes' as 64 lowercase hex digits, computed
			-- the way CHAT_SERVICE computes it.
		local
			l_data: STRING_8
			l_crypto: SIMPLE_ENCRYPTION
			i: INTEGER
		do
			create l_data.make (a_bytes.count)
			from
				i := 0
			until
				i >= a_bytes.count
			loop
				l_data.append_code (a_bytes [i])
				i := i + 1
			variant
				a_bytes.count - i
			end
			create l_crypto.make
			Result := l_crypto.sha256 (l_data).as_lower
		ensure
			shape: Result.count = 64
		end

	hebrew_name: STRING_32
			-- Shalom, in Hebrew letters.
		do
			Result := {STRING_32} "%/1513/%/1500/%/1493/%/1501/"
		end

	hebrew_body: STRING_32
			-- Hebrew text and the robot emoji, together.
		do
			Result := hebrew_name + {STRING_32} " %/129302/"
		end

	sample_hash: STRING_8
			-- A well-formed PBKDF2 `salt$iterations$hash'.
		do
			Result := "0123456789abcdef0123456789abcdef$600000$" + hex_a
		end

	hex_a: STRING_8
		do
			Result := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
		end

	hex_b: STRING_8
		do
			Result := "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
		end

	hex_c: STRING_8
		do
			Result := "abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd"
		end

	Scratch_directory: STRING_8 = "testing/equivalence_scratch"

end
