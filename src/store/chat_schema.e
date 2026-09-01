note
	description: "[
		The SQLite schema, versioned. Forward-only numbered migrations, each
		in a transaction, after a backup; `schema_version' row records where
		a database stands (intent-v2 Q10).

		v1: user, room, membership, event (id INTEGER PRIMARY KEY, room_id,
		kind, sender_id, created_at, body, attachment_id, payload_json,
		is_bot), attachment (with a nullable BLOB carrying the file's
		bytes), session (token_hash UNIQUE, is_bot_token); UNIQUE on
		user.username and membership (room_id, user_id) so the store's
		`fresh_*' preconditions are also facts on disk. Every UNIQUE
		constraint carries its own index - username, token_hash and the
		membership pair are the hot lookups - and the explicit index
		event (room_id, id) serves the paging queries. Event ids are
		assigned by the store, never AUTOINCREMENT, so a refused insert
		burns nothing (DR-001). A database ahead of `Current_version' is
		refused by the store's `open', never migrated down.
	]"
	author: "Larry Rix"

class
	CHAT_SCHEMA

create
	make

feature {NONE} -- Initialization

	make
		do
		end

feature -- Access

	Current_version: INTEGER = 1

feature -- Basic operations

	version_of (a_db: SIMPLE_SQL_DATABASE): INTEGER
			-- The version recorded in `a_db'; 0 for an empty database.
		require
			open: a_db.is_open
		local
			l_rows: SIMPLE_SQL_RESULT
		do
			l_rows := a_db.run_query ("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'schema_version'")
			if not l_rows.is_empty then
				l_rows := a_db.run_query ("SELECT version AS n FROM schema_version LIMIT 1")
				if not l_rows.is_empty then
					Result := l_rows.first.integer_value ("n").max (0)
				end
			end
		ensure
			non_negative: Result >= 0
		end

	migrate (a_db: SIMPLE_SQL_DATABASE)
			-- Bring `a_db' from `version_of' to `Current_version', one
			-- numbered step at a time, each in its own transaction. A step
			-- that fails leaves the previous version intact.
		require
			open: a_db.is_open
			not_ahead: version_of (a_db) <= Current_version
		local
			l_version: INTEGER
			l_step_failed: BOOLEAN
		do
			from
				l_version := version_of (a_db)
			until
				l_version >= Current_version
			loop
				a_db.begin_transaction
				inspect l_version + 1
				when 1 then
					create_v1 (a_db)
				end
				l_step_failed := a_db.error_occurred
				if not l_step_failed then
					record_version (a_db, l_version + 1)
					l_step_failed := a_db.error_occurred
				end
				if l_step_failed then
						-- The transaction unwinds whole: the previous version stays intact.
					a_db.rollback
				else
					a_db.commit
				end
				check migration_step_succeeded: not l_step_failed end
				l_version := l_version + 1
			variant
				Current_version - l_version + 1
			end
		ensure
			at_current_version: version_of (a_db) = Current_version
		end

feature {NONE} -- Steps

	create_v1 (a_db: SIMPLE_SQL_DATABASE)
			-- The version 1 tables and indexes; stops at the first failed
			-- statement so the caller sees the error state.
		require
			open: a_db.is_open
			mid_transaction: a_db.is_in_transaction
		local
			l_statements: ARRAY [STRING_8]
			i: INTEGER
		do
			l_statements := v1_statements
			from
				i := l_statements.lower
			until
				i > l_statements.upper or a_db.error_occurred
			loop
				a_db.perform (l_statements [i])
				i := i + 1
			variant
				l_statements.upper - i + 1
			end
		end

	v1_statements: ARRAY [STRING_8]
			-- The DDL of version 1, in execution order.
		do
			Result := <<
				"CREATE TABLE schema_version (version INTEGER NOT NULL)",
				"CREATE TABLE user (id INTEGER PRIMARY KEY, username TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL, password_hash TEXT NOT NULL, is_admin INTEGER NOT NULL, is_bot INTEGER NOT NULL, is_active INTEGER NOT NULL, created_at TEXT NOT NULL)",
				"CREATE TABLE room (id INTEGER PRIMARY KEY, name TEXT NOT NULL, created_at TEXT NOT NULL)",
				"CREATE TABLE membership (room_id INTEGER NOT NULL REFERENCES room (id), user_id INTEGER NOT NULL REFERENCES user (id), role TEXT NOT NULL, joined_at TEXT NOT NULL, UNIQUE (room_id, user_id))",
				"CREATE TABLE event (id INTEGER PRIMARY KEY, room_id INTEGER NOT NULL REFERENCES room (id), kind TEXT NOT NULL, sender_id INTEGER NOT NULL, created_at TEXT NOT NULL, body TEXT NOT NULL, attachment_id INTEGER REFERENCES attachment (id), payload_json TEXT NOT NULL, is_bot INTEGER NOT NULL)",
				"CREATE TABLE attachment (id INTEGER PRIMARY KEY, uploader_id INTEGER NOT NULL REFERENCES user (id), original_name TEXT NOT NULL, mime TEXT NOT NULL, size INTEGER NOT NULL, sha256 TEXT NOT NULL, created_at TEXT NOT NULL, bytes BLOB)",
				"CREATE TABLE session (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES user (id), token_hash TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL, last_seen_at TEXT NOT NULL, expires_at TEXT NOT NULL, is_bot_token INTEGER NOT NULL)",
				"CREATE INDEX idx_event_room_id ON event (room_id, id)"
			>>
		ensure
			statements_given: not Result.is_empty
		end

	record_version (a_db: SIMPLE_SQL_DATABASE; a_version: INTEGER)
			-- Make `a_version' the one recorded row of schema_version.
		require
			open: a_db.is_open
			positive: a_version > 0
		do
			a_db.perform ("DELETE FROM schema_version")
			if not a_db.error_occurred then
				a_db.perform_with ("INSERT INTO schema_version (version) VALUES (?)", <<a_version>>)
			end
		end

end
