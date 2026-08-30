note
	description: "[
		The logic between the client, the inbox, the view and the
		notifier - and the only thing that touches all four. Lives on the
		root processor with the window; the GUI timer calls `pump', which
		takes the pages the poller left in the EVENT_INBOX (bytes, copied
		across), decodes them here and shows them. Never waits on the
		network: the inbox is a processor that never blocks, and the
		poller is never spoken to at all - `close_room' stops it through
		the inbox.

		Rules it owns: attribution (who sent it, is it mine, "system" for
		sender 0), the unread count (grows only for others' messages,
		never system events, while the window is not in front; foreground
		clears it), the badge (touched only when it would change), the
		status line, and the connection error - shown once per outage
		(`reported_outage'), not once per tick and not never.
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
			create codec.make
		ensure
			set: client = a_client and view = a_view and notifier = a_notifier
			no_room: not is_room_open
			nothing_unread: unread = 0
			nothing_reported: not reported_outage
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

	room_id: INTEGER_64
			-- The open room; 0 when none.

	unread: INTEGER

	last_seen_id: INTEGER_64
			-- The highest id shown.

	pages_pumped: INTEGER
			-- Pages taken from the inbox so far.

	name_of (a_sender_id: INTEGER_64): STRING_32
			-- The member's display name; "system" for sender 0; "#<id>" until the roster
			-- arrives; with " (@username)" appended when another member shows the same name.
		do
			if a_sender_id = 0 then
				Result := System_name.twin
			elseif attached members [a_sender_id] as m then
				Result := m.display_name.twin
				if has_name_twin (a_sender_id) then
					Result.append ({STRING_32} " (")
					Result.append (m.mention)
					Result.append_character (')')
				end
			else
				Result := {STRING_32} "#" + a_sender_id.out
			end
		ensure
			named: not Result.is_empty
			system_named: a_sender_id = 0 implies Result.same_string (System_name)
			unknown_by_id: (a_sender_id /= 0 and not knows (a_sender_id)) implies Result.same_string ({STRING_32} "#" + a_sender_id.out)
			disambiguated: (a_sender_id /= 0 and knows (a_sender_id) and has_name_twin (a_sender_id)) implies Result.ends_with ({STRING_32} ")")
		end

feature -- Status report

	is_room_open: BOOLEAN
		do
			Result := inbox /= Void
		end

	reported_outage: BOOLEAN
			-- Has the current outage been shown? Reset when polling recovers.

	knows (a_sender_id: INTEGER_64): BOOLEAN
			-- Is `a_sender_id' in the roster?
		do
			Result := members.has (a_sender_id)
		end

	has_name_twin (a_member_id: INTEGER_64): BOOLEAN
			-- Does another member in the roster show the same display name?
		do
			if attached members [a_member_id] as m then
				Result := across members as other some (other.id /= m.id and then other.display_name.same_string (m.display_name)) end
			end
		end

feature -- Element change

	remember (a_member: CHAT_MEMBER)
		do
			members.force (a_member, a_member.id)
		ensure
			known: members_model |=| (old members_model).updated (a_member.id, a_member)
			unread_kept: unread = old unread
			seen_kept: last_seen_id = old last_seen_id
			room_kept: room_id = old room_id
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
			unread_kept: unread = old unread
			seen_kept: last_seen_id = old last_seen_id
			room_kept: room_id = old room_id
			shown_kept: view.shown_model |=| old view.shown_model
		end

feature -- Basic operations

	open_room (a_room_id, a_since_id: INTEGER_64; a_inbox: separate EVENT_INBOX)
			-- Show `a_room_id' from `a_since_id' on, pumping pages the poller leaves in `a_inbox'.
		require
			logged_in: client.is_logged_in
			closed: not is_room_open
			positive_room: a_room_id > 0
			since_non_negative: a_since_id >= 0
		do
			inbox := a_inbox
			room_id := a_room_id
			last_seen_id := a_since_id
			reported_outage := False
			view.show_connection (client.endpoint, True)
		ensure
			open: is_room_open
			room_set: room_id = a_room_id
			from_there: last_seen_id = a_since_id
			inbox_kept: inbox = a_inbox
			unread_kept: unread = old unread
			shown_kept: view.shown_model |=| old view.shown_model
		end

	close_room
			-- Stop the poller (through the inbox) and forget the room.
		require
			open: is_room_open
		do
			if attached inbox as b then
				stop_inbox (b)
			end
			inbox := Void
			room_id := 0
		ensure
			closed: not is_room_open
			unread_kept: unread = old unread
			shown_kept: view.shown_model |=| old view.shown_model
		end

	log_out
			-- Close the room if one is open, then end the session.
		require
			logged_in: client.is_logged_in
		do
			if is_room_open then
				close_room
			end
			client.logout
		ensure
			closed: not is_room_open
			logged_out: not client.is_logged_in
		end

	pump
			-- Show every page the poller left in the inbox; keep the unread count, the badge
			-- and the connection error honest.
		require
			open: is_room_open
			logged_in: client.is_logged_in
		local
			l_bytes: detachable STRING_8
			l_outage: detachable STRING_32
		do
			if attached inbox as b then
				from
					l_bytes := take_from (b)
				until
					l_bytes = Void
				loop
					if attached l_bytes as l_page_bytes then
						pages_pumped := pages_pumped + 1
						if attached codec.page (l_page_bytes) as p then
							apply (p)
						else
							view.show_error (Message_unreadable_page)
						end
					end
					l_bytes := take_from (b)
				end
				l_outage := outage_from (b)
			end
			if attached l_outage as o then
				if not reported_outage then
					view.show_error (o)
					reported_outage := True
				end
			else
				reported_outage := False
			end
			if view.is_foreground then
				unread := 0
				if notifier.unread /= 0 then
					notifier.clear
				end
			elseif notifier.unread /= unread then
				notifier.badge (unread)
			end
		ensure
			shown_some: view.shown_count >= old view.shown_count
			in_order: (old view.shown_model) <= view.shown_model
			foreground_clears: view.is_foreground implies unread = 0
			badge_matches: notifier.unread = unread
			last_seen_monotonic: last_seen_id >= old last_seen_id
			pumped_monotonic: pages_pumped >= old pages_pumped
			still_open: is_room_open
			room_kept: room_id = old room_id
		end

	send (a_text: READABLE_STRING_GENERAL)
			-- Post; the echo arrives through the poller, so nothing is shown here but an error.
		require
			open: is_room_open
			logged_in: client.is_logged_in
			text_given: not a_text.is_empty
		local
			l_result: CHAT_RESULT [CHAT_EVENT]
		do
			l_result := client.post_message (room_id, a_text)
			if not l_result.is_success and then attached l_result.error as e then
				view.show_error (e.message)
			end
		ensure
			nothing_shown_here: view.shown_model |=| old view.shown_model
			unread_kept: unread = old unread
			still_open: is_room_open
			room_kept: room_id = old room_id
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

	System_name: STRING_32 = "system"

	Message_unreadable_page: STRING_32 = "A page from the server could not be read"

feature {NONE} -- Showing

	apply (a_page: CHAT_PAGE)
			-- Show `a_page': every event of the open room, attributed, counted as unread when it is
			-- another member's and the window is not in front; then the room's statuses.
		local
			l_mine, l_system: BOOLEAN
			l_name: STRING_32
			l_shown_before, l_applied, l_unread_before, l_others: INTEGER
		do
			l_shown_before := view.shown_count
			l_unread_before := unread
			across a_page.events as e loop
				if e.room_id = room_id then
					l_mine := attached client.me as m and then m.id = e.sender_id
					l_system := e.sender_id = 0
					l_name := name_of (e.sender_id)
					view.show_event (e, l_name, l_mine)
					l_applied := l_applied + 1
					last_seen_id := last_seen_id.max (e.id)
					if not l_mine and not l_system and not view.is_foreground then
						unread := unread + 1
						l_others := l_others + 1
						notifier.notify (l_name, snippet_of (e))
					end
				end
			end
			check shown_all: view.shown_count = l_shown_before + l_applied end
			check unread_exact: unread = l_unread_before + l_others end
			across a_page.statuses as s loop
				if s.room_id = room_id then
					view.show_status (s.from_display_name + {STRING_32} " " + s.text)
				end
			end
		ensure
			shown_some: view.shown_count >= old view.shown_count
			bounded: view.shown_count <= old view.shown_count + a_page.events.count
			in_order: (old view.shown_model) <= view.shown_model
			last_seen_monotonic: last_seen_id >= old last_seen_id
			unread_monotonic: unread >= old unread
		end

feature {NONE} -- The inbox (each a short, separate call)

	take_from (a_inbox: separate EVENT_INBOX): detachable STRING_8
			-- The oldest page in `a_inbox', copied here; Void when there is none.
		do
			if attached a_inbox.take as s then
				create Result.make_from_separate (s)
			end
		end

	outage_from (a_inbox: separate EVENT_INBOX): detachable STRING_32
			-- The poller's reported outage, copied here; Void while it polls successfully.
		do
			if attached a_inbox.outage as o then
				create Result.make_from_separate (o)
			end
		end

	stop_inbox (a_inbox: separate EVENT_INBOX)
		do
			a_inbox.stop
		end

feature {NONE} -- Implementation

	view: CHAT_VIEW
	notifier: NOTIFIER
	codec: CLIENT_CODEC
	members: HASH_TABLE [CHAT_MEMBER, INTEGER_64]

	inbox: detachable separate EVENT_INBOX
			-- Where the poller leaves pages; attached exactly while a room is open.

invariant
	unread_non_negative: unread >= 0
	last_seen_non_negative: last_seen_id >= 0
	pumped_non_negative: pages_pumped >= 0
	model_consistent: members_model.count = members.count
	open_implies_session: is_room_open implies client.is_logged_in
	room_iff_open: is_room_open = (room_id > 0)

end
