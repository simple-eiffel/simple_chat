note
	description: "[
		Delivers one room's events to one client from a `since' id onward,
		in order, each exactly once. The live stream and any fallback (long
		polling) are both this, so a client's reconnect and its live
		delivery share one contract.
	]"
	author: "Larry Rix"

deferred class
	EVENT_SOURCE

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
			-- The highest id this client has been given.

feature -- Basic operations

	open (a_room_id, a_since_id: INTEGER_64)
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
		end

	close
		deferred
		ensure
			closed: not is_open
		end

	deliver_pending
			-- Give the client everything after `last_delivered_id', in order.
		require
			open: is_open
		deferred
		ensure
			in_order: last_delivered_id >= old last_delivered_id
		end

invariant
	never_backwards: last_delivered_id >= since_id
	room_when_open: is_open implies room_id > 0

end
