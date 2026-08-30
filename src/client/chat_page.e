note
	description: "[
		One answer from /events or /wait: events in ascending id order
		plus the ephemeral statuses seen meanwhile. A page the client
		decoded from the wire also keeps the bytes it came as (`bytes',
		`make_from_wire'), because only bytes cross processors: the
		poller hands those to EVENT_INBOX and the presenter decodes them
		again on the root.
	]"
	author: "Larry Rix"

class
	CHAT_PAGE

create
	make,
	make_from_wire

feature {NONE} -- Initialization

	make (a_events: ARRAYED_LIST [CHAT_EVENT]; a_statuses: ARRAYED_LIST [CHAT_STATUS])
			-- A page built locally (the server's side; no wire bytes).
		require
			ascending: is_ascending (a_events)
		do
			events := a_events
			statuses := a_statuses
			create bytes.make_empty
		ensure
			kept: events = a_events and statuses = a_statuses
			no_bytes: not has_bytes
		end

	make_from_wire (a_events: ARRAYED_LIST [CHAT_EVENT]; a_statuses: ARRAYED_LIST [CHAT_STATUS]; a_bytes: READABLE_STRING_8)
			-- A page decoded from `a_bytes', which it keeps (a copy).
		require
			ascending: is_ascending (a_events)
			given: not a_bytes.is_empty
		do
			events := a_events
			statuses := a_statuses
			create bytes.make_from_string (a_bytes)
		ensure
			kept: events = a_events and statuses = a_statuses
			bytes_kept: bytes.same_string (a_bytes)
			has_bytes: has_bytes
		end

feature -- Access

	events: ARRAYED_LIST [CHAT_EVENT]
	statuses: ARRAYED_LIST [CHAT_STATUS]

	bytes: STRING_8
			-- The wire form this page was decoded from; empty for a page built locally.

	last_id: INTEGER_64
			-- The highest event id, or 0 when empty.
		do
			if not events.is_empty then
				Result := events.last.id
			end
		ensure
			zero_when_empty: events.is_empty implies Result = 0
			the_last: not events.is_empty implies Result = events.last.id
			the_highest: across events as e all e.id <= Result end
		end

feature -- Status report

	is_empty: BOOLEAN
			-- Neither events nor statuses?
		do
			Result := events.is_empty and statuses.is_empty
		ensure
			definition: Result = (events.is_empty and statuses.is_empty)
		end

	has_bytes: BOOLEAN
			-- Was this page decoded from the wire?
		do
			Result := not bytes.is_empty
		end

feature -- Validation (contract support)

	is_ascending (a_events: LIST [CHAT_EVENT]): BOOLEAN
			-- Strictly increasing ids?
		local
			l_previous: INTEGER_64
		do
			Result := True
			across a_events as e loop
				if e.id <= l_previous then
					Result := False
				end
				l_previous := e.id
			end
		end

invariant
	ascending: is_ascending (events)

end
