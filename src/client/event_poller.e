note
	description: "[
		The client's long-poll machine, meant to live on its own processor
		with a CHAT_CLIENT and transport of its own (approach section 8):
		`run' loops `poll_once' until the inbox says stop or the session
		is lost, and nothing it blocks on is shared with the GUI.

		`poll_once' is the unit of work: one wait_for_events from `cursor'.
		A page with news is handed to the EVENT_INBOX as the raw bytes it
		came in (`deliver' - the inbox copies them; nothing but bytes
		crosses) and the cursor moves to the page's last id; a page the
		client refused (foreign room, not after the cursor, not ascending)
		is a failure like any other and moves nothing. Failures back off
		(`backoff_seconds': 0 when healthy, doubling, capped at
		`Backoff_maximum_seconds') so a dead or refusing server is never
		hammered, and each is reported to the inbox so the GUI can say so;
		a 401 loses the session (`session_lost') and ends the loop rather
		than spinning on it.

		The inbox is held only for the moment of a call that names it
		(`should_stop', `deliver', `report', `recover'): never across the
		long poll, so the GUI's `take' is never made to wait.

		Laws: the cursor never goes backwards; every poll is counted;
		a failure is always explained by `last_error'; healthy is quiet.
	]"
	author: "Larry Rix"

class
	EVENT_POLLER

create
	make

feature {NONE} -- Initialization

	make (a_client: CHAT_CLIENT; a_room_id, a_since_id: INTEGER_64; a_inbox: separate EVENT_INBOX)
		require
			logged_in: a_client.is_logged_in
			positive_room: a_room_id > 0
			since_non_negative: a_since_id >= 0
		do
			client := a_client
			room_id := a_room_id
			cursor := a_since_id
			inbox := a_inbox
		ensure
			set: room_id = a_room_id and cursor = a_since_id
			inbox_set: inbox = a_inbox
			fresh: polls = 0 and consecutive_failures = 0 and delivered = 0 and not session_lost
			quiet: backoff_seconds = 0
		end

feature -- Access

	room_id: INTEGER_64

	cursor: INTEGER_64
			-- The highest id delivered; the next poll asks for what follows it.

	polls: INTEGER
			-- `poll_once' calls so far.

	consecutive_failures: INTEGER
			-- Failed polls since the last success.

	delivered: INTEGER
			-- Pages handed to the inbox so far.

	last_error: detachable CHAT_ERROR
			-- Why the last poll failed; Void after a success.

	backoff_seconds: INTEGER
			-- How long `run' waits before the next poll: nothing while healthy,
			-- 1 s after one failure, doubling, never more than `Backoff_maximum_seconds'.
		local
			i: INTEGER
		do
			if consecutive_failures > 0 then
				from
					Result := 1
					i := 1
				until
					i >= consecutive_failures or Result >= Backoff_maximum_seconds
				loop
					Result := Result * 2
					i := i + 1
				end
				Result := Result.min (Backoff_maximum_seconds)
			end
		ensure
			quiet_when_healthy: consecutive_failures = 0 implies Result = 0
			waits_when_failing: consecutive_failures > 0 implies Result >= 1
			one_second_first: consecutive_failures = 1 implies Result = 1
			capped: Result <= Backoff_maximum_seconds
		end

feature -- Status report

	session_lost: BOOLEAN
			-- Did the server answer 401? The token is dead; no further poll is attempted.

	should_stop (a_inbox: separate EVENT_INBOX): BOOLEAN
			-- Has the GUI asked, through the inbox, for polling to end?
		do
			Result := a_inbox.is_stopped
		end

feature -- Basic operations

	poll_once (a_wait_seconds: INTEGER)
			-- One long-poll from `cursor'; deliver what came and advance the cursor, or count the failure.
		require
			seconds_in_range: a_wait_seconds >= 0 and a_wait_seconds <= {CHAT_CLIENT}.Max_wait_seconds
			session_alive: not session_lost
		local
			l_result: CHAT_RESULT [CHAT_PAGE]
		do
			l_result := client.wait_for_events (room_id, cursor, Page_size, a_wait_seconds)
			polls := polls + 1
			if l_result.is_success and then attached l_result.value as p then
				if consecutive_failures > 0 then
					recover (inbox)
				end
				consecutive_failures := 0
				last_error := Void
				if not p.is_empty then
					deliver (inbox, p.bytes)
					cursor := cursor.max (p.last_id)
				end
			else
				consecutive_failures := consecutive_failures + 1
				last_error := l_result.error
				if attached l_result.error as err then
					session_lost := err.http_status = 401
					report (inbox, err.message)
				end
			end
		ensure
			polled: polls = old polls + 1
			cursor_monotonic: cursor >= old cursor
			failure_explained: (consecutive_failures > 0) = (last_error /= Void)
			failures_step: consecutive_failures = 0 or consecutive_failures = old consecutive_failures + 1
			delivered_monotonic: delivered >= old delivered
			moved_only_by_delivery: cursor > old cursor implies delivered = old delivered + 1
			lost_on_401: session_lost = (attached last_error as e and then e.http_status = 401)
			room_kept: room_id = old room_id
		end

	run
			-- The loop: until the inbox says stop or the session is lost, poll for up to
			-- `Max_wait_seconds', then wait out the backoff. Blocks the caller's processor
			-- for as long as it runs - the poller's own, by design.
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			from
			until
				session_lost or else should_stop (inbox)
			loop
				poll_once ({CHAT_CLIENT}.Max_wait_seconds)
				if backoff_seconds > 0 and then not session_lost and then not should_stop (inbox) then
					l_env.sleep (backoff_seconds.to_integer_64 * Nanoseconds_per_second)
				end
			end
		ensure
			ended: session_lost or else should_stop (inbox)
			cursor_monotonic: cursor >= old cursor
			polls_monotonic: polls >= old polls
		end

feature -- Constants

	Page_size: INTEGER = 200

	Backoff_maximum_seconds: INTEGER = 30

	Nanoseconds_per_second: INTEGER_64 = 1000000000

feature {NONE} -- The inbox (each a short, separate call)

	deliver (a_inbox: separate EVENT_INBOX; a_bytes: STRING_8)
			-- Hand `a_bytes' (one page as it came off the wire) to the inbox.
		require
			given: not a_bytes.is_empty
		do
			a_inbox.put (a_bytes)
			delivered := delivered + 1
		ensure
			counted: delivered = old delivered + 1
		end

	report (a_inbox: separate EVENT_INBOX; a_message: STRING_32)
			-- Tell the inbox the last poll failed.
		do
			a_inbox.report_outage (a_message)
		end

	recover (a_inbox: separate EVENT_INBOX)
			-- Tell the inbox polling succeeds again.
		do
			a_inbox.report_recovery
		end

feature {NONE} -- Implementation

	client: CHAT_CLIENT

	inbox: separate EVENT_INBOX

invariant
	cursor_non_negative: cursor >= 0
	counts_non_negative: polls >= 0 and consecutive_failures >= 0 and delivered >= 0
	failure_explained: (consecutive_failures > 0) = (last_error /= Void)
	quiet_when_healthy: consecutive_failures = 0 implies backoff_seconds = 0
	lost_is_explained: session_lost implies last_error /= Void

end
