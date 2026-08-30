note
	description: "[
		Persistence for users, rooms, memberships, events, attachments and
		sessions, behind one contract. Two implementations: SQLite for the
		server, memory for the tests - the memory store is the oracle the
		SQLite store is checked against, and since D5 it has the disk's
		value semantics: it stores and returns copies, so a change to a
		returned object reaches the store only through a command.

		Event ids are strictly increasing across the whole store (DR-001);
		`events_since' is the catch-up primitive every client and every
		participant uses (the doorbell pattern of intent-v2 Q3: the bus only
		says "look", this store is the truth) - and a full page is gap-free.

		Concurrency (D1): the store lives on the API's processor and is
		called by one request at a time; no lock of its own. The schema's
		UNIQUE constraints (user.username, membership (room_id, user_id),
		session.token_hash) back the `fresh_*' preconditions on disk.
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

feature -- Counts

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
			within_ids: Result <= last_event_id
		end

	user_count: INTEGER
		require
			open: is_open
		deferred
		ensure
			non_negative: Result >= 0
		end

	room_count: INTEGER
		require
			open: is_open
		deferred
		ensure
			non_negative: Result >= 0
		end

	session_count: INTEGER
		require
			open: is_open
		deferred
		ensure
			non_negative: Result >= 0
		end

	attachment_count: INTEGER
		require
			open: is_open
		deferred
		ensure
			non_negative: Result >= 0
		end

