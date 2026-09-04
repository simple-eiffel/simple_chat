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
		sender 0 - and " (@username)" after any member's name that would
		mislead on its own: a twin in the roster, or the reserved "system"
		itself), the unread count (grows only for others' messages,
		never system events, while the window is not in front; foreground
		clears it), the badge (touched only when it would change), the
		status line, the connection state (`show_connection', revised
		exactly when an outage begins and when it ends), the connection
		error - shown once per outage (`reported_outage'), not once per
		tick and not never - and the end of the session: when the inbox
		says the poller met a 401 (`session_lost'), `pump' shows the
		server's reason once, closes the room and drops the GUI client's
		token without an exchange (the server has already rejected it);
		the window then asks for a login and `open_room' starts afresh.
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
			session_alive: not session_lost
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
			-- arrives; with " (@username)" appended when the name would mislead on its own -
			-- another member shows the same name (any case), or it reads as the reserved "system".
		do
			if a_sender_id = 0 then
				Result := System_name.twin
			elseif attached members [a_sender_id] as m then
				Result := m.display_name.twin
				if is_ambiguous_name (a_sender_id) then
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
			disambiguated: (a_sender_id /= 0 and knows (a_sender_id) and is_ambiguous_name (a_sender_id)) implies Result.ends_with ({STRING_32} ")")
			never_system_alike: (a_sender_id /= 0 and knows (a_sender_id)) implies not Result.as_lower.same_string (System_name)
		end

feature -- Status report

	is_room_open: BOOLEAN
		do
			Result := inbox /= Void
		end

	reported_outage: BOOLEAN
			-- Has the current outage been shown? Reset when polling recovers.

	session_lost: BOOLEAN
			-- Did the last pump learn the session is dead (the poller met a 401)? The room is then
			-- closed and the client logged out; the window must ask for a login before `open_room'.

	knows (a_sender_id: INTEGER_64): BOOLEAN
			-- Is `a_sender_id' in the roster?
		do
			Result := members.has (a_sender_id)
		end

	bot_members: ARRAYED_LIST [CHAT_MEMBER]
			-- Every bot in the roster, roster order - real data for a host that
			-- wants to name the room's assistant(s) rather than hard-code one.
		do
			create Result.make (4)
			across members as m loop
				if m.is_bot then
					Result.extend (m)
				end
			end
		ensure
			all_bots: across Result as r all r.is_bot end
			known_only: across Result as r all knows (r.id) end
		end

	has_name_twin (a_member_id: INTEGER_64): BOOLEAN
			-- Does another member in the roster show the same display name (compared without regard to case)?
		do
			if attached members [a_member_id] as m then
				Result := across members as other some (other.id /= m.id and then other.display_name.as_lower.same_string (m.display_name.as_lower)) end
			end
		ensure
			known_only: Result implies knows (a_member_id)
		end

	is_system_alike (a_member_id: INTEGER_64): BOOLEAN
			-- Does the member's display name read as the reserved `System_name' (without regard to case)?
		do
			Result := attached members [a_member_id] as m and then m.display_name.as_lower.same_string (System_name)
		ensure
			known_only: Result implies knows (a_member_id)
		end

	is_ambiguous_name (a_member_id: INTEGER_64): BOOLEAN
			-- Would the member's display name mislead on its own: a twin in the roster, or the reserved "system"?
		do
			Result := has_name_twin (a_member_id) or is_system_alike (a_member_id)
		ensure
			definition: Result = (has_name_twin (a_member_id) or is_system_alike (a_member_id))
			known_only: Result implies knows (a_member_id)
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
			seen_events.wipe_out
			reported_outage := False
			session_lost := False
			view.show_connection (client.endpoint, True)
		ensure
			open: is_room_open
			room_set: room_id = a_room_id
			from_there: last_seen_id = a_since_id
			inbox_kept: inbox = a_inbox
			session_fresh: not session_lost
			connected_shown: view.is_connected
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
			-- Show every page the poller left in the inbox; keep the unread count, the badge, the
			-- connection state and the connection error honest; and when the inbox says the session
			-- is lost, show why once, close the room and forget the session.
		require
			open: is_room_open
			logged_in: client.is_logged_in
		local
			l_bytes: detachable STRING_8
			l_outage, l_lost: detachable STRING_32
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
				l_lost := session_lost_from (b)
			end
			if attached l_lost as l_why then
				view.show_error (l_why)
				session_lost := True
				close_room
				client.forget_session
			elseif attached l_outage as o then
				if not reported_outage then
					view.show_error (o)
					view.show_connection (client.endpoint, False)
					reported_outage := True
				end
			elseif reported_outage then
				view.show_connection (client.endpoint, True)
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
			lost_closes: session_lost implies (not is_room_open and not client.is_logged_in)
			still_open: not session_lost implies is_room_open
			room_kept: not session_lost implies room_id = old room_id
			connection_shown: not session_lost implies view.is_connected = not reported_outage
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

feature -- Access: what a per-message menu needs

	sender_of (a_event_id: INTEGER_64): INTEGER_64
			-- Who said `a_event_id'; 0 for one this client never saw. What
			-- the permission rule needs before it can grey a menu item.
		do
			across seen_events as e loop
				if Result = 0 and then e.id = a_event_id then
					Result := e.sender_id
				end
			end
		ensure
			non_negative: Result >= 0
		end

	body_of (a_event_id: INTEGER_64): STRING_32
			-- What `a_event_id' says NOW - its latest edit when it has one,
			-- so Edit loads the composer with the text on screen and not the
			-- words it replaced. Empty for one this client never saw.
		local
			f: MESSAGE_FOLD
		do
			create f.make (seen_events)
			if attached f.current_text (a_event_id) as t then
				Result := t.twin
			else
				create Result.make_empty
				across seen_events as e loop
					if Result.is_empty and then e.id = a_event_id and then e.is_message then
						Result := e.body.twin
					end
				end
			end
		end

	is_message_deleted (a_event_id: INTEGER_64): BOOLEAN
			-- Has `a_event_id' been tombstoned? Nothing may be done to a
			-- deleted message: a delete is final.
		local
			f: MESSAGE_FOLD
		do
			create f.make (seen_events)
			Result := f.is_deleted (a_event_id)
		end

	apply_fold
			-- Fold every event this room has shown and give the view what a
			-- reader should now see: edited text, tombstones, reaction rows
			-- and reply quotes. The view ignores an id it never drew and one
			-- already tombstoned, so this is safe to run again and again.
		local
			f: MESSAGE_FOLD
			l_row: ARRAYED_LIST [TUPLE [emoji: STRING_32; tally: INTEGER; mine: BOOLEAN]]
			l_me: INTEGER_64
		do
			create f.make (seen_events)
			if attached client.me as m then
				l_me := m.id
			end
			across f.standalone as e loop
				if f.is_deleted (e.id) then
					view.apply_delete (e.id)
				else
					if attached f.current_text (e.id) as t and then not t.is_empty then
						view.apply_edit (e.id, t)
					end
					create l_row.make (4)
					across f.reactions_on (e.id) as n loop
						l_row.extend ([@n.key.twin, n, f.reacted (e.id, l_me, @n.key)])
					end
						-- UNCONDITIONALLY, empty row included: a row is replaced
						-- wholesale, and the one moment an empty one matters is
						-- the moment it BECAME empty - somebody took their only
						-- reaction back. Skipping it there would leave the chip
						-- drawn until an unrelated event happened to redraw it.
					view.apply_reactions (e.id, l_row)
					if f.reply_parent (e.id) > 0 and then attached quoted_parent (f.reply_parent (e.id)) as q then
						view.apply_reply_quote (e.id, q.author, q.text)
					end
				end
			end
		ensure
			nothing_added: view.shown_model |=| old view.shown_model
		end

	quoted_parent (a_id: INTEGER_64): detachable TUPLE [author, text: STRING_32]
			-- Who said the message `a_id' is, and what it said - for the
			-- one-line quote a reply carries. Void when this client never
			-- saw the parent, which a page boundary makes ordinary.
		do
			across seen_events as e loop
				if Result = Void and then e.id = a_id and then e.is_message then
					Result := [name_of (e.sender_id), e.body.twin]
				end
			end
		end

	seen_events: ARRAYED_LIST [CHAT_EVENT]
			-- Every event of the open room this client has pumped, oldest
			-- first - what the fold needs, and the only place a reply can
			-- find the words it quotes.
		attribute
			create Result.make (64)
		end

	kinds: CHAT_EVENT_KINDS
		once
			create Result
		end

	apply (a_page: CHAT_PAGE)
			-- Show `a_page': every event of the open room, attributed, counted as unread when it is
			-- another member's and the window is not in front; then the room's statuses.
		local
			l_mine, l_system, l_folded: BOOLEAN
			l_name: STRING_32
			l_shown_before, l_applied, l_unread_before, l_others: INTEGER
		do
			l_shown_before := view.shown_count
			l_unread_before := unread
			across a_page.events as e loop
				if e.room_id = room_id then
					seen_events.extend (e)
					last_seen_id := last_seen_id.max (e.id)
					if kinds.is_fold_kind (e.kind) then
							-- An edit, a delete or a reaction CHANGES a bubble that
							-- is already there. It never draws one of its own, and
							-- it is nobody's unread: a reaction on an old message
							-- is not a message.
						l_folded := True
					else
						l_mine := attached client.me as m and then m.id = e.sender_id
						l_system := e.sender_id = 0
						l_name := name_of (e.sender_id)
						view.show_event (e, l_name, l_mine)
						l_applied := l_applied + 1
						l_folded := True
						if not l_mine and not l_system and not view.is_foreground then
							unread := unread + 1
							l_others := l_others + 1
							notifier.notify (l_name, snippet_of (e))
						end
					end
				end
			end
			check shown_all: view.shown_count = l_shown_before + l_applied end
			check unread_exact: unread = l_unread_before + l_others end
			if l_folded then
					-- Re-fold everything this room has shown and push the result
					-- onto the bubbles. MESSAGE_FOLD is the SHIPPED rule - last
					-- edit wins, a delete is final, reactions dedupe per person
					-- per emoji - and re-running it beats a second, private copy
					-- of those rules living here and drifting from it.
				apply_fold
			end
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

	session_lost_from (a_inbox: separate EVENT_INBOX): detachable STRING_32
			-- The server's reason when the poller met a 401 (the outage it reported with it), copied
			-- here; Void while the session is alive.
		do
			if a_inbox.is_session_lost and then attached a_inbox.outage as o then
				create Result.make_from_separate (o)
			end
		ensure
			lost_iff_given: (Result /= Void) = a_inbox.is_session_lost
		end

	stop_inbox (a_inbox: separate EVENT_INBOX)
		do
			a_inbox.stop
		ensure
			stopped: a_inbox.is_stopped
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
	lost_is_closed: session_lost implies not is_room_open
	connection_honest: is_room_open implies view.is_connected = not reported_outage

end
