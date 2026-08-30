note
	description: "[
		The GUI's letterbox, meant to live on its own processor (approach
		section 8): the poller `put's the raw bytes of every page it
		accepted - an asynchronous call that copies the bytes onto this
		processor - and the presenter `take's them oldest first and
		decodes on the root. Nothing here blocks, so the GUI never waits
		on the network: the poller's 30 s inside WinHTTP happen on the
		poller's processor with this one unlocked.

		Also the poller's health as the GUI sees it (`outage', reported
		by the poller on every failed poll and cleared when a poll
		succeeds again) and the GUI's one signal to the poller: `stop' -
		the poller reads `is_stopped' before each poll and its `run' loop
		ends. Once stopped, stays stopped.

		Bounded: `Capacity' pages; a page arriving when full or after
		`stop' is dropped and counted (`dropped') rather than growing
		without limit while the window is stuck. `take' is a query with
		an effect - the one CQS exception here, as `drain' was on the old
		EVENT_POLLER - because a separate query is the only synchronous
		way to hand bytes across processors in one locked step. Only
		bytes cross: every string is copied with `make_from_separate'.
	]"
	author: "Larry Rix"

class
	EVENT_INBOX

create
	make

feature {NONE} -- Initialization

	make
		do
			create pages.make (Capacity)
		ensure
			empty: count = 0
			running: not is_stopped
			nothing_dropped: dropped = 0
			no_outage: not has_outage
		end

feature -- Model Queries (for MML postconditions)

	pages_model: MML_SEQUENCE [STRING_8]
			-- The pages not yet taken, oldest first.
		do
			create Result
			across pages as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = pages.count
		end

feature -- Access

	count: INTEGER
			-- Pages waiting to be taken.
		do
			Result := pages.count
		ensure
			non_negative: Result >= 0
		end

	dropped: INTEGER
			-- Pages refused because the inbox was full or stopped.

	outage: detachable STRING_32
			-- What the poller last reported; Void while its polls succeed.

feature -- Status report

	is_full: BOOLEAN
		do
			Result := count >= Capacity
		ensure
			definition: Result = (count >= Capacity)
		end

	is_stopped: BOOLEAN
			-- Has the GUI asked the poller to end?

	has_outage: BOOLEAN
		do
			Result := outage /= Void
		end

feature -- Element change

	put (a_page_bytes: separate READABLE_STRING_8)
			-- Queue a copy of `a_page_bytes'; dropped, and counted, when full or stopped.
		local
			l_copy: STRING_8
		do
			if is_full or is_stopped then
				dropped := dropped + 1
			else
				create l_copy.make_from_separate (a_page_bytes)
				pages.extend (l_copy)
			end
		ensure
			accepted: (not old is_full and not old is_stopped) implies (count = old count + 1 and (old pages_model) <= pages_model)
			same_bytes: (not old is_full and not old is_stopped) implies pages_model.last.count = a_page_bytes.count
			refused: (old is_full or old is_stopped) implies (count = old count and dropped = old dropped + 1)
			accounted: count + dropped = old count + old dropped + 1
			bounded: count <= Capacity
		end

	take: detachable STRING_8
			-- The oldest page, removed; Void when there is none.
		do
			if not pages.is_empty then
				Result := pages.first
				pages.start
				pages.remove
			end
		ensure
			void_iff_was_empty: (Result = Void) = (old count = 0)
			oldest: attached Result as r implies (r = (old pages_model).first and pages_model |=| (old pages_model).but_first)
			one_fewer: attached Result implies count = old count - 1
			dropped_kept: dropped = old dropped
		end

	report_outage (a_message: separate READABLE_STRING_32)
			-- The poller's last poll failed for `a_message' (a stock message when empty).
		local
			l_copy: STRING_32
		do
			create l_copy.make_from_separate (a_message)
			if l_copy.is_empty then
				outage := Message_unexplained
			else
				outage := l_copy
			end
		ensure
			reported: has_outage
			pages_kept: pages_model |=| old pages_model
		end

	report_recovery
			-- The poller's last poll succeeded.
		do
			outage := Void
		ensure
			cleared: not has_outage
			pages_kept: pages_model |=| old pages_model
		end

	stop
			-- Tell the poller to end; pages arriving from now on are dropped.
		do
			is_stopped := True
		ensure
			stopped: is_stopped
			pages_kept: pages_model |=| old pages_model
		end

feature -- Constants

	Capacity: INTEGER = 64
			-- Pages held at most; at 200 events a page, far more than a GUI pumping every tick ever sees.

	Message_unexplained: STRING_32 = "The server is not answering"

feature {NONE} -- Implementation

	pages: ARRAYED_LIST [STRING_8]

invariant
	bounded: count <= Capacity
	full_definition: is_full = (count >= Capacity)
	dropped_non_negative: dropped >= 0
	outage_explained: attached outage as o implies not o.is_empty
	model_consistent: pages_model.count = pages.count

end
