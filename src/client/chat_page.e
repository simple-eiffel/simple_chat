note
	description: "One answer from /events or /wait: events in ascending id order plus the ephemeral statuses seen meanwhile."
	author: "Larry Rix"

class
	CHAT_PAGE

create
	make

feature {NONE} -- Initialization

	make (a_events: ARRAYED_LIST [CHAT_EVENT]; a_statuses: ARRAYED_LIST [CHAT_STATUS])
		require
			ascending: is_ascending (a_events)
		do
			events := a_events
			statuses := a_statuses
		ensure
			kept: events = a_events and statuses = a_statuses
		end

feature -- Access

	events: ARRAYED_LIST [CHAT_EVENT]
	statuses: ARRAYED_LIST [CHAT_STATUS]

	last_id: INTEGER_64
			-- The highest event id, or 0 when empty.
		do
			if not events.is_empty then
				Result := events.last.id
			end
		ensure
			zero_when_empty: events.is_empty implies Result = 0
		end

feature -- Status report

	is_empty: BOOLEAN
		do
			Result := events.is_empty and statuses.is_empty
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
