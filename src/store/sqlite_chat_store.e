note
	description: "[
		CHAT_STORE over simple_sql: one SQLite file opened in WAL mode, one
		connection, every feature serialized through `lock' so correctness
		never depends on the SQLite build's threading mode (RISK-010).
		Images are files under data/uploads; only their rows live here.
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
			create lock.make
			create schema.make
		ensure
			path_set: path.same_string_general (a_path)
			not_open: not is_open
		end

feature -- Access

	path: STRING_32

feature -- Status report

	is_open: BOOLEAN
		do
			Result := attached db as d and then d.is_open
		end

feature -- Lifecycle

	open
		do
			-- Implementation in Phase 4: create db.make (path); WAL; schema.migrate (db)
		end

	close
		do
			-- Implementation in Phase 4
		end

	schema_version: INTEGER
		do
			-- Implementation in Phase 4
		end

feature -- Events

	last_event_id: INTEGER_64
		do
			-- Implementation in Phase 4
		end

	event_count: INTEGER_64
		do
			-- Implementation in Phase 4
		end

	append_event (a_draft: CHAT_EVENT_DRAFT): CHAT_EVENT
		local
			l_now: SIMPLE_DATE_TIME
		do
			-- Implementation in Phase 4 (INSERT under `lock', read back last_insert_row_id)
			create l_now.make_now
			create Result.make (last_event_id + 1, a_draft.room_id, a_draft.sender_id, a_draft.kind, l_now,
				a_draft.body, a_draft.attachment, a_draft.payload, a_draft.is_bot_authored)
		end

	event (a_id: INTEGER_64): detachable CHAT_EVENT
		do
			-- Implementation in Phase 4
		end

	events_since (a_room_id, a_since_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
		do
			create Result.make (0)
			-- Implementation in Phase 4
		end

	events_before (a_room_id, a_before_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
		do
			create Result.make (0)
			-- Implementation in Phase 4
		end

	count_after (a_room_id, a_since_id: INTEGER_64): INTEGER_64
		do
			-- Implementation in Phase 4
		end

feature -- Users

	has_user (a_user_id: INTEGER_64): BOOLEAN
		do
			-- Implementation in Phase 4
		end

	has_username (a_username: READABLE_STRING_8): BOOLEAN
		do
			-- Implementation in Phase 4
		end

	add_user (a_user: CHAT_USER)
		do
			-- Implementation in Phase 4
		end

	update_user (a_user: CHAT_USER)
		do
			-- Implementation in Phase 4
		end

	user (a_user_id: INTEGER_64): detachable CHAT_USER
		do
			-- Implementation in Phase 4
		end

	user_by_username (a_username: READABLE_STRING_8): detachable CHAT_USER
		do
			-- Implementation in Phase 4
		end

	users: ARRAYED_LIST [CHAT_USER]
		do
			create Result.make (0)
			-- Implementation in Phase 4
		end

feature -- Rooms and membership

	has_room (a_room_id: INTEGER_64): BOOLEAN
		do
			-- Implementation in Phase 4
		end

	add_room (a_room: CHAT_ROOM)
		do
			-- Implementation in Phase 4
		end

	room (a_room_id: INTEGER_64): detachable CHAT_ROOM
		do
			-- Implementation in Phase 4
		end

	default_room: detachable CHAT_ROOM
		do
			-- Implementation in Phase 4
		end

	rooms_of (a_user_id: INTEGER_64): ARRAYED_LIST [CHAT_ROOM]
		do
			create Result.make (0)
			-- Implementation in Phase 4
		end

	is_member (a_user_id, a_room_id: INTEGER_64): BOOLEAN
		do
			-- Implementation in Phase 4
		end

	add_membership (a_membership: CHAT_MEMBERSHIP)
		do
			-- Implementation in Phase 4
		end

feature -- Attachments

	add_attachment (a_attachment: CHAT_ATTACHMENT)
		do
			-- Implementation in Phase 4
		end

	attachment (a_attachment_id: INTEGER_64): detachable CHAT_ATTACHMENT
		do
			-- Implementation in Phase 4
		end

feature -- Sessions

	put_session (a_session: CHAT_SESSION)
		do
			-- Implementation in Phase 4
		end

	session_by_hash (a_token_hash: READABLE_STRING_8): detachable CHAT_SESSION
		do
			-- Implementation in Phase 4
		end

	remove_session (a_token_hash: READABLE_STRING_8)
		do
			-- Implementation in Phase 4
		end

	has_session_of (a_user_id: INTEGER_64): BOOLEAN
		do
			-- Implementation in Phase 4 (SELECT 1 FROM session WHERE user_id = ?)
		end

	remove_sessions_of (a_user_id: INTEGER_64)
		do
			-- Implementation in Phase 4
		end

feature {NONE} -- Implementation

	db: detachable SIMPLE_SQL_DATABASE
			-- The one connection; attached while open.

	lock: MUTEX
			-- Serializes every feature (innermost lock in the system).

	schema: CHAT_SCHEMA

invariant
	lock_attached: lock /= Void
	path_given: not path.is_empty

end
