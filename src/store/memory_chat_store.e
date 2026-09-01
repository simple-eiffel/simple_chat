note
	description: "[
		CHAT_STORE in memory: the test oracle, implemented in full. Every
		collection has a mathematical model, so the commands state what
		changed and - through frame conditions - what did not; the SQLite
		store is checked against this one feature for feature.

		Value semantics (D5): what goes in is copied, what comes out is a
		copy, exactly as a database behaves. A caller that changes a
		returned user without `update_user' changes nothing here - which is
		how the oracle catches a service that forgets to persist. Since
		Issue 23 the copies are `duplicate's - fresh strings, a fresh
		payload - so even mutating a returned object's TEXT reaches nothing
		here, and the domain's value-based `is_equal' keeps every MML model
		clause true across those copies.
	]"
	author: "Larry Rix"

class
	MEMORY_CHAT_STORE

inherit
	CHAT_STORE

create
	make

feature {NONE} -- Initialization

	make
		do
			create events.make (64)
			create users_table.make (16)
			create rooms.make (4)
			create memberships.make (16)
			create attachments.make (16)
			create attachment_bytes_table.make (8)
			create sessions.make (16)
		ensure
			not_open: not is_open
			empty: events.is_empty
			no_models: events_model.is_empty and users_model.is_empty and rooms_model.is_empty
				and membership_model.is_empty and attachments_model.is_empty and sessions_model.is_empty
		end