feature -- Events

	append_event (a_draft: CHAT_EVENT_DRAFT): CHAT_EVENT
			-- Persist `a_draft' as the next event; assigns id and timestamp.
		require
			open: is_open
			room_exists: has_room (a_draft.room_id)
			sender_exists: a_draft.is_system or has_user (a_draft.sender_id)
			bot_flag_truthful: a_draft.is_system or (attached user (a_draft.sender_id) as u and then u.is_bot = a_draft.is_bot_authored)
			attachment_stored: attached a_draft.attachment as a implies has_attachment (a.id)
		deferred
		ensure
			assigned_id: Result.id > 0
			strictly_increasing: Result.id > old last_event_id
			is_last: last_event_id = Result.id
			persisted: attached event (Result.id) as e and then (e.id = Result.id and e.kind.same_string (Result.kind) and e.body.same_string (Result.body))
			one_more: event_count = old event_count + 1
			same_room: Result.room_id = a_draft.room_id
			same_kind: Result.kind.same_string (a_draft.kind)
			same_body: Result.body.same_string (a_draft.body)
			same_author: Result.sender_id = a_draft.sender_id and Result.is_bot_authored = a_draft.is_bot_authored
			same_attachment: (attached Result.attachment as ra) = (attached a_draft.attachment as da) and then
				(attached Result.attachment as ra2 and then attached a_draft.attachment as da2 implies ra2.id = da2.id)
			same_payload: Result.payload.to_json_string.same_string (a_draft.payload.to_json_string)
			users_untouched: user_count = old user_count
			rooms_untouched: room_count = old room_count
		end

	event (a_id: INTEGER_64): detachable CHAT_EVENT
		require
			open: is_open
			positive: a_id > 0
		deferred
		ensure
			right_one: attached Result as e implies e.id = a_id
			within_ids: attached Result implies a_id <= last_event_id
		end

	events_since (a_room_id, a_since_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
			-- Events of `a_room_id' with id > `a_since_id', ascending, at most `a_limit', without gaps.
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
			gapless: Result.count > 0 implies count_after (a_room_id, a_since_id) - count_after (a_room_id, Result.last.id) = Result.count
		end

	events_before (a_room_id, a_before_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
			-- The `a_limit' events of `a_room_id' immediately preceding `a_before_id', ascending (history paging).
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
			newest: Result.count = a_limit.to_integer_64.min (count_before (a_room_id, a_before_id))
			adjacent: Result.count > 0 implies count_before (a_room_id, a_before_id) - count_before (a_room_id, Result.first.id) = Result.count
		end

	count_after (a_room_id, a_since_id: INTEGER_64): INTEGER_64
			-- How many events of `a_room_id' have id > `a_since_id'.
		require
			open: is_open
			room_exists: has_room (a_room_id)
			since_non_negative: a_since_id >= 0
		deferred
		ensure
			non_negative: Result >= 0
			zero_iff_none: (Result = 0) = events_since (a_room_id, a_since_id, 1).is_empty
		end

	count_before (a_room_id, a_before_id: INTEGER_64): INTEGER_64
			-- How many events of `a_room_id' have id < `a_before_id'.
		require
			open: is_open
			room_exists: has_room (a_room_id)
			before_positive: a_before_id > 0
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

	has_admin: BOOLEAN
			-- Is there at least one active person who is an admin?
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
			one_more_user: user_count = old user_count + 1
			events_untouched: last_event_id = old last_event_id and event_count = old event_count
			rooms_untouched: room_count = old room_count
		end

	update_user (a_user: CHAT_USER)
			-- Persist `a_user's display name, hash, flags and activity; the username is immutable.
		require
			open: is_open
			stored: a_user.is_stored and has_user (a_user.id)
			same_username: attached user (a_user.id) as u and then u.username.same_string (a_user.username)
		deferred
		ensure
			persisted: attached user (a_user.id) as u and then (u.is_active = a_user.is_active and u.password_hash.same_string (a_user.password_hash)
				and u.display_name.same_string (a_user.display_name) and u.is_admin = a_user.is_admin)
			users_untouched: user_count = old user_count
			events_untouched: last_event_id = old last_event_id and event_count = old event_count
		end

	user (a_user_id: INTEGER_64): detachable CHAT_USER
			-- A copy of the stored user, or Void.
		require
			open: is_open
		deferred
		ensure
			right_one: attached Result as u implies u.id = a_user_id
			consistent: (Result /= Void) = has_user (a_user_id)
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
			-- Copies of every stored user.
		require
			open: is_open
		deferred
		ensure
			complete: Result.count = user_count
			each_stored: across Result as u all has_user (u.id) end
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
			one_more_room: room_count = old room_count + 1
			first_room_is_default: (old room_count = 0) implies default_room_id = a_room.id
			events_untouched: last_event_id = old last_event_id and event_count = old event_count
			users_untouched: user_count = old user_count
		end

	room (a_room_id: INTEGER_64): detachable CHAT_ROOM
		require
			open: is_open
		deferred
		ensure
			right_one: attached Result as r implies r.id = a_room_id
			consistent: (Result /= Void) = has_room (a_room_id)
		end

	default_room_id: INTEGER_64
			-- The room every new member joins; 0 while there is no room.
		require
			open: is_open
		deferred
		ensure
			non_negative: Result >= 0
			exists_when_set: Result > 0 implies has_room (Result)
			set_when_any: room_count > 0 implies Result > 0
		end

	default_room: detachable CHAT_ROOM
		require
			open: is_open
		deferred
		ensure
			consistent: (Result /= Void) = (default_room_id > 0)
			right_one: attached Result as r implies r.id = default_room_id
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

	membership (a_user_id, a_room_id: INTEGER_64): detachable CHAT_MEMBERSHIP
			-- A copy of the membership, with its role.
		require
			open: is_open
		deferred
		ensure
			consistent: (Result /= Void) = is_member (a_user_id, a_room_id)
			right_one: attached Result as m implies (m.user_id = a_user_id and m.room_id = a_room_id)
		end

	add_membership (a_membership: CHAT_MEMBERSHIP)
		require
			open: is_open
			room_exists: has_room (a_membership.room_id)
			user_exists: has_user (a_membership.user_id)
			not_already: not is_member (a_membership.user_id, a_membership.room_id)
		deferred
		ensure
			member: is_member (a_membership.user_id, a_membership.room_id)
			role_kept: attached membership (a_membership.user_id, a_membership.room_id) as m and then m.role.same_string (a_membership.role)
			events_untouched: last_event_id = old last_event_id and event_count = old event_count
			users_untouched: user_count = old user_count
			rooms_untouched: room_count = old room_count
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
			findable: has_attachment (a_attachment.id)
			one_more: attachment_count = old attachment_count + 1
			events_untouched: last_event_id = old last_event_id and event_count = old event_count
		end

	has_attachment (a_attachment_id: INTEGER_64): BOOLEAN
		require
			open: is_open
		deferred
		end

	attachment (a_attachment_id: INTEGER_64): detachable CHAT_ATTACHMENT
		require
			open: is_open
		deferred
		ensure
			right_one: attached Result as a implies a.id = a_attachment_id
			consistent: (Result /= Void) = has_attachment (a_attachment_id)
		end

feature -- Sessions

	put_session (a_session: CHAT_SESSION)
			-- Store `a_session' (assigning its id when new); an existing hash is updated in place.
		require
			open: is_open
			user_exists: has_user (a_session.user_id)
			kind_matches: attached user (a_session.user_id) as u and then u.is_bot = a_session.is_bot_token
			same_owner: attached session_by_hash (a_session.token_hash) as s implies s.user_id = a_session.user_id
		deferred
		ensure
			stored: a_session.id > 0
			findable: attached session_by_hash (a_session.token_hash)
			bounded_growth: session_count <= old session_count + 1
			events_untouched: last_event_id = old last_event_id and event_count = old event_count
		end

	session_by_hash (a_token_hash: READABLE_STRING_8): detachable CHAT_SESSION
		require
			open: is_open
			hash_shape: a_token_hash.count = 64
		deferred
		ensure
			right_one: attached Result as s implies s.token_hash.same_string (a_token_hash)
		end

	has_session_of (a_user_id: INTEGER_64): BOOLEAN
			-- Does any session (or bot token) of `a_user_id' exist?
		require
			open: is_open
		deferred
		end

	remove_session (a_token_hash: READABLE_STRING_8)
		require
			open: is_open
			hash_shape: a_token_hash.count = 64
		deferred
		ensure
			gone: session_by_hash (a_token_hash) = Void
			at_most_one: session_count >= old session_count - 1
			events_untouched: last_event_id = old last_event_id and event_count = old event_count
		end

	remove_sessions_of (a_user_id: INTEGER_64)
			-- Revoke every session and token of a user.
		require
			open: is_open
		deferred
		ensure
			none_left: not has_session_of (a_user_id)
			events_untouched: last_event_id = old last_event_id and event_count = old event_count
			users_untouched: user_count = old user_count
		end

invariant
	count_within_ids: is_open implies event_count <= last_event_id

end
