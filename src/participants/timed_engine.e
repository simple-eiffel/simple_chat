note
	description: "[
		What every engine that waits on something outside the process
		reports (Issue 26): the ceiling it was given, how long the last
		call took, and whether it overran. The ceiling is advisory until
		simple_process can kill a child: a hung engine is reported as
		timed out, never clamped into the bound - `elapsed_seconds' is
		always the truth, and an overrun is always an error in the engine's
		own contract (`timeout_is_error').
	]"
	author: "Larry Rix"

deferred class
	TIMED_ENGINE

feature -- Access

	timeout_seconds: INTEGER
			-- The ceiling for one call, in seconds.

	elapsed_seconds: INTEGER
			-- How long the last call took; never clamped to the ceiling.

	last_timed_out: BOOLEAN
			-- Did the last call overrun `timeout_seconds'?

feature {NONE} -- Implementation

	record_run (a_elapsed_seconds: INTEGER)
			-- Note that the last call took `a_elapsed_seconds'.
		require
			non_negative: a_elapsed_seconds >= 0
		do
			elapsed_seconds := a_elapsed_seconds
			last_timed_out := a_elapsed_seconds > timeout_seconds
		ensure
			elapsed_set: elapsed_seconds = a_elapsed_seconds
			timed_out_when_over: last_timed_out = (a_elapsed_seconds > timeout_seconds)
			timeout_unchanged: timeout_seconds = old timeout_seconds
		end

invariant
	timeout_positive: timeout_seconds > 0
	elapsed_non_negative: elapsed_seconds >= 0
	overrun_is_timeout: elapsed_seconds > timeout_seconds implies last_timed_out

end
