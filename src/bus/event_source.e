note
	description: "[
		Delivers one room's events to one client from a `since' id onward,
		in order, each exactly once: the SSE stream is one; the long-poll
		page is the same law applied once per request. `delivered_model'
		is the list of ids given so far - strictly increasing, all after
		`since_id' - and every delivery extends it.
	]"
	author: "Larry Rix"

deferred class
	EVENT_SOURCE

feature -- Model Queries (for MML postconditions)

	delivered_model: MML_SEQUENCE [INTEGER_64]
			-- The ids delivered, in order.
		deferred
		end

feature -- Status report

	is_open: BOOLEAN
		deferred
		end

feature -- Access

	room_id: INTEGER_64
			-- The room being delivered; 0 before `open'.

	since_id: INTEGER_64
			-- Where delivery started.

	last_delivered_id: INTEGER_64
			-- The highest id this client has been given; `since_id' until the first delivery.

feature -- Basic operations

	open (a_room_id, a_since_id: INTEGER_64)
			-- Start delivering `a_room_id' after `a_since_id'; delivers nothing itself.
		require
			not_open: not is_open
			positive_room: a_room_id > 0
			since_non_negative: a_since_id >= 0
		deferred
		ensure
			open: is_open
			room_set: room_id = a_room_id
			since_set: since_id = a_since_id
			starts_at_since: last_delivered_id = a_since_id
			nothing_yet: delivered_model.is_empty
		end

	close
		deferred
		ensure
			closed: not is_open
		end

	deliver (a_page: CHAT_PAGE)
			-- Give the client `a_page' - the events after `last_delivered_id', in order.
		require
			open: is_open
			follows: a_page.events.is_empty or else a_page.events.first.id > last_delivered_id
			same_room: across a_page.events as e all e.room_id = room_id end
		deferred
		ensure
			extended: delivered_model.count = old delivered_model.count + a_page.events.count
			prefix_kept: delivered_model.front (old delivered_model.count) |=| old delivered_model
			advanced: last_delivered_id = (if a_page.events.is_empty then old last_delivered_id else a_page.last_id end)
		end

feature -- Validation (contract support)

	is_strictly_increasing (a_ids: MML_SEQUENCE [INTEGER_64]): BOOLEAN
		local
			i: INTEGER
		do
			Result := True
			from
				i := 1
			until
				i >= a_ids.count or not Result
			loop
				Result := a_ids [i] < a_ids [i + 1]
				i := i + 1
			end
		end

invariant
	never_backwards: last_delivered_id >= since_id
	room_when_open: is_open implies room_id > 0
	each_once_in_order: is_strictly_increasing (delivered_model)
	all_after_since: delivered_model.count > 0 implies delivered_model.first > since_id
	last_is_last: delivered_model.count > 0 implies last_delivered_id = delivered_model.last

end
