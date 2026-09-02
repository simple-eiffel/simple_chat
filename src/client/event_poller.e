note
	description: "[
		The client's long-poll machine, meant to live on its own processor
		with a CHAT_CLIENT and transport of its own (approach section 8):
		`run' loops `poll_once' until the inbox says stop or the session
		is lost, and nothing it blocks on is shared with the GUI.

		`poll_once' is the unit of work: one wait_for_events from `cursor',
		and `run' asks for `Poll_slice_seconds' of it - never more, because
		the whole of an exchange is spent inside a C call the garbage
		collector cannot interrupt, and every processor in the system,
		the GUI's included, stops at its next allocation until it returns.
		A page with news is handed to the EVENT_INBOX as the raw bytes it
		came in (`deliver' - the inbox copies them; nothing but bytes
		crosses), and the cursor moves to the page's last id only when
		the inbox took the page: `wait_for_room' first blocks this
		processor until the inbox has room or has been stopped (a SCOOP
		wait condition), and `deliver' answers False, moving nothing,
		once it is stopped. So no page is ever lost between the server
		and the GUI: the next poll asks again for whatever the inbox did
		not take. A page the client refused (foreign room, not after the
		cursor, not ascending) is a failure like any other and moves
		nothing. Failures back off (`backoff_seconds': 0 when healthy,
		doubling, capped at `Backoff_maximum_seconds') so a dead or
		refusing server is never hammered, and each is reported to the
		inbox so the GUI can say so; a 401 loses the session
		(`session_lost'), is reported as such (`report_lost', distinct
		from an outage) and ends the loop rather than spinning on it.
		Successes have a floor too: from the second quiet poll in a row
		(nothing came) `run' waits `Quiet_floor_seconds' (`pause_seconds'),
		so a server that answers an empty page at once is not polled in a
		tight loop. Since `Poll_slice_seconds' is 0 - see the constant for
		why the GUI's allocator cannot afford a held connection - that
		floor is what paces a quiet room, and what a first message into
		one may cost.

		The inbox is held only for the moment of a call that names it
		(`should_stop', `wait_for_room', `deliver', `report',
		`report_lost', `recover'): never across the long poll, so the
		GUI's `take' is never made to wait.

		Laws: the cursor never goes backwards and moves only past a page
		the inbox took; every poll is counted; a failure is always
		explained by `last_error'; healthy is quiet; quiet is free once.
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
			fresh: polls = 0 and consecutive_failures = 0 and delivered = 0 and quiet_polls = 0 and not session_lost and not last_was_quiet
			quiet: backoff_seconds = 0 and pause_seconds = 0
		end

feature -- Access

	room_id: INTEGER_64

	cursor: INTEGER_64
			-- The highest id the inbox took; the next poll asks for what follows it.

	polls: INTEGER
			-- `poll_once' calls so far.

	consecutive_failures: INTEGER
			-- Failed polls since the last success.

	quiet_polls: INTEGER
			-- Successive successful polls that brought nothing (no events, no statuses);
			-- 0 again after a page, and after a failure.

	delivered: INTEGER
			-- Pages the inbox took so far.

	last_error: detachable CHAT_ERROR
			-- Why the last poll failed; Void after a success.

	backoff_seconds: INTEGER
			-- How long a failure makes `run' wait before the next poll: nothing while healthy,
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

	pause_seconds: INTEGER
			-- What `run' waits before the next poll: the failure backoff, else `Quiet_floor_seconds'
			-- after every quiet poll beyond the first (a server that honors `seconds' never answers
			-- quiet in under a second, so a healthy server never pays it), else nothing.
		do
			if consecutive_failures > 0 then
				Result := backoff_seconds
			elseif quiet_polls > 1 then
				Result := Quiet_floor_seconds
			end
		ensure
			failure_backoff: consecutive_failures > 0 implies Result = backoff_seconds
			quiet_floor: (consecutive_failures = 0 and quiet_polls > 1) implies Result = Quiet_floor_seconds
			eager_when_busy: (consecutive_failures = 0 and quiet_polls <= 1) implies Result = 0
		end

feature -- Status report

	session_lost: BOOLEAN
			-- Did the server answer 401? The token is dead; no further poll is attempted.

	last_was_quiet: BOOLEAN
			-- Did the last poll succeed and bring nothing (no events, no statuses)?

	should_stop (a_inbox: separate EVENT_INBOX): BOOLEAN
			-- Has the GUI asked, through the inbox, for polling to end?
		do
			Result := a_inbox.is_stopped
		end

feature -- Basic operations

	poll_once (a_wait_seconds: INTEGER)
			-- One long-poll from `cursor'; hand what came to the inbox and advance the cursor past
			-- what it took, or count the failure.
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
				last_was_quiet := p.is_empty
				if p.is_empty then
					quiet_polls := quiet_polls + 1
				else
					quiet_polls := 0
					wait_for_room (inbox)
					if deliver (inbox, p.bytes) then
						cursor := cursor.max (p.last_id)
					end
				end
			else
				consecutive_failures := consecutive_failures + 1
				quiet_polls := 0
				last_was_quiet := False
				last_error := l_result.error
				if attached l_result.error as err then
					session_lost := err.http_status = 401
					if session_lost then
						report_lost (inbox, err.message)
					else
						report (inbox, err.message)
					end
				end
			end
		ensure
			polled: polls = old polls + 1
			cursor_monotonic: cursor >= old cursor
			failure_explained: (consecutive_failures > 0) = (last_error /= Void)
			failures_step: consecutive_failures = 0 or consecutive_failures = old consecutive_failures + 1
			delivered_monotonic: delivered >= old delivered
			moved_only_by_delivery: cursor > old cursor implies delivered = old delivered + 1
			quiet_counted: last_was_quiet implies quiet_polls = old quiet_polls + 1
			busy_resets: (last_error = Void and not last_was_quiet) implies quiet_polls = 0
			failure_resets: last_error /= Void implies quiet_polls = 0
			lost_on_401: session_lost = (attached last_error as e and then e.http_status = 401)
			room_kept: room_id = old room_id
		end

	run
			-- The loop: until the inbox says stop or the session is lost, poll for
			-- `Poll_slice_seconds', then wait out `pause_seconds'. Blocks the caller's processor
			-- for as long as it runs - the poller's own, by design - but never blocks it INSIDE
			-- THE TRANSPORT for longer than one slice, which is what the GUI's allocator pays for.
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			from
			until
				session_lost or else should_stop (inbox)
			loop
				poll_once (Poll_slice_seconds)
				if pause_seconds > 0 and then not session_lost and then not should_stop (inbox) then
					l_env.sleep (pause_seconds.to_integer_64 * Nanoseconds_per_second)
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

	Quiet_floor_seconds: INTEGER = 1
			-- What a quiet poll costs after the first in a row: enough to end a tight loop, too little to notice.

	Poll_slice_seconds: INTEGER = 0
			-- How long ONE exchange may keep this processor INSIDE THE TRANSPORT.
			--
			-- ISE's collector stops every thread in the system before it collects, and a
			-- thread inside a plain `external "C inline"' call - which is what
			-- SIMPLE_WINHTTP.c_send is for the whole of an exchange - is where the runtime
			-- cannot see it and cannot stop it. So a collection anywhere in the system waits
			-- for this processor's exchange to come back, and the GUI's very next allocation
			-- - a string, an MML sequence in a postcondition, a shaped line - waits with it.
			-- A 25 s long poll therefore froze the window for up to 25 s at a time (measured
			-- on the live stack: 21,058 ms, while every call this class makes on the inbox
			-- came back inside 2 ms). That is the defect phase4/freeze was opened for, and
			-- nothing about it is this project's own concurrency: an Eiffel sleep of the same
			-- length on the same processor costs the root 1 ms.
			--
			-- Zero asks the server to answer NOW - CHAT_REQUEST_HANDLER.handle_wait holds the
			-- doorbell only while `seconds' > 0 - so an exchange lasts one round trip, and one
			-- round trip is the most the window can ever be stopped for. What it costs is the
			-- doorbell: the FIRST message into a room that has gone quiet arrives up to
			-- `Quiet_floor_seconds' late instead of at once. Everything after it is immediate
			-- again, because a page resets `quiet_polls' and `pause_seconds' is 0 once more.
			--
			-- The one-line change that would give both back lives in another repository: mark
			-- SIMPLE_WINHTTP.c_send `blocking', so the runtime releases the collector across
			-- it. Then, and only then, this may go back to {CHAT_CLIENT}.Max_wait_seconds.

	Nanoseconds_per_second: INTEGER_64 = 1000000000

feature {NONE} -- The inbox (each a short, separate call)

	wait_for_room (a_inbox: separate EVENT_INBOX)
			-- Block this processor until the inbox can take a page, or it has been stopped: the
			-- precondition is a SCOOP wait condition when the inbox lives on another processor
			-- (the lock is released while it is false). On one processor - the tests - it is a plain
			-- precondition: never poll a page into a full inbox that is not stopped.
		require
			room_or_stopped: not a_inbox.is_full or a_inbox.is_stopped
		do
		end

	deliver (a_inbox: separate EVENT_INBOX; a_bytes: STRING_8): BOOLEAN
			-- Hand `a_bytes' (one page as it came off the wire) to the inbox: True when it was queued
			-- and counted, False - nothing put, nothing counted - when the inbox is stopped. Never a
			-- drop: `wait_for_room' has just returned, and only this processor puts.
		require
			given: not a_bytes.is_empty
			room_or_stopped: not a_inbox.is_full or a_inbox.is_stopped
		do
			if not a_inbox.is_stopped then
				a_inbox.put (a_bytes)
				delivered := delivered + 1
				Result := True
			end
		ensure
			counted: Result implies delivered = old delivered + 1
			kept_when_not: not Result implies delivered = old delivered
			only_while_running: Result = not a_inbox.is_stopped
			not_dropped: a_inbox.dropped = old a_inbox.dropped
		end

	report (a_inbox: separate EVENT_INBOX; a_message: STRING_32)
			-- Tell the inbox the last poll failed.
		require
			message_given: not a_message.is_empty
		do
			a_inbox.report_outage (a_message)
		ensure
			reported: a_inbox.has_outage
		end

	report_lost (a_inbox: separate EVENT_INBOX; a_message: STRING_32)
			-- Tell the inbox the server rejected the session: the token is dead and this loop ends.
		require
			message_given: not a_message.is_empty
		do
			a_inbox.report_session_lost (a_message)
		ensure
			lost: a_inbox.is_session_lost
			reported: a_inbox.has_outage
		end

	recover (a_inbox: separate EVENT_INBOX)
			-- Tell the inbox polling succeeds again.
		require
			session_alive: not session_lost
		do
			a_inbox.report_recovery
		ensure
			cleared: not a_inbox.has_outage
		end

feature {NONE} -- Implementation

	client: CHAT_CLIENT

	inbox: separate EVENT_INBOX

invariant
	cursor_non_negative: cursor >= 0
	counts_non_negative: polls >= 0 and consecutive_failures >= 0 and delivered >= 0 and quiet_polls >= 0
	failure_explained: (consecutive_failures > 0) = (last_error /= Void)
	quiet_when_healthy: consecutive_failures = 0 implies backoff_seconds = 0
	quiet_definition: (quiet_polls > 0) = last_was_quiet
	quiet_is_healthy: last_was_quiet implies consecutive_failures = 0
	lost_is_explained: session_lost implies last_error /= Void

end
