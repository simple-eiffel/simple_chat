note
	description: "[
		Where a summary lands when it arrives. A mailbox on its own
		processor that NEVER blocks: every routine here is a field
		assignment or a field read, so a call the GUI makes on it returns
		in the time of one call and can never queue behind the engine.

		That is the whole point. A summary is a `claude -p' call and takes
		seconds; Windows ghosts a window that stops pumping for about five
		of them and DISCARDS the keystrokes aimed at the ghost (see
		.eiffel-workflow/evidence/phase4-freeze.txt). So the request runs
		on SUMMARY_HOST's processor and the answer is left here, and the
		window's 250 ms tick collects it with one short call - the same
		shape as EVENT_INBOX between the poller and the GUI.
	]"
	author: "Larry Rix"

class
	SUMMARY_SLOT

create
	make

feature {NONE} -- Initialization

	make
		do
			create text.make_empty
		ensure
			idle: not is_waiting and not has_outcome
			nothing_yet: requests = 0 and outcomes = 0
		end

feature -- Access

	text: STRING_32
			-- The summary, or the reason there is none; empty until one lands.

	requests: INTEGER
			-- How many summaries have been asked for through this slot.

	outcomes: INTEGER
			-- How many have come back.

feature -- Status report

	is_waiting: BOOLEAN
			-- Is a summary in flight?

	has_outcome: BOOLEAN
			-- Is there something to show?

	is_failure: BOOLEAN
			-- Is the outcome a refusal rather than a summary?

feature -- Element change

	note_request
			-- One summary is now in flight; whatever was here is stale.
		do
			requests := requests + 1
			is_waiting := True
			has_outcome := False
			is_failure := False
			create text.make_empty
		ensure
			waiting: is_waiting
			cleared: not has_outcome
			counted: requests = old requests + 1
		end

	put_text (a_text: separate READABLE_STRING_32)
			-- The summary arrived. Copied here, so nothing of the host's
			-- processor is held once this returns.
		require
			given: not a_text.is_empty
		do
			create text.make_from_separate (a_text)
			has_outcome := True
			is_failure := False
			is_waiting := False
			outcomes := outcomes + 1
		ensure
			ready: has_outcome and not is_waiting and not is_failure
			counted: outcomes = old outcomes + 1
		end

	put_failure (a_message: separate READABLE_STRING_32)
			-- There is no summary, and this is why.
		require
			given: not a_message.is_empty
		do
			create text.make_from_separate (a_message)
			has_outcome := True
			is_failure := True
			is_waiting := False
			outcomes := outcomes + 1
		ensure
			ready: has_outcome and not is_waiting and is_failure
			counted: outcomes = old outcomes + 1
		end

	clear
			-- Taken and shown.
		do
			has_outcome := False
			is_failure := False
			create text.make_empty
		ensure
			empty: not has_outcome and text.is_empty
			request_count_kept: requests = old requests and outcomes = old outcomes
		end

invariant
	counts_non_negative: requests >= 0 and outcomes >= 0
	outcomes_within_requests: outcomes <= requests
	nothing_shown_while_waiting: is_waiting implies not has_outcome
	failure_needs_an_outcome: is_failure implies has_outcome

end
