note
	description: "[
		The long-poll's half of the doorbell. A handler calls `arm' for
		its room, checks the store, and if nothing is there calls `wait';
		a wake that lands between the check and the wait is retained, so
		the classic check-then-sleep race cannot lose a message. Wakes for
		other rooms are ignored. Statuses seen while armed are kept and
		ride back with the reply (they exist nowhere else - DR-009).

		Thread-safe: MUTEX + CONDITION_VARIABLE, both from EiffelBase.
		`wait' releases the mutex while blocked, so `wake' from a posting
		thread always gets in.
	]"
	author: "Larry Rix"

class
	POLL_WAITER

inherit
	EVENT_SUBSCRIBER

create
	make

feature {NONE} -- Initialization

	make
		do
			create lock.make
			create condition.make
			create statuses.make (2)
			subscriber_name := "poll"
		ensure
			not_armed: not is_armed
			nothing_yet: wake_count = 0
		end

feature -- Access

	subscriber_name: STRING_8

	wake_count: INTEGER

	armed_room_id: INTEGER_64
			-- The room `arm' named; 0 when not armed.

	wakes_since_arm: INTEGER
			-- Wakes for the armed room since `arm'.

	statuses: ARRAYED_LIST [CHAT_STATUS]
			-- Ephemeral notices for the armed room since `arm'.

feature -- Status report

	is_armed: BOOLEAN
		do
			Result := armed_room_id > 0
		end

feature -- Basic operations

	arm (a_room_id: INTEGER_64)
			-- Listen for `a_room_id' from now; forget earlier wakes and statuses.
		require
			positive_room: a_room_id > 0
		do
			lock.lock
			armed_room_id := a_room_id
			wakes_since_arm := 0
			statuses.wipe_out
			lock.unlock
		ensure
			armed: is_armed and armed_room_id = a_room_id
			fresh: wakes_since_arm = 0 and statuses.is_empty
		end

	wait (a_max_ms: INTEGER): BOOLEAN
			-- Block until a wake for the armed room arrives or `a_max_ms' pass.
			-- True exactly when a wake arrived since `arm' (possibly before this call).
		require
			armed: is_armed
			non_negative: a_max_ms >= 0
		local
			l_remaining_ms: INTEGER
			l_slept: BOOLEAN
		do
			lock.lock
			from
				l_remaining_ms := a_max_ms
			until
				wakes_since_arm > 0 or l_remaining_ms <= 0
			loop
				l_slept := condition.wait_with_timeout (lock, l_remaining_ms.min (Slice_ms))
				l_remaining_ms := l_remaining_ms - Slice_ms
			end
			Result := wakes_since_arm > 0
			lock.unlock
		ensure
			definition: Result = (wakes_since_arm > 0)
			still_armed: is_armed
		end

	disarm
		do
			lock.lock
			armed_room_id := 0
			wakes_since_arm := 0
			statuses.wipe_out
			lock.unlock
		ensure
			not_armed: not is_armed
		end

	wake (a_room_id: INTEGER_64)
		do
			lock.lock
			wake_count := wake_count + 1
			if a_room_id = armed_room_id then
				wakes_since_arm := wakes_since_arm + 1
				condition.broadcast
			end
			lock.unlock
		ensure then
			mine_counted: a_room_id = armed_room_id implies wakes_since_arm = old wakes_since_arm + 1
			others_ignored: a_room_id /= armed_room_id implies wakes_since_arm = old wakes_since_arm
		end

	receive_status (a_status: CHAT_STATUS)
		do
			lock.lock
			if a_status.room_id = armed_room_id then
				statuses.extend (a_status)
				condition.broadcast
			end
			lock.unlock
		ensure then
			kept_when_mine: a_status.room_id = armed_room_id implies statuses.count = old statuses.count + 1
			dropped_otherwise: a_status.room_id /= armed_room_id implies statuses.count = old statuses.count
		end

feature -- Constants

	Slice_ms: INTEGER = 250
			-- Wait in slices so a spurious wake-up never overshoots the deadline by much.

feature {NONE} -- Implementation

	lock: MUTEX
	condition: CONDITION_VARIABLE

invariant
	named: not subscriber_name.is_empty
	counts_non_negative: wake_count >= 0 and wakes_since_arm >= 0
	quiet_when_disarmed: not is_armed implies (wakes_since_arm = 0 and statuses.is_empty)

end