feature -- Model Queries (for MML postconditions)

	events_model: MML_SEQUENCE [CHAT_EVENT]
			-- Every event, in id order.
		do
			create Result
			across events as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = events.count
		end

	users_model: MML_MAP [INTEGER_64, CHAT_USER]
			-- Stored users by id.
		do
			create Result
			across users_table as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = users_table.count
		end

	rooms_model: MML_MAP [INTEGER_64, CHAT_ROOM]
		do
			create Result
			across rooms as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = rooms.count
		end

	membership_model: MML_RELATION [INTEGER_64, INTEGER_64]
			-- user id -> room id, many to many (one pair per membership: `unique_pairs').
		do
			create Result
			across memberships as ic loop
				Result := Result.extended (ic.user_id, ic.room_id)
			end
		ensure
			same_count: Result.count = memberships.count
		end

	attachments_model: MML_MAP [INTEGER_64, CHAT_ATTACHMENT]
		do
			create Result
			across attachments as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = attachments.count
		end

	sessions_model: MML_MAP [STRING_8, CHAT_SESSION]
			-- Sessions by token hash.
		do
			create Result
			across sessions as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = sessions.count
		end

feature -- Status report

	is_open: BOOLEAN

	last_open_error: detachable CHAT_ERROR
			-- Never attached: the memory store always opens (M-D8).

feature -- Lifecycle

	open
		do
			is_open := True
		ensure then
			always_opens: is_open and last_open_error = Void
			nothing_else_changed: events_model |=| old events_model and users_model |=| old users_model
				and sessions_model |=| old sessions_model
		end

	close
		do
			is_open := False
		ensure then
			nothing_lost: events_model |=| old events_model and users_model |=| old users_model
				and sessions_model |=| old sessions_model
		end

	schema_version: INTEGER
		do
			Result := {CHAT_SCHEMA}.Current_version
		end

feature -- Counts

	last_event_id: INTEGER_64

	event_count: INTEGER_64
		do
			Result := events.count
		end

	user_count: INTEGER
		do
			Result := users_table.count
		end

	room_count: INTEGER
		do
			Result := rooms.count
		end

	session_count: INTEGER
		do
			Result := sessions.count
		end

	attachment_count: INTEGER
		do
			Result := attachments.count
		end

feature -- Events

	append_event (a_draft: CHAT_EVENT_DRAFT): CHAT_EVENT
		local
			l_now: SIMPLE_DATE_TIME
		do
			create l_now.make_now
			create Result.make (last_event_id + 1, a_draft.room_id, a_draft.sender_id, a_draft.kind, l_now,
				a_draft.body, a_draft.attachment, a_draft.payload, a_draft.is_bot_authored)
			events.extend (Result.duplicate)
			last_event_id := Result.id
		ensure then
			appended_at_end: events_model |=| ((old events_model) & Result)
			users_unchanged: users_model |=| old users_model
			rooms_unchanged: rooms_model |=| old rooms_model
			memberships_unchanged: membership_model |=| old membership_model
			attachments_unchanged: attachments_model |=| old attachments_model
			sessions_unchanged: sessions_model |=| old sessions_model
			next_id: Result.id = old last_event_id + 1
		end

	event (a_id: INTEGER_64): detachable CHAT_EVENT
		do
			across events as ic until Result /= Void loop
				if ic.id = a_id then
					Result := ic.duplicate
				end
			end
		ensure then
			from_model: attached Result as e implies events_model.has (e)
		end

	events_since (a_room_id, a_since_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
		do
			create Result.make (a_limit.min (16))
			across events as ic until Result.count >= a_limit loop
				if ic.room_id = a_room_id and ic.id > a_since_id then
					Result.extend (ic.duplicate)
				end
			end
		ensure then
			from_model: across Result as e all events_model.has (e) end
		end

	events_before (a_room_id, a_before_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
		local
			l_all: ARRAYED_LIST [CHAT_EVENT]
			i: INTEGER
		do
			create l_all.make (16)
			across events as ic loop
				if ic.room_id = a_room_id and ic.id < a_before_id then
					l_all.extend (ic)
				end
			end
			create Result.make (a_limit.min (16))
			from
				i := (l_all.count - a_limit + 1).max (1)
			until
				i > l_all.count
			loop
				Result.extend (l_all [i].duplicate)
				i := i + 1
			end
		ensure then
			from_model: across Result as e all events_model.has (e) end
		end

	count_after (a_room_id, a_since_id: INTEGER_64): INTEGER_64
		do
			across events as ic loop
				if ic.room_id = a_room_id and ic.id > a_since_id then
					Result := Result + 1
				end
			end
		end

	count_before (a_room_id, a_before_id: INTEGER_64): INTEGER_64
		do
			across events as ic loop
				if ic.room_id = a_room_id and ic.id < a_before_id then
					Result := Result + 1
				end
			end
		end

feature -- Users

	has_user (a_user_id: INTEGER_64): BOOLEAN
		do
			Result := users_table.has (a_user_id)
		ensure then
			definition: Result = users_model.domain.has (a_user_id)
		end

	has_username (a_username: READABLE_STRING_8): BOOLEAN
		do
			Result := across users_table as ic some ic.username.same_string (a_username) end
		end

	has_admin: BOOLEAN
		do
			Result := across users_table as ic some (ic.is_admin and ic.is_active and not ic.is_bot) end
		end

	add_user (a_user: CHAT_USER)
		do
			next_user_id := next_user_id + 1
			a_user.set_id (next_user_id)
			users_table.force (a_user.duplicate, a_user.id)
		ensure then
			added: users_model |=| (old users_model).updated (a_user.id, a_user)
			events_unchanged: events_model |=| old events_model
			rooms_unchanged: rooms_model |=| old rooms_model
			memberships_unchanged: membership_model |=| old membership_model
			sessions_unchanged: sessions_model |=| old sessions_model
		end

	update_user (a_user: CHAT_USER)
		do
			users_table.force (a_user.duplicate, a_user.id)
		ensure then
			replaced: users_model |=| (old users_model).updated (a_user.id, a_user)
			same_users: users_model.domain |=| (old users_model).domain
			events_unchanged: events_model |=| old events_model
			sessions_unchanged: sessions_model |=| old sessions_model
		end

	user (a_user_id: INTEGER_64): detachable CHAT_USER
		do
			if attached users_table [a_user_id] as u then
				Result := u.duplicate
			end
		ensure then
			from_model: attached Result as u implies users_model.domain.has (a_user_id)
			a_copy: attached Result as u2 implies u2 /= users_table [a_user_id]
		end

	user_by_username (a_username: READABLE_STRING_8): detachable CHAT_USER
		do
			across users_table as ic until Result /= Void loop
				if ic.username.same_string (a_username) then
					Result := ic.duplicate
				end
			end
		end

	users: ARRAYED_LIST [CHAT_USER]
		do
			create Result.make (users_table.count)
			across users_table as ic loop
				Result.extend (ic.duplicate)
			end
		ensure then
			all_of_them: Result.count = users_model.count
		end

feature -- Rooms and membership

	has_room (a_room_id: INTEGER_64): BOOLEAN
		do
			Result := rooms.has (a_room_id)
		ensure then
			definition: Result = rooms_model.domain.has (a_room_id)
		end

	add_room (a_room: CHAT_ROOM)
		do
			next_room_id := next_room_id + 1
			a_room.set_id (next_room_id)
			rooms.force (a_room.duplicate, a_room.id)
			if default_room_id = 0 then
				default_room_id := a_room.id
			end
		ensure then
			added: rooms_model |=| (old rooms_model).updated (a_room.id, a_room)
			users_unchanged: users_model |=| old users_model
			events_unchanged: events_model |=| old events_model
			memberships_unchanged: membership_model |=| old membership_model
		end

	room (a_room_id: INTEGER_64): detachable CHAT_ROOM
		do
			if attached rooms [a_room_id] as r then
				Result := r.duplicate
			end
		ensure then
			from_model: attached Result as r implies rooms_model.domain.has (a_room_id)
		end

	default_room_id: INTEGER_64

	default_room: detachable CHAT_ROOM
		do
			if default_room_id > 0 then
				Result := room (default_room_id)
			end
		end

	rooms_of (a_user_id: INTEGER_64): ARRAYED_LIST [CHAT_ROOM]
		do
			create Result.make (4)
			across memberships as ic loop
				if ic.user_id = a_user_id and then attached room (ic.room_id) as r then
					Result.extend (r)
				end
			end
		ensure then
			exactly_the_image: Result.count = membership_model.image_of (a_user_id).count
		end

	is_member (a_user_id, a_room_id: INTEGER_64): BOOLEAN
		do
			Result := across memberships as ic some (ic.user_id = a_user_id and ic.room_id = a_room_id) end
		ensure then
			definition: Result = membership_model.has (a_user_id, a_room_id)
		end

	membership (a_user_id, a_room_id: INTEGER_64): detachable CHAT_MEMBERSHIP
		do
			across memberships as ic until Result /= Void loop
				if ic.user_id = a_user_id and ic.room_id = a_room_id then
					Result := ic.duplicate
				end
			end
		end

	add_membership (a_membership: CHAT_MEMBERSHIP)
		do
			memberships.extend (a_membership.duplicate)
		ensure then
			related: membership_model |=| (old membership_model).extended (a_membership.user_id, a_membership.room_id)
			one_more: memberships.count = old memberships.count + 1
			users_unchanged: users_model |=| old users_model
			rooms_unchanged: rooms_model |=| old rooms_model
			events_unchanged: events_model |=| old events_model
		end

feature -- Attachments

	add_attachment (a_attachment: CHAT_ATTACHMENT)
		do
			next_attachment_id := next_attachment_id + 1
			a_attachment.set_id (next_attachment_id)
			attachments.force (a_attachment.duplicate, a_attachment.id)
		ensure then
			added: attachments_model |=| (old attachments_model).updated (a_attachment.id, a_attachment)
			events_unchanged: events_model |=| old events_model
			users_unchanged: users_model |=| old users_model
		end

	has_attachment (a_attachment_id: INTEGER_64): BOOLEAN
		do
			Result := attachments.has (a_attachment_id)
		ensure then
			definition: Result = attachments_model.domain.has (a_attachment_id)
		end

	attachment (a_attachment_id: INTEGER_64): detachable CHAT_ATTACHMENT
		do
			if attached attachments [a_attachment_id] as a then
				Result := a.duplicate
			end
		ensure then
			from_model: attached Result as a implies attachments_model.domain.has (a_attachment_id)
		end

	put_attachment_bytes (a_attachment_id: INTEGER_64; a_bytes: SPECIAL [NATURAL_8])
		do
			attachment_bytes_table.force (copied_bytes (a_bytes), a_attachment_id)
		ensure then
			events_unchanged: events_model |=| old events_model
			users_unchanged: users_model |=| old users_model
			attachments_unchanged: attachments_model |=| old attachments_model
		end

	attachment_bytes (a_attachment_id: INTEGER_64): detachable SPECIAL [NATURAL_8]
		do
			if attached attachment_bytes_table [a_attachment_id] as l_bytes then
				Result := copied_bytes (l_bytes)
			end
		ensure then
			a_copy: attached Result as b implies b /= attachment_bytes_table [a_attachment_id]
		end

	has_attachment_bytes (a_attachment_id: INTEGER_64): BOOLEAN
		do
			Result := attachment_bytes_table.has (a_attachment_id)
		end

feature -- Sessions

	put_session (a_session: CHAT_SESSION)
		local
			l_dup: CHAT_SESSION
		do
			if a_session.id = 0 then
				if attached sessions [a_session.token_hash] as s then
					a_session.set_id (s.id)
				else
					next_session_id := next_session_id + 1
					a_session.set_id (next_session_id)
				end
			end
			l_dup := a_session.duplicate
			sessions.force (l_dup, l_dup.token_hash)
		ensure then
			stored_by_hash: sessions_model |=| (old sessions_model).updated (a_session.token_hash, a_session)
			users_unchanged: users_model |=| old users_model
			events_unchanged: events_model |=| old events_model
		end

	session_by_hash (a_token_hash: READABLE_STRING_8): detachable CHAT_SESSION
		do
			if attached sessions [a_token_hash.to_string_8] as s then
				Result := s.duplicate
			end
		ensure then
			definition: (Result /= Void) = sessions_model.domain.has (a_token_hash.to_string_8)
		end

	has_session_of (a_user_id: INTEGER_64): BOOLEAN
		do
			Result := across sessions as ic some ic.user_id = a_user_id end
		ensure then
			definition: Result = across sessions as ic some ic.user_id = a_user_id end
		end

	remove_session (a_token_hash: READABLE_STRING_8)
		do
			sessions.remove (a_token_hash.to_string_8)
		ensure then
			removed: sessions_model |=| (old sessions_model).removed (a_token_hash.to_string_8)
			users_unchanged: users_model |=| old users_model
			events_unchanged: events_model |=| old events_model
		end

	remove_sessions_of (a_user_id: INTEGER_64)
		local
			l_hashes: ARRAYED_LIST [STRING_8]
		do
			create l_hashes.make (4)
			across sessions as ic loop
				if ic.user_id = a_user_id then
					l_hashes.extend (@ic.key)
				end
			end
			across l_hashes as h loop
				sessions.remove (h)
			end
		ensure then
			others_kept: across (old sessions.twin) as ic all (ic.user_id /= a_user_id) implies sessions_model.domain.has (@ic.key) end
			users_unchanged: users_model |=| old users_model
			events_unchanged: events_model |=| old events_model
		end

feature {NONE} -- Implementation

	events: ARRAYED_LIST [CHAT_EVENT]
	users_table: HASH_TABLE [CHAT_USER, INTEGER_64]
	rooms: HASH_TABLE [CHAT_ROOM, INTEGER_64]
	memberships: ARRAYED_LIST [CHAT_MEMBERSHIP]
	attachments: HASH_TABLE [CHAT_ATTACHMENT, INTEGER_64]
	attachment_bytes_table: HASH_TABLE [SPECIAL [NATURAL_8], INTEGER_64]
	sessions: HASH_TABLE [CHAT_SESSION, STRING_8]

	next_user_id, next_room_id, next_attachment_id, next_session_id: INTEGER_64

	copied_bytes (a_bytes: SPECIAL [NATURAL_8]): SPECIAL [NATURAL_8]
			-- An independent copy of `a_bytes' (D5 at the byte level).
		local
			i: INTEGER
		do
			create Result.make_empty (a_bytes.count)
			from
				i := 0
			until
				i >= a_bytes.count
			loop
				Result.extend (a_bytes [i])
				i := i + 1
			variant
				a_bytes.count - i
			end
		ensure
			fresh: Result /= a_bytes
			same_size: Result.count = a_bytes.count
		end

invariant
	ids_never_exceed_last: across events as e all e.id <= last_event_id end
	count_matches: events.count <= last_event_id
	events_ascending: across 1 |..| (events.count - 1) as i all events [i].id < events [i + 1].id end
	events_reference: across events as e all rooms.has (e.room_id) and (e.is_system or users_table.has (e.sender_id)) end
	keyed_by_id: across users_table as u all u.id = @u.key end
	rooms_keyed_by_id: across rooms as r all r.id = @r.key end
	attachments_keyed_by_id: across attachments as a all a.id = @a.key end
	keyed_by_hash: across sessions as s all s.token_hash.same_string (@s.key) end
	memberships_reference: across memberships as m all rooms.has (m.room_id) and users_table.has (m.user_id) end
	sessions_reference: across sessions as s all users_table.has (s.user_id) end
	attachments_reference: across attachments as a all users_table.has (a.uploader_id) end
	bytes_only_for_stored: across attachment_bytes_table as b all attachments.has (@b.key) end
	unique_usernames: across users_table as u all (across users_table as v all u.username.same_string (v.username) implies u.id = v.id end) end
	unique_pairs: across memberships as a all (across memberships as b all (a.user_id = b.user_id and a.room_id = b.room_id) implies a = b end) end
	default_room_exists: default_room_id > 0 implies rooms.has (default_room_id)
	default_when_any: rooms.count > 0 implies default_room_id > 0
	models_consistent: events_model.count = events.count and users_model.count = users_table.count
		and rooms_model.count = rooms.count and sessions_model.count = sessions.count
		and membership_model.count = memberships.count and attachments_model.count = attachments.count

end
