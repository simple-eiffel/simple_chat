note
	description: "[
		A one-shot timer on its own processor: sleeps `seconds', then
		times out its waiter. It never holds the waiter while sleeping -
		the waiter is an attribute here and is locked only for the instant
		of `time_out' - so the bus's wakes are never delayed by an alarm.
		Create it `separate' and call `start' as a separate command.
	]"
	author: "Larry Rix"

class
	POLL_ALARM

create
	make

feature {NONE} -- Initialization

	make (a_waiter: separate POLL_WAITER; a_seconds: INTEGER)
		require
			non_negative: a_seconds >= 0
		do
			waiter := a_waiter
			seconds := a_seconds
		ensure
			set: waiter = a_waiter and seconds = a_seconds
			not_fired: not has_fired
		end

feature -- Access

	seconds: INTEGER

feature -- Status report

	has_fired: BOOLEAN

feature -- Basic operations

	start
			-- Sleep `seconds', then time the waiter out.
		require
			once_only: not has_fired
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			if seconds > 0 then
				create l_env
				l_env.sleep (seconds.to_integer_64 * 1_000_000_000)
			end
			expire (waiter)
			has_fired := True
		ensure
			fired: has_fired
		end

feature {NONE} -- Implementation

	waiter: separate POLL_WAITER

	expire (a_waiter: separate POLL_WAITER)
			-- The only moment the waiter is held.
		do
			a_waiter.time_out
		end

invariant
	non_negative: seconds >= 0

end
