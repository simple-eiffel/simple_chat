note
	description: "[
		A processor that does nothing but wait, two ways: through
		EXECUTION_ENVIRONMENT.sleep, and inside a plain blocking C call of
		the shape every simple_* external takes (`external "C inline"',
		no `blocking' marker). The assault launches one of these on its
		own SCOOP processor and then measures how long an ALLOCATION on
		the root takes: ISE's collector stops every thread of the system,
		and a thread that is inside C where the runtime cannot see it
		cannot be stopped until it comes back.
	]"
	author: "Larry Rix"

class
	GC_PROBE

create
	make

feature {NONE} -- Initialization

	make
		do
		end

feature -- Access

	waits_done: INTEGER
			-- Waits completed so far.

feature -- Basic operations

	run_eiffel_sleeps (a_count, a_milliseconds: INTEGER)
			-- `a_count' waits of `a_milliseconds' through EXECUTION_ENVIRONMENT.
		require
			positive: a_count > 0 and a_milliseconds > 0
		local
			l_env: EXECUTION_ENVIRONMENT
			i: INTEGER
		do
			create l_env
			from
				i := 1
			until
				i > a_count
			loop
				l_env.sleep (a_milliseconds.to_integer_64 * 1_000_000)
				waits_done := waits_done + 1
				i := i + 1
			variant
				a_count + 1 - i
			end
		ensure
			done: waits_done = old waits_done + a_count
		end

	run_c_sleeps (a_count, a_milliseconds: INTEGER)
			-- `a_count' waits of `a_milliseconds' inside a blocking C call - the shape
			-- SIMPLE_WINHTTP's `c_send' takes for a whole long poll.
		require
			positive: a_count > 0 and a_milliseconds > 0
		local
			i: INTEGER
		do
			from
				i := 1
			until
				i > a_count
			loop
				c_sleep (a_milliseconds)
				waits_done := waits_done + 1
				i := i + 1
			variant
				a_count + 1 - i
			end
		ensure
			done: waits_done = old waits_done + a_count
		end

feature {NONE} -- Externals

	c_sleep (a_milliseconds: INTEGER)
			-- Block this thread in C, exactly as an unmarked external does.
		external
			"C inline use <windows.h>"
		alias
			"Sleep((DWORD) $a_milliseconds);"
		end

invariant
	non_negative: waits_done >= 0

end
