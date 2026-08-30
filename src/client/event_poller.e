note
	description: "[
		The client's long-poll machine. `poll_once' is the unit of work:
		one wait_for_events from `cursor', whose events are queued in
		`pending' and advance the cursor. Phase 4 drives it from a worker
		thread; the GUI thread only ever calls `drain' (and the queries),
		under the same MUTEX, so the two never share a list unguarded.

		The cursor never goes backwards, `pending' is always ascending,
		and everything pending is at or below the cursor: the three laws
		the assault checks with a scripted transport.
	]"
	author: "Larry Rix"

class
	EVENT_POLLER

create
	make

feature {NONE} -- Initialization

	make (a_client: CHAT_CLIENT; a_room_id, a_since_id: INTEGER_64)
		require
			logged_in: a_client.is_logged_in
			positive_room: a_room_id > 0
			since_non_negative: a_since_id >= 0
		do
			client := a_client
			room_id := a_room_id
			cursor := a_since_id
			create pending.make (16)
			create pending_statuses.make (2)
			create lock.make
		ensure
			set: room_id = a_room_id and cursor = a_since_id
			nothing_pending: pending_count = 0
		end

feature -- Model Queries (for MML postconditions)

	pending_model: MML_SEQUENCE [INTEGER_64]
			-- Ids queued and not yet drained, in order (a snapshot; not locked).
		do
			create Result
			across pending as ic loop
				Result := Result & ic.id
			end
		ensure
			same_count: Result.count = pending.count
		end

feature -- Access

	room_id: INTEGER_64

	cursor: INTEGER_64
			-- The highest id seen; the next poll asks for what follows it.

	polls: INTEGER
			-- `poll_once' calls so far.

	consecutive_failures: INTEGER

	last_error: detachable CHAT_ERROR

	pending_count: INTEGER
		do
			Result := pending.count
		end

	pending_status_count: INTEGER
		do
			Result := pending_statuses.count
		end

feature -- Basic operations

	poll_once (a_wait_seconds: INTEGER)
			-- One long-poll from `cursor'; queue what came, advance the cursor.
		require
			seconds_in_range: a_wait_seconds >= 0 and a_wait_seconds <= {CHAT_CLIENT}.Max_wait_seconds
		local
			l_result: CHAT_RESULT [CHAT_PAGE]
		do
			l_result := client.wait_for_events (room_id, cursor, Page_size, a_wait_seconds)
			polls := polls + 1
			if l_result.is_success and then attached l_result.value as p then
				lock.lock
				across p.events as e loop
					if e.id > cursor then
						pending.extend (e)
						cursor := e.id
					end
				end
				across p.statuses as s loop
					pending_statuses.extend (s)
				end
				lock.unlock
				consecutive_failures := 0
				last_error := Void
			else
				consecutive_failures := consecutive_failures + 1
				last_error := l_result.error
			end
		ensure
			polled: polls = old polls + 1
			cursor_monotonic: cursor >= old cursor
			older_kept: pending_model.count >= (old pending_model).count
			failure_explained: (consecutive_failures > 0) = (last_error /= Void)
		end

	drain: ARRAYED_LIST [CHAT_EVENT]
			-- Everything queued, in order; the queue is emptied.
		do
			lock.lock
			Result := pending.twin
			pending.wipe_out
			lock.unlock
		ensure
			emptied: pending_count = 0
			handed_over: Result.count = (old pending_model).count
			ascending: across Result as e all e.id <= cursor end
		end

	drain_statuses: ARRAYED_LIST [CHAT_STATUS]
		do
			lock.lock
			Result := pending_statuses.twin
			pending_statuses.wipe_out
			lock.unlock
		ensure
			emptied: pending_status_count = 0
		end

feature -- Constants

	Page_size: INTEGER = 200

feature {NONE} -- Implementation

	client: CHAT_CLIENT
	pending: ARRAYED_LIST [CHAT_EVENT]
	pending_statuses: ARRAYED_LIST [CHAT_STATUS]
	lock: MUTEX

invariant
	cursor_non_negative: cursor >= 0
	pending_at_or_below_cursor: across pending as e all e.id <= cursor end
	counts_non_negative: polls >= 0 and consecutive_failures >= 0
	model_consistent: pending_model.count = pending.count

end
