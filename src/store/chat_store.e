note
	description: "[
		Persistence for users, rooms, memberships, events, attachments and
		sessions, behind one contract. Two implementations: SQLite for the
		server, memory for the tests - the memory store is the oracle the
		SQLite store is checked against.

		Event ids are strictly increasing across the whole store (DR-001);
		`events_since' is the catch-up primitive every client and every
		participant uses (the doorbell pattern of intent-v2 Q3: the bus only
		says "look", this store is the truth).

		Every implementation serializes its own calls; callers never need a
		lock of their own (lock order: store < limiter < bus).
	]"
	author: "Larry Rix"

deferred class
	CHAT_STORE

feature -- Status report

	is_open: BOOLEAN
		deferred
		end

feature -- Lifecycle

	open
			-- Open (creating if absent) and bring the schema to the current version.
		require
			not_open: not is_open
		deferred
		ensure
			open: is_open
			schema_current: schema_version = {CHAT_SCHEMA}.Current_version
		end

	close
		require
			open: is_open
		deferred
		ensure
			closed: not is_open
		end

	schema_version: INTEGER
		require
			open: is_open
		deferred
		ensure
			non_negative: Result >= 0
		end

feature -- Events

	last_event_id: INTEGER_64
			-- The highest id ever assigned; 0 when empty.
		require
			open: is_open
		deferred
		ensure
			non_negative: Result >= 0
		end

	event_count: INTEGER_64
		require
			open: is_open
		deferred
		ensure
			non_negative: Result >= 0
		end

	append_event (a_draft: CHAT_EVENT_DRAFT): CHAT_EVENT
			-- Persist `a_draft' as the next event; assigns id and timestamp.
		require
			open: is_open
			room_exists: has_room (a_draft.room_id)
			sender_exists: a_draft.kind.same_string ({CHAT_EVENT_KINDS}.Kind_system) or has_user (a_draft.sender_id)
		deferred
		ensure
			assigned_id: Result.id > 0
			strictly_increasing: Result.id > old last_event_id
			is_last: last_event_id = Result.id
			persisted: attached event (Result.id) as e and then e.id = Result.id
			one_more: event_count = old event_count + 1
			same_room: Result.room_id = a_draft.room_id
			same_body: Result.body.same_string (a_draft.body)
			same_author: Result.sender_id = a_draft.sender_id and Result.is_bot_authored = a_draft.is_bot_authored
		end

	event (a_id: INTEGER_64): detachable CHAT_EVENT
		require
			open: is_open
			positive: a_id > 0
		deferred
		ensure
			right_one: attached Result as e implies e.id = a_id
		end

	events_since (a_room_id, a_since_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
			-- Events of `a_room_id' with id > `a_since_id', ascending, at most `a_limit'.
		require
			open: is_open
			room_exists: has_room (a_room_id)
			since_non_negative: a_since_id >= 0
			limit_positive: a_limit > 0
		deferred
		ensure
			bounded: Result.count <= a_limit
			all_after: across Result as e all e.id > a_since_id and e.room_id = a_room_id end
			ascending: across 1 |..| (Result.count - 1) as i all Result [i].id < Result [i + 1].id end
			contiguous: Result.count < a_limit implies Result.count = count_after (a_room_id, a_since_id)
		end

	events_before (a_room_id, a_before_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
			-- The `a_limit' events of `a_room_id' with id < `a_before_id', ascending (history paging).
		require
			open: is_open
			room_exists: has_room (a_room_id)
			before_positive: a_before_id > 0
			limit_positive: a_limit > 0
		deferred
		ensure
			bounded: Result.count <= a_limit
			all_before: across Result as e all e.id < a_before_id and e.room_id = a_room_id end
			ascending: across 1 |..| (Result.count - 1) as i all Result [i].id < Result [i + 1].id end
		end

	count_after (a_room_id, a_since_id: INTEGER_64): INTEGER_64
		require
			open: is_open
			room_exists: has_room (a_room_id)
		deferred
		ensure
			non_negative: Result >= 0
		end

feature -- Users

	has_user (a_user_id: INTEGER_64): BOOLEAN
		require
			open: is_open
		deferred
		end

	has_username (a_username: READABLE_STRING_8): BOOLEAN
		require
			open: is_open
		deferred
		end

	add_user (a_user: CHAT_USER)
			-- Store `a_user', assigning its id.
		require
			open: is_open
			not_yet_stored: not a_user.is_stored
			fresh_username: not has_username (a_user.username)
		deferred
		ensure
			stored: a_user.is_stored
			findable: has_user (a_user.id) and has_username (a_user.username)
		end

	update_user (a_user: CHAT_USER)
		require
			open: is_open
			stored: a_user.is_stored and has_user (a_user.id)
		deferred
		ensure
			still_there: has_user (a_user.id)
		end

	user (a_user_id: INTEGER_64): detachable CHAT_USER
		require
			open: is_open
		deferred
		ensure
			right_one: attached Result as u implies u.id = a_user_id
		end

	user_by_username (a_username: READABLE_STRING_8): detachable CHAT_USER
		require
			open: is_open
		deferred
		ensure
			right_one: attached Result as u implies u.username.same_string (a_username)
			consistent: (Result /= Void) = has_username (a_username)
		end

	users: ARRAYED_LIST [CHAT_USER]
		require
			open: is_open
		deferred
		end

feature -- Rooms and membership

	has_room (a_room_id: INTEGER_64): BOOLEAN
		require
			open: is_open
		deferred
		end

	add_room (a_room: CHAT_ROOM)
		require
			open: is_open
			not_yet_stored: not a_room.is_stored
		deferred
		ensure
			stored: a_room.is_stored and has_room (a_room.id)
		end

	room (a_room_id: INTEGER_64): detachable CHAT_ROOM
		require
			open: is_open
		deferred
		ensure
			right_one: attached Result as r implies r.id = a_room_id
		end

	default_room: detachable CHAT_ROOM
			-- The room every new member joins.
		require
			open: is_open
		deferred
		end

	rooms_of (a_user_id: INTEGER_64): ARRAYED_LIST [CHAT_ROOM]
		require
			open: is_open
		deferred
		ensure
			all_members: across Result as r all is_member (a_user_id, r.id) end
		end

	is_member (a_user_id, a_room_id: INTEGER_64): BOOLEAN
		require
			open: is_open
		deferred
		end

	add_membership (a_membership: CHAT_MEMBERSHIP)
		require
			open: is_open
			room_exists: has_room (a_membership.room_id)
			user_exists: has_user (a_membership.user_id)
		deferred
		ensure
			member: is_member (a_membership.user_id, a_membership.room_id)
		end

feature -- Attachments

	add_attachment (a_attachment: CHAT_ATTACHMENT)
		require
			open: is_open
			not_yet_stored: a_attachment.id = 0
			uploader_exists: has_user (a_attachment.uploader_id)
		deferred
		ensure
			stored: a_attachment.id > 0
			findable: attached attachment (a_attachment.id)
		end

	attachment (a_attachment_id: INTEGER_64): detachable CHAT_ATTACHMENT
		require
			open: is_open
		deferred
		ensure
			right_one: attached Result as a implies a.id = a_attachment_id
		end

feature -- Sessions

	put_session (a_session: CHAT_SESSION)
			-- Store `a_session' (assigning its id when new).
		require
			open: is_open
			user_exists: has_user (a_session.user_id)
		deferred
		ensure
			stored: a_session.id > 0
			findable: attached session_by_hash (a_session.token_hash)
		end

	session_by_hash (a_token_hash: READABLE_STRING_8): detachable CHAT_SESSION
		require
			open: is_open
			hash_shape: a_token_hash.count = 64
		deferred
		ensure
			right_one: attached Result as s implies s.token_hash.same_string (a_token_hash)
		end

	remove_session (a_token_hash: READABLE_STRING_8)
		require
			open: is_open
			hash_shape: a_token_hash.count = 64
		deferred
		ensure
			gone: session_by_hash (a_token_hash) = Void
		end

	remove_sessions_of (a_user_id: INTEGER_64)
			-- Revoke every session and token of a user.
		require
			open: is_open
		deferred
		end

end
