note
	description: "[
		CHAT_STORE in memory: the test oracle. Every collection has a
		mathematical model, so the store's commands state what changed,
		how, and - through frame conditions - what did not; the SQLite
		store is checked against this one feature for feature.
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
			create sessions.make (16)
			create lock.make
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
			-- user id -> room id, many to many.
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

feature -- Lifecycle

	open
		do
			is_open := True
		ensure then
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

feature -- Events

	last_event_id: INTEGER_64

	event_count: INTEGER_64
		do
			Result := events.count
		end

	append_event (a_draft: CHAT_EVENT_DRAFT): CHAT_EVENT
		local
			l_now: SIMPLE_DATE_TIME
		do
			-- Implementation in Phase 4 (under `lock')
			create l_now.make_now
			create Result.make (last_event_id + 1, a_draft.room_id, a_draft.sender_id, a_draft.kind, l_now,
				a_draft.body, a_draft.attachment, a_draft.payload, a_draft.is_bot_authored)
		ensure then
			appended_at_end: events_model |=| ((old events_model) & Result)
			users_unchanged: users_model |=| old users_model
			rooms_unchanged: rooms_model |=| old rooms_model
			memberships_unchanged: membership_model |=| old membership_model
			attachments_unchanged: attachments_model |=| old attachments_model
			sessions_unchanged: sessions_model |=| old sessions_model
		end

	event (a_id: INTEGER_64): detachable CHAT_EVENT
		do
			-- Implementation in Phase 4
		ensure then
			from_model: attached Result as e implies events_model.has (e)
		end

	events_since (a_room_id, a_since_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
		do
			create Result.make (0)
			-- Implementation in Phase 4
		ensure then
			from_model: across Result as e all events_model.has (e) end
		end

	events_before (a_room_id, a_before_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
		do
			create Result.make (0)
			-- Implementation in Phase 4
		ensure then
			from_model: across Result as e all events_model.has (e) end
		end

	count_after (a_room_id, a_since_id: INTEGER_64): INTEGER_64
		do
			-- Implementation in Phase 4
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
			-- Implementation in Phase 4
		end

	add_user (a_user: CHAT_USER)
		do
			-- Implementation in Phase 4
		ensure then
			added: users_model |=| (old users_model).updated (a_user.id, a_user)
			events_unchanged: events_model |=| old events_model
			rooms_unchanged: rooms_model |=| old rooms_model
			memberships_unchanged: membership_model |=| old membership_model
			sessions_unchanged: sessions_model |=| old sessions_model
		end

	update_user (a_user: CHAT_USER)
		do
			-- Implementation in Phase 4
		ensure then
			replaced: users_model |=| (old users_model).updated (a_user.id, a_user)
			same_users: users_model.domain |=| (old users_model).domain
			events_unchanged: events_model |=| old events_model
			sessions_unchanged: sessions_model |=| old sessions_model
		end

	user (a_user_id: INTEGER_64): detachable CHAT_USER
		do
			-- Implementation in Phase 4
		ensure then
			from_model: attached Result as u implies users_model.domain.has (a_user_id)
		end

	user_by_username (a_username: READABLE_STRING_8): detachable CHAT_USER
		do
			-- Implementation in Phase 4
		end

	users: ARRAYED_LIST [CHAT_USER]
		do
			create Result.make (0)
			-- Implementation in Phase 4
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
			-- Implementation in Phase 4
		ensure then
			added: rooms_model |=| (old rooms_model).updated (a_room.id, a_room)
			users_unchanged: users_model |=| old users_model
			events_unchanged: events_model |=| old events_model
			memberships_unchanged: membership_model |=| old membership_model
		end

	room (a_room_id: INTEGER_64): detachable CHAT_ROOM
		do
			-- Implementation in Phase 4
		ensure then
			from_model: attached Result as r implies rooms_model.domain.has (a_room_id)
		end

	default_room: detachable CHAT_ROOM
		do
			-- Implementation in Phase 4
		end

	rooms_of (a_user_id: INTEGER_64): ARRAYED_LIST [CHAT_ROOM]
		do
			create Result.make (0)
			-- Implementation in Phase 4
		ensure then
			exactly_the_image: Result.count = membership_model.image_of (a_user_id).count
		end

	is_member (a_user_id, a_room_id: INTEGER_64): BOOLEAN
		do
			-- Implementation in Phase 4
		ensure then
			definition: Result = membership_model.has (a_user_id, a_room_id)
		end

	add_membership (a_membership: CHAT_MEMBERSHIP)
		do
			-- Implementation in Phase 4
		ensure then
			related: membership_model |=| (old membership_model).extended (a_membership.user_id, a_membership.room_id)
			users_unchanged: users_model |=| old users_model
			rooms_unchanged: rooms_model |=| old rooms_model
			events_unchanged: events_model |=| old events_model
		end

feature -- Attachments

	add_attachment (a_attachment: CHAT_ATTACHMENT)
		do
			-- Implementation in Phase 4
		ensure then
			added: attachments_model |=| (old attachments_model).updated (a_attachment.id, a_attachment)
			events_unchanged: events_model |=| old events_model
			users_unchanged: users_model |=| old users_model
		end

	attachment (a_attachment_id: INTEGER_64): detachable CHAT_ATTACHMENT
		do
			-- Implementation in Phase 4
		ensure then
			from_model: attached Result as a implies attachments_model.domain.has (a_attachment_id)
		end

feature -- Sessions

	put_session (a_session: CHAT_SESSION)
		do
			-- Implementation in Phase 4
		ensure then
			stored_by_hash: sessions_model |=| (old sessions_model).updated (a_session.token_hash, a_session)
			users_unchanged: users_model |=| old users_model
			events_unchanged: events_model |=| old events_model
		end

	session_by_hash (a_token_hash: READABLE_STRING_8): detachable CHAT_SESSION
		do
			-- Implementation in Phase 4
		ensure then
			definition: (Result /= Void) = sessions_model.domain.has (a_token_hash.to_string_8)
		end

	remove_session (a_token_hash: READABLE_STRING_8)
		do
			-- Implementation in Phase 4
		ensure then
			removed: sessions_model |=| (old sessions_model).removed (a_token_hash.to_string_8)
			users_unchanged: users_model |=| old users_model
			events_unchanged: events_model |=| old events_model
		end

	remove_sessions_of (a_user_id: INTEGER_64)
		do
			-- Implementation in Phase 4
		ensure then
			none_left: across sessions as ic all ic.user_id /= a_user_id end
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
	sessions: HASH_TABLE [CHAT_SESSION, STRING_8]
	lock: MUTEX

invariant
	ids_never_exceed_last: across events as e all e.id <= last_event_id end
	count_matches: event_count = events.count
	models_consistent: events_model.count = events.count and users_model.count = users_table.count
		and rooms_model.count = rooms.count and sessions_model.count = sessions.count

end
