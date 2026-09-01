note
	description: "[
		CHAT_STORE over simple_sql: one SQLite file opened in WAL mode, one
		connection; one caller at a time by construction (D1: the store
		lives on the API's processor), so correctness never depends on the
		SQLite build's threading mode (RISK-010).

		Ids are assigned here, never by AUTOINCREMENT: an event gets
		`last_event_id + 1' inside its insert transaction, so a refused
		insert burns nothing and the ids match the memory oracle exactly
		(DR-001). Text crosses the SQL boundary as UTF-8 bytes in TEXT
		columns ({UTF_CONVERTER} both ways), booleans as 0/1, dates as ISO
		8601 text - `append_event' stamps a timestamp already truncated to
		that precision, so what it returns equals what a later read
		rebuilds. Every row read builds a fresh object: the disk gives the
		value semantics the oracle promises (D5). Attachment bytes live in
		a BLOB column beside their metadata row.

		`open' refuses a database ahead of {CHAT_SCHEMA}.Current_version
		and explains in `last_open_error' (M-D8); a database behind is
		backed up to `backup_path' first - SQLite's own VACUUM INTO writes
		the copy - then migrated forward.
	]"
	author: "Larry Rix"

class
	SQLITE_CHAT_STORE

inherit
	CHAT_STORE

create
	make

feature {NONE} -- Initialization

	make (a_path: READABLE_STRING_GENERAL)
			-- A store for the database file at `a_path' (not yet open).
		require
			path_given: not a_path.is_empty
		do
			path := a_path.to_string_32
			create schema.make
		ensure
			path_set: path.same_string_general (a_path)
			not_open: not is_open
		end

feature -- Access

	path: STRING_32

	backup_path: STRING_32
			-- Where `open' copies a behind-version file before migrating.
		do
			Result := path + {STRING_32} ".bak"
		ensure
			beside_the_file: Result.starts_with (path)
		end

feature -- Status report

	is_open: BOOLEAN
		do
			Result := attached db as l_db and then l_db.is_open
		end

	last_open_error: detachable CHAT_ERROR
			-- Why the last `open' did not open: a database ahead of
			-- {CHAT_SCHEMA}.Current_version, or an unusable file. Void
			-- after a successful `open'.

feature -- Lifecycle

	open
		local
			l_db: detachable SIMPLE_SQL_DATABASE
			l_pragma: SIMPLE_SQL_RESULT
			l_version: INTEGER
			l_existed, l_failed: BOOLEAN
		do
			if l_failed then
				db := Void
				create last_open_error.make ({CHAT_ERROR}.Code_unavailable, "The database file cannot be opened or migrated.", 503)
			else
				last_open_error := Void
				l_existed := file_has_content (path)
				create l_db.make (path)
				l_version := schema.version_of (l_db)
				if l_version > {CHAT_SCHEMA}.Current_version then
						-- Refused, never migrated down (M-D8).
					l_db.close
					db := Void
					create last_open_error.make ({CHAT_ERROR}.Code_unavailable,
						"The database is schema version " + l_version.out + "; this server understands only "
						+ {CHAT_SCHEMA}.Current_version.out + " and never migrates down.", 503)
				else
					if l_version < {CHAT_SCHEMA}.Current_version and l_existed then
							-- The backup first, written by SQLite itself: a plain
							-- file copy of a just-queried database trips over the
							-- connection's Windows file lock; VACUUM INTO never does.
						remove_file (backup_path)
						l_db.perform_with ("VACUUM INTO ?", <<backup_path>>)
						check backup_made: not l_db.error_occurred end
					end
					l_pragma := l_db.run_query ("PRAGMA journal_mode=WAL")
					schema.migrate (l_db)
					db := l_db
					next_session_id := scalar_64 ("SELECT COALESCE(MAX(id), 0) AS n FROM session")
				end
			end
		rescue
			if attached l_db as l_open_db and then l_open_db.is_open then
				l_open_db.close
			end
			l_failed := True
			retry
		end

	close
		do
			if attached db as l_db then
				if l_db.is_open then
					l_db.close
				end
				db := Void
			end
		end

	schema_version: INTEGER
		do
			Result := schema.version_of (active_db)
		end

feature -- Counts

	last_event_id: INTEGER_64
		do
			Result := scalar_64 ("SELECT COALESCE(MAX(id), 0) AS n FROM event")
		end

	event_count: INTEGER_64
		do
			Result := scalar_64 ("SELECT COUNT(*) AS n FROM event")
		end

	user_count: INTEGER
		do
			Result := scalar_64 ("SELECT COUNT(*) AS n FROM user").to_integer_32
		end

	room_count: INTEGER
		do
			Result := scalar_64 ("SELECT COUNT(*) AS n FROM room").to_integer_32
		end

	session_count: INTEGER
		do
			Result := scalar_64 ("SELECT COUNT(*) AS n FROM session").to_integer_32
		end

	attachment_count: INTEGER
		do
			Result := scalar_64 ("SELECT COUNT(*) AS n FROM attachment").to_integer_32
		end

feature -- Events

	append_event (a_draft: CHAT_EVENT_DRAFT): CHAT_EVENT
		local
			l_db: SIMPLE_SQL_DATABASE
			l_now: SIMPLE_DATE_TIME
			l_id: INTEGER_64
		do
				-- The timestamp is truncated to ISO precision up front, so the
				-- returned event equals what a later read rebuilds.
			l_now := date_of ((create {SIMPLE_DATE_TIME}.make_now).to_iso8601)
			l_db := active_db
			l_db.begin_transaction
			l_id := last_event_id + 1
			if attached a_draft.attachment as l_attachment then
				l_db.perform_with (Insert_event_sql, <<l_id, a_draft.room_id, a_draft.kind, a_draft.sender_id,
					iso (l_now), utf8 (a_draft.body), l_attachment.id, utf8 (a_draft.payload.to_json_string), a_draft.is_bot_authored>>)
			else
				l_db.perform_with (Insert_event_sql, <<l_id, a_draft.room_id, a_draft.kind, a_draft.sender_id,
					iso (l_now), utf8 (a_draft.body), Void, utf8 (a_draft.payload.to_json_string), a_draft.is_bot_authored>>)
			end
			finish (l_db)
			create Result.make (l_id, a_draft.room_id, a_draft.sender_id, a_draft.kind, l_now,
				a_draft.body, a_draft.attachment, a_draft.payload, a_draft.is_bot_authored)
		end

	event (a_id: INTEGER_64): detachable CHAT_EVENT
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			l_rows := active_db.query_sql_with (Select_event_sql + " WHERE id = ?", <<a_id>>)
			if not l_rows.is_empty then
				Result := event_of_row (l_rows.first)
			end
		end

	events_since (a_room_id, a_since_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			l_rows := active_db.query_sql_with (Select_event_sql + " WHERE room_id = ? AND id > ? ORDER BY id LIMIT ?",
				<<a_room_id, a_since_id, a_limit>>)
			create Result.make (l_rows.count)
			across 1 |..| l_rows.count as i loop
				Result.extend (event_of_row (l_rows [i]))
			end
		end

	events_before (a_room_id, a_before_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
		local
			l_rows: SIMPLE_SQL_RESULT
			i: INTEGER
		do
				-- Newest-first from the SQL, reversed here to ascending.
			l_rows := active_db.query_sql_with (Select_event_sql + " WHERE room_id = ? AND id < ? ORDER BY id DESC LIMIT ?",
				<<a_room_id, a_before_id, a_limit>>)
			create Result.make (l_rows.count)
			from
				i := l_rows.count
			until
				i < 1
			loop
				Result.extend (event_of_row (l_rows [i]))
				i := i - 1
			variant
				i + 1
			end
		end

	count_after (a_room_id, a_since_id: INTEGER_64): INTEGER_64
		do
			Result := scalar_64_with ("SELECT COUNT(*) AS n FROM event WHERE room_id = ? AND id > ?", <<a_room_id, a_since_id>>)
		end

	count_before (a_room_id, a_before_id: INTEGER_64): INTEGER_64
		do
			Result := scalar_64_with ("SELECT COUNT(*) AS n FROM event WHERE room_id = ? AND id < ?", <<a_room_id, a_before_id>>)
		end

feature -- Users

	has_user (a_user_id: INTEGER_64): BOOLEAN
		do
			Result := row_exists ("SELECT 1 AS n FROM user WHERE id = ?", <<a_user_id>>)
		end

	has_username (a_username: READABLE_STRING_8): BOOLEAN
		do
			Result := row_exists ("SELECT 1 AS n FROM user WHERE username = ?", <<a_username>>)
		end

	has_admin: BOOLEAN
		do
			Result := not active_db.run_query ("SELECT 1 AS n FROM user WHERE is_admin = 1 AND is_active = 1 AND is_bot = 0 LIMIT 1").is_empty
		end

	add_user (a_user: CHAT_USER)
		local
			l_db: SIMPLE_SQL_DATABASE
		do
			l_db := active_db
			l_db.begin_transaction
			a_user.set_id (scalar_64 ("SELECT COALESCE(MAX(id), 0) + 1 AS n FROM user"))
			l_db.perform_with ("INSERT INTO user (id, username, display_name, password_hash, is_admin, is_bot, is_active, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
				<<a_user.id, a_user.username, utf8 (a_user.display_name), a_user.password_hash,
				a_user.is_admin, a_user.is_bot, a_user.is_active, iso (a_user.created_at)>>)
			finish (l_db)
		end

	update_user (a_user: CHAT_USER)
		local
			l_db: SIMPLE_SQL_DATABASE
		do
			l_db := active_db
			l_db.perform_with ("UPDATE user SET display_name = ?, password_hash = ?, is_admin = ?, is_bot = ?, is_active = ?, created_at = ? WHERE id = ?",
				<<utf8 (a_user.display_name), a_user.password_hash, a_user.is_admin, a_user.is_bot,
				a_user.is_active, iso (a_user.created_at), a_user.id>>)
			assure_write (l_db)
		end

	user (a_user_id: INTEGER_64): detachable CHAT_USER
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			l_rows := active_db.query_sql_with (Select_user_sql + " WHERE id = ?", <<a_user_id>>)
			if not l_rows.is_empty then
				Result := user_of_row (l_rows.first)
			end
		end

	user_by_username (a_username: READABLE_STRING_8): detachable CHAT_USER
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			l_rows := active_db.query_sql_with (Select_user_sql + " WHERE username = ?", <<a_username>>)
			if not l_rows.is_empty then
				Result := user_of_row (l_rows.first)
			end
		end

	users: ARRAYED_LIST [CHAT_USER]
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			l_rows := active_db.run_query (Select_user_sql + " ORDER BY id")
			create Result.make (l_rows.count)
			across 1 |..| l_rows.count as i loop
				Result.extend (user_of_row (l_rows [i]))
			end
		end

feature -- Rooms and membership

	has_room (a_room_id: INTEGER_64): BOOLEAN
		do
			Result := row_exists ("SELECT 1 AS n FROM room WHERE id = ?", <<a_room_id>>)
		end

	add_room (a_room: CHAT_ROOM)
		local
			l_db: SIMPLE_SQL_DATABASE
		do
			l_db := active_db
			l_db.begin_transaction
			a_room.set_id (scalar_64 ("SELECT COALESCE(MAX(id), 0) + 1 AS n FROM room"))
			l_db.perform_with ("INSERT INTO room (id, name, created_at) VALUES (?, ?, ?)",
				<<a_room.id, utf8 (a_room.name), iso (a_room.created_at)>>)
			finish (l_db)
		end

	room (a_room_id: INTEGER_64): detachable CHAT_ROOM
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			l_rows := active_db.query_sql_with ("SELECT id, name, created_at FROM room WHERE id = ?", <<a_room_id>>)
			if not l_rows.is_empty then
				Result := room_of_row (l_rows.first)
			end
		end

	default_room_id: INTEGER_64
		do
			Result := scalar_64 ("SELECT COALESCE(MIN(id), 0) AS n FROM room")
		end

	default_room: detachable CHAT_ROOM
		do
			if default_room_id > 0 then
				Result := room (default_room_id)
			end
		end

	rooms_of (a_user_id: INTEGER_64): ARRAYED_LIST [CHAT_ROOM]
		local
			l_rows: SIMPLE_SQL_RESULT
		do
				-- rowid order is insertion order, exactly as the oracle walks its list.
			l_rows := active_db.query_sql_with ("SELECT room_id FROM membership WHERE user_id = ? ORDER BY rowid", <<a_user_id>>)
			create Result.make (l_rows.count)
			across 1 |..| l_rows.count as i loop
				if attached room (l_rows [i].integer_64_value ("room_id")) as l_room then
					Result.extend (l_room)
				end
			end
		end

	is_member (a_user_id, a_room_id: INTEGER_64): BOOLEAN
		do
			Result := row_exists ("SELECT 1 AS n FROM membership WHERE user_id = ? AND room_id = ?", <<a_user_id, a_room_id>>)
		end

	membership (a_user_id, a_room_id: INTEGER_64): detachable CHAT_MEMBERSHIP
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			l_rows := active_db.query_sql_with ("SELECT room_id, user_id, role, joined_at FROM membership WHERE user_id = ? AND room_id = ?",
				<<a_user_id, a_room_id>>)
			if not l_rows.is_empty then
				Result := membership_of_row (l_rows.first)
			end
		end

	add_membership (a_membership: CHAT_MEMBERSHIP)
		local
			l_db: SIMPLE_SQL_DATABASE
		do
			l_db := active_db
			l_db.perform_with ("INSERT INTO membership (room_id, user_id, role, joined_at) VALUES (?, ?, ?, ?)",
				<<a_membership.room_id, a_membership.user_id, a_membership.role, iso (a_membership.joined_at)>>)
			assure_write (l_db)
		end

feature -- Attachments

	add_attachment (a_attachment: CHAT_ATTACHMENT)
		local
			l_db: SIMPLE_SQL_DATABASE
		do
			l_db := active_db
			l_db.begin_transaction
			a_attachment.set_id (scalar_64 ("SELECT COALESCE(MAX(id), 0) + 1 AS n FROM attachment"))
			l_db.perform_with ("INSERT INTO attachment (id, uploader_id, original_name, mime, size, sha256, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
				<<a_attachment.id, a_attachment.uploader_id, utf8 (a_attachment.original_name), a_attachment.mime,
				a_attachment.size, a_attachment.sha256, iso (a_attachment.created_at)>>)
			finish (l_db)
		end

	has_attachment (a_attachment_id: INTEGER_64): BOOLEAN
		do
			Result := row_exists ("SELECT 1 AS n FROM attachment WHERE id = ?", <<a_attachment_id>>)
		end

	attachment (a_attachment_id: INTEGER_64): detachable CHAT_ATTACHMENT
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			l_rows := active_db.query_sql_with ("SELECT id, uploader_id, original_name, mime, size, sha256, created_at FROM attachment WHERE id = ?",
				<<a_attachment_id>>)
			if not l_rows.is_empty then
				Result := attachment_of_row (l_rows.first)
			end
		end

	put_attachment_bytes (a_attachment_id: INTEGER_64; a_bytes: SPECIAL [NATURAL_8])
		local
			l_db: SIMPLE_SQL_DATABASE
		do
			l_db := active_db
			l_db.perform_with ("UPDATE attachment SET bytes = ? WHERE id = ?", <<pointer_of (a_bytes), a_attachment_id>>)
			assure_write (l_db)
		end

	attachment_bytes (a_attachment_id: INTEGER_64): detachable SPECIAL [NATURAL_8]
		local
			l_rows: SIMPLE_SQL_RESULT
			i: INTEGER
		do
			l_rows := active_db.query_sql_with ("SELECT bytes FROM attachment WHERE id = ? AND bytes IS NOT NULL", <<a_attachment_id>>)
			if not l_rows.is_empty and then attached l_rows.first.blob_value ("bytes") as l_blob then
				create Result.make_empty (l_blob.count)
				from
					i := 0
				until
					i >= l_blob.count
				loop
					Result.extend (l_blob.read_natural_8 (i))
					i := i + 1
				variant
					l_blob.count - i
				end
			end
		end

	has_attachment_bytes (a_attachment_id: INTEGER_64): BOOLEAN
		do
			Result := row_exists ("SELECT 1 AS n FROM attachment WHERE id = ? AND bytes IS NOT NULL", <<a_attachment_id>>)
		end

feature -- Sessions

	put_session (a_session: CHAT_SESSION)
		local
			l_db: SIMPLE_SQL_DATABASE
		do
			l_db := active_db
			l_db.begin_transaction
			if a_session.id = 0 then
				if attached session_by_hash (a_session.token_hash) as l_existing then
					a_session.set_id (l_existing.id)
				else
					next_session_id := next_session_id + 1
					a_session.set_id (next_session_id)
				end
			end
			if row_exists ("SELECT 1 AS n FROM session WHERE token_hash = ?", <<a_session.token_hash>>) then
				l_db.perform_with ("UPDATE session SET id = ?, user_id = ?, created_at = ?, last_seen_at = ?, expires_at = ?, is_bot_token = ? WHERE token_hash = ?",
					<<a_session.id, a_session.user_id, iso (a_session.created_at), iso (a_session.last_seen_at),
					iso (a_session.expires_at), a_session.is_bot_token, a_session.token_hash>>)
			else
				l_db.perform_with ("INSERT INTO session (id, user_id, token_hash, created_at, last_seen_at, expires_at, is_bot_token) VALUES (?, ?, ?, ?, ?, ?, ?)",
					<<a_session.id, a_session.user_id, a_session.token_hash, iso (a_session.created_at),
					iso (a_session.last_seen_at), iso (a_session.expires_at), a_session.is_bot_token>>)
			end
			finish (l_db)
		end

	session_by_hash (a_token_hash: READABLE_STRING_8): detachable CHAT_SESSION
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			l_rows := active_db.query_sql_with ("SELECT id, user_id, token_hash, created_at, last_seen_at, expires_at, is_bot_token FROM session WHERE token_hash = ?",
				<<a_token_hash>>)
			if not l_rows.is_empty then
				Result := session_of_row (l_rows.first)
			end
		end

	has_session_of (a_user_id: INTEGER_64): BOOLEAN
		do
			Result := row_exists ("SELECT 1 AS n FROM session WHERE user_id = ?", <<a_user_id>>)
		end

	remove_session (a_token_hash: READABLE_STRING_8)
		local
			l_db: SIMPLE_SQL_DATABASE
		do
			l_db := active_db
			l_db.perform_with ("DELETE FROM session WHERE token_hash = ?", <<a_token_hash>>)
			assure_write (l_db)
		end

	remove_sessions_of (a_user_id: INTEGER_64)
		local
			l_db: SIMPLE_SQL_DATABASE
		do
			l_db := active_db
			l_db.perform_with ("DELETE FROM session WHERE user_id = ?", <<a_user_id>>)
			assure_write (l_db)
		end

feature {NONE} -- Row building

	user_of_row (a_row: SIMPLE_SQL_ROW): CHAT_USER
			-- A fresh user from one row.
		do
			create Result.make (a_row.integer_64_value ("id"), a_row.string_value ("username").to_string_8,
				a_row.string_value ("display_name"), a_row.string_value ("password_hash").to_string_8,
				a_row.boolean_value ("is_admin"), a_row.boolean_value ("is_bot"), date_of (a_row.string_value ("created_at")))
			Result.set_active (a_row.boolean_value ("is_active"))
		end

	room_of_row (a_row: SIMPLE_SQL_ROW): CHAT_ROOM
		do
			create Result.make (a_row.integer_64_value ("id"), a_row.string_value ("name"), date_of (a_row.string_value ("created_at")))
		end

	membership_of_row (a_row: SIMPLE_SQL_ROW): CHAT_MEMBERSHIP
		do
			create Result.make (a_row.integer_64_value ("room_id"), a_row.integer_64_value ("user_id"),
				a_row.string_value ("role").to_string_8, date_of (a_row.string_value ("joined_at")))
		end

	attachment_of_row (a_row: SIMPLE_SQL_ROW): CHAT_ATTACHMENT
		do
			create Result.make (a_row.integer_64_value ("id"), a_row.integer_64_value ("uploader_id"),
				a_row.string_value ("original_name"), a_row.string_value ("mime").to_string_8,
				a_row.integer_64_value ("size"), a_row.string_value ("sha256").to_string_8, date_of (a_row.string_value ("created_at")))
		end

	session_of_row (a_row: SIMPLE_SQL_ROW): CHAT_SESSION
		do
			create Result.make (a_row.integer_64_value ("id"), a_row.integer_64_value ("user_id"),
				a_row.string_value ("token_hash").to_string_8, date_of (a_row.string_value ("created_at")),
				date_of (a_row.string_value ("expires_at")), a_row.boolean_value ("is_bot_token"))
			Result.touch (date_of (a_row.string_value ("last_seen_at")))
		end

	event_of_row (a_row: SIMPLE_SQL_ROW): CHAT_EVENT
			-- A fresh event from one row, its attachment re-read from its own table.
		local
			l_attachment: detachable CHAT_ATTACHMENT
		do
			if not a_row.is_null ("attachment_id") then
				l_attachment := attachment (a_row.integer_64_value ("attachment_id"))
			end
			create Result.make (a_row.integer_64_value ("id"), a_row.integer_64_value ("room_id"),
				a_row.integer_64_value ("sender_id"), a_row.string_value ("kind").to_string_8,
				date_of (a_row.string_value ("created_at")), a_row.string_value ("body"),
				l_attachment, payload_of (a_row.string_value ("payload_json")), a_row.boolean_value ("is_bot"))
		end

	payload_of (a_text: STRING_32): SIMPLE_JSON_OBJECT
			-- The payload re-parsed from its stored JSON text.
		do
			if not a_text.is_empty and then attached (create {SIMPLE_JSON}).parse_message (a_text) as l_value and then l_value.is_object then
				Result := l_value.as_object
			else
				create Result.make
			end
		end

feature {NONE} -- SQL plumbing

	db: detachable SIMPLE_SQL_DATABASE
			-- The one connection; attached while open.

	schema: CHAT_SCHEMA

	next_session_id: INTEGER_64
			-- The last session id handed out; seeded from the table at `open'.

	active_db: SIMPLE_SQL_DATABASE
			-- The open connection.
		require
			open: is_open
		do
			check open_means_attached: attached db as l_db then
				Result := l_db
			end
		end

	scalar_64 (a_sql: STRING_8): INTEGER_64
			-- The single INTEGER_64 the aliased column `n' of `a_sql' holds.
		require
			open: is_open
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			l_rows := active_db.run_query (a_sql)
			if not l_rows.is_empty then
				Result := l_rows.first.integer_64_value ("n")
			end
		end

	scalar_64_with (a_sql: STRING_8; a_args: ARRAY [detachable ANY]): INTEGER_64
			-- The single INTEGER_64 the aliased column `n' of `a_sql' holds, bound with `a_args'.
		require
			open: is_open
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			l_rows := active_db.query_sql_with (a_sql, a_args)
			if not l_rows.is_empty then
				Result := l_rows.first.integer_64_value ("n")
			end
		end

	row_exists (a_sql: STRING_8; a_args: ARRAY [detachable ANY]): BOOLEAN
			-- Does `a_sql', bound with `a_args', return any row?
		require
			open: is_open
		do
			Result := not active_db.query_sql_with (a_sql, a_args).is_empty
		end

	finish (a_db: SIMPLE_SQL_DATABASE)
			-- Commit, or roll back and fail loudly when a write failed.
		require
			in_transaction: a_db.is_in_transaction
		local
			l_write_failed: BOOLEAN
		do
			l_write_failed := a_db.error_occurred
			if l_write_failed then
				a_db.rollback
			else
				a_db.commit
			end
			check write_succeeded: not l_write_failed end
		ensure
			out_of_transaction: not a_db.is_in_transaction
		end

	assure_write (a_db: SIMPLE_SQL_DATABASE)
			-- Fail loudly when the last single-statement write failed.
		do
			check write_succeeded: not a_db.error_occurred end
		end

	utf8 (a_text: READABLE_STRING_GENERAL): STRING_8
			-- `a_text' as UTF-8 bytes for a TEXT column.
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text)
		end

	iso (a_when: SIMPLE_DATE_TIME): STRING_8
			-- `a_when' as ISO 8601 text for a TEXT column.
		do
			Result := a_when.to_iso8601
		ensure
			shaped: Result.count = 19
		end

	date_of (a_text: READABLE_STRING_GENERAL): SIMPLE_DATE_TIME
			-- The ISO 8601 `a_text' (YYYY-MM-DDTHH:MM:SS) as a date again,
			-- parsed positionally: {SIMPLE_DATE_TIME}.make_from_iso8601
			-- reads a bare hour 12 as 12 AM, so noon would come back as
			-- midnight.
		require
			shaped: a_text.count = 19
		local
			l_text: STRING_8
		do
			l_text := a_text.to_string_8
			create Result.make (l_text.substring (1, 4).to_integer, l_text.substring (6, 7).to_integer,
				l_text.substring (9, 10).to_integer, l_text.substring (12, 13).to_integer,
				l_text.substring (15, 16).to_integer, l_text.substring (18, 19).to_integer)
		end

	pointer_of (a_bytes: SPECIAL [NATURAL_8]): MANAGED_POINTER
			-- `a_bytes' as a blob argument.
		local
			i: INTEGER
		do
			create Result.make (a_bytes.count)
			from
				i := 0
			until
				i >= a_bytes.count
			loop
				Result.put_natural_8 (a_bytes [i], i)
				i := i + 1
			variant
				a_bytes.count - i
			end
		ensure
			sized: Result.count = a_bytes.count
		end

	file_has_content (a_path: READABLE_STRING_32): BOOLEAN
			-- Does a non-empty file exist at `a_path'?
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			Result := l_file.exists and then l_file.count > 0
		end

	remove_file (a_path: READABLE_STRING_32)
			-- Delete the file at `a_path' when it exists (a stale backup).
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			if l_file.exists then
				l_file.delete
			end
		end

	Insert_event_sql: STRING_8 = "INSERT INTO event (id, room_id, kind, sender_id, created_at, body, attachment_id, payload_json, is_bot) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"

	Select_event_sql: STRING_8 = "SELECT id, room_id, kind, sender_id, created_at, body, attachment_id, payload_json, is_bot FROM event"

	Select_user_sql: STRING_8 = "SELECT id, username, display_name, password_hash, is_admin, is_bot, is_active, created_at FROM user"

invariant
	path_given: not path.is_empty
	session_counter_non_negative: next_session_id >= 0

end
