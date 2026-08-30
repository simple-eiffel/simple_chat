note
	description: "[
		The SQLite schema, versioned. Forward-only numbered migrations, each
		in a transaction, after a backup; `schema_version' row records where
		a database stands (intent-v2 Q10).

		v1: user, room, membership, event (id INTEGER PRIMARY KEY AUTOINCREMENT,
		room_id, kind, sender_id, created_at, body, attachment_id,
		payload_json, is_bot), attachment, session (token_hash UNIQUE,
		is_bot_token); indexes event(room_id, id), session(token_hash).
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
		do
			-- Implementation in Phase 4
		ensure
			non_negative: Result >= 0
			never_ahead: Result <= Current_version
		end

	migrate (a_db: SIMPLE_SQL_DATABASE)
			-- Bring `a_db' from `version_of' to `Current_version', one
			-- numbered step at a time, each in its own transaction. A step
			-- that fails leaves the previous version intact.
		require
			open: a_db.is_open
			not_ahead: version_of (a_db) <= Current_version
		do
			-- Implementation in Phase 4
		ensure
			at_current_version: version_of (a_db) = Current_version
		end

end
