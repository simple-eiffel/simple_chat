note
	description: "[
		The logic between the client, the poller, the view and the
		notifier - and the only thing that touches all four. Single-
		threaded by construction: the GUI timer calls `pump'. Rules it
		owns: attribution (who sent it, is it mine), the unread count
		(grows only for others' messages while the window is not in
		front; foreground clears it), and the status line.
	]"
	author: "Larry Rix"

class
	CHAT_PRESENTER

create
	make

feature {NONE} -- Initialization

	make (a_client: CHAT_CLIENT; a_view: CHAT_VIEW; a_notifier: NOTIFIER)
		do
			client := a_client
			view := a_view
			notifier := a_notifier
			create members.make (16)
		ensure
			set: client = a_client and view = a_view and notifier = a_notifier
			no_room: not is_room_open
			nothing_unread: unread = 0
		end

feature -- Model Queries (for MML postconditions)

	members_model: MML_MAP [INTEGER_64, CHAT_MEMBER]
		do
			create Result
			across members as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = members.count
		end

feature -- Access

	client: CHAT_CLIENT
			-- Public because the contracts speak of it (VAPE).

	poller: detachable EVENT_POLLER

	unread: INTEGER

	last_seen_id: INTEGER_64
			-- The highest id shown.

	pending_count: INTEGER
			-- What the poller holds for the next `pump'.
		do
			if attached poller as p then
				Result := p.pending_count
			end
		end

	name_of (a_sender_id: INTEGER_64): STRING_32
			-- The member's display name, or "#<id>" until the roster arrives.
		do
			if attached members [a_sender_id] as m then
				Result := m.display_name
			else
				Result := {STRING_32} "#" + a_sender_id.out
			end
		ensure
			named: not Result.is_empty
		end

feature -- Status report

	is_room_open: BOOLEAN
		do
			Result := poller /= Void
		end

feature -- Element change

	remember (a_member: CHAT_MEMBER)
		do
			members.force (a_member, a_member.id)
		ensure
			known: members_model |=| (old members_model).updated (a_member.id, a_member)
		end

	load_roster (a_room_id: INTEGER_64)
			-- GET the members and remember them; an error is shown, not raised.
		require
			logged_in: client.is_logged_in
			positive_room: a_room_id > 0
		local
			l_result: CHAT_RESULT [ARRAYED_LIST [CHAT_MEMBER]]
		do
			l_result := client.members (a_room_id)
			if l_result.is_success and then attached l_result.value as l_list then
				across l_list as m loop
					remember (m)
				end
			elseif attached l_result.error as e then
				view.show_error (e.message)
			end
		ensure
			never_forgets: members_model.count >= (old members_model).count
		end

feature -- Basic operations

	open_room (a_room_id, a_since_id: INTEGER_64)
			-- Start polling `a_room_id' after `a_since_id'.
		require
			logged_in: client.is_logged_in
			positive_room: a_room_id > 0
			since_non_negative: a_since_id >= 0
		do
			create poller.make (client, a_room_id, a_since_id)
			last_seen_id := a_since_id
			view.show_connection (client.endpoint, True)
		ensure
			open: is_room_open
			from_there: last_seen_id = a_since_id
		end

	pump
			-- Show what the poller drained; keep the unread count honest.
		require
			open: is_room_open
		local
			l_mine: BOOLEAN
			l_name: STRING_32
		do
			if attached poller as p then
				across p.drain as e loop
					l_mine := attached client.me as m and then m.id = e.sender_id
					l_name := name_of (e.sender_id)
					view.show_event (e, l_name, l_mine)
					last_seen_id := last_seen_id.max (e.id)
					if not l_mine and not view.is_foreground then
						unread := unread + 1
						notifier.notify (l_name, snippet_of (e))
					end
				end
				across p.drain_statuses as s loop
					view.show_status (s.from_display_name + {STRING_32} " " + s.text)
				end
				if attached p.last_error as err and then p.consecutive_failures = 1 then
					view.show_error (err.message)
				end
			end
			if view.is_foreground then
				unread := 0
				notifier.clear
			else
				notifier.badge (unread)
			end
		ensure
			shown_all: view.shown_count = old view.shown_count + old pending_count
			drained: pending_count = 0
			foreground_clears: view.is_foreground implies unread = 0
			badge_matches: notifier.unread = unread
			last_seen_monotonic: last_seen_id >= old last_seen_id
		end

	send (a_text: READABLE_STRING_GENERAL)
			-- Post; the echo arrives through the poller, so nothing is shown here but an error.
		require
			open: is_room_open
			text_given: not a_text.is_empty
		local
			l_result: CHAT_RESULT [CHAT_EVENT]
		do
			if attached poller as p then
				l_result := client.post_message (p.room_id, a_text)
				if not l_result.is_success and then attached l_result.error as e then
					view.show_error (e.message)
				end
			end
		ensure
			nothing_shown_here: view.shown_count = old view.shown_count
		end

feature -- Conversion (contract support)

	snippet_of (a_event: CHAT_EVENT): STRING_32
			-- The start of the body, for a notice.
		do
			if a_event.is_image then
				Result := {STRING_32} "(image) " + a_event.body
			else
				Result := a_event.body.twin
			end
			if Result.count > Snippet_maximum then
				Result := Result.substring (1, Snippet_maximum) + {STRING_32} "…"
			end
		ensure
			bounded: Result.count <= Snippet_maximum + 1
		end

feature -- Constants

	Snippet_maximum: INTEGER = 80

feature {NONE} -- Implementation

	view: CHAT_VIEW
	notifier: NOTIFIER
	members: HASH_TABLE [CHAT_MEMBER, INTEGER_64]

invariant
	unread_non_negative: unread >= 0
	last_seen_non_negative: last_seen_id >= 0
	model_consistent: members_model.count = members.count

end
