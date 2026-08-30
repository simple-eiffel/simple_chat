note
	description: "[
		The blocking half of a long-poll, run on the request's processor.
		`wait_for' has a SCOOP wait condition: its precondition on the
		separate waiter is re-evaluated by the runtime until it holds, so
		the caller sleeps until the bus wakes the waiter or the alarm times
		it out - no MUTEX, no CONDITION_VARIABLE, no polling loop. What it
		saw is copied out (`woke_with_news', `statuses_json') so the
		handler never touches the waiter again.
	]"
	author: "Larry Rix"

class
	POLL_WAIT

create
	make

feature {NONE} -- Initialization

	make
		do
			create statuses_json.make_from_string ("[]")
		ensure
			not_waited: not has_waited
		end

feature -- Access

	statuses_json: STRING_8
			-- The statuses the waiter kept, as a JSON array; "[]" before `wait_for'.

feature -- Status report

	has_waited: BOOLEAN

	woke_with_news: BOOLEAN
			-- Did the wait end because the room had news (rather than the alarm)?

feature -- Basic operations

	wait_for (a_waiter: separate POLL_WAITER)
			-- Block until `a_waiter' has news or has timed out.
		require
			ready: a_waiter.is_ready
		do
			woke_with_news := a_waiter.has_news
			create statuses_json.make_from_separate (a_waiter.statuses_json)
			has_waited := True
		ensure
			waited: has_waited
			faithful: woke_with_news = a_waiter.has_news
		end

invariant
	array_text: statuses_json.starts_with ("[")

end
