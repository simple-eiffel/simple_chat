note
	description: "[
		A shaper on Claude through CLAUDE_CODE_CLIENT: chosen with
		`via @claude', costs subscription quota (Tier_subscription). Bounded
		in time like every engine (TIMED_ENGINE, Issue 26).
	]"
	author: "Larry Rix"

class
	CLAUDE_SHAPER

inherit
	SHAPER

	TIMED_ENGINE

create
	make

feature {NONE} -- Initialization

	make (a_name: READABLE_STRING_GENERAL; a_client: CLAUDE_CODE_CLIENT; a_timeout_seconds: INTEGER)
		require
			name_is_handle: (create {PARTICIPANT_RULES}).is_valid_handle (a_name)
			timeout_positive: a_timeout_seconds > 0
		do
			create name.make_from_string_general (a_name)
			client := a_client
			timeout_seconds := a_timeout_seconds
		ensure
			name_set: name.same_string_general (a_name)
			timeout_set: timeout_seconds = a_timeout_seconds
		end

feature -- Access

	name: STRING_32

	cost_tier: INTEGER
		do
			Result := Tier_subscription
		end

feature -- Basic operations

	shape (a_text: READABLE_STRING_GENERAL; a_brief: SHAPING_BRIEF): SHAPED_TEXT
			-- <Precursor>: one CLI call - the brief becomes the system
			-- prompt (`instruction_of'), the text the user prompt. The
			-- bound is advisory (the client cannot kill the CLI): an
			-- overrun, a failure or a raising engine is an error result,
			-- never an exception.
		local
			l_started, l_now: SIMPLE_DATE_TIME
			l_response: detachable AI_RESPONSE
			l_failed: BOOLEAN
		do
			create l_started.make_now
			if not l_failed then
				l_response := client.ask_with_system (instruction_of (a_brief), a_text.to_string_32)
			end
			create l_now.make_now
			record_run ((l_now.to_timestamp - l_started.to_timestamp).to_integer_32.max (0))
			if l_failed or l_response = Void then
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, "the shaper raised instead of answering", 503))
			elseif last_timed_out then
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, "no shaping within " + timeout_seconds.out + " seconds", 503))
			elseif attached l_response as l_r and then l_r.is_success and then not l_r.text.is_empty then
				create Result.make_success (l_r.text.head (a_brief.max_characters))
			else
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, "Claude could not shape the text", 503))
			end
		ensure then
			bounded_runtime: not last_timed_out implies elapsed_seconds <= timeout_seconds
			timeout_is_error: last_timed_out implies not Result.is_success
		rescue
				-- One retry only; a second exception propagates instead of
				-- looping the rescue forever.
			if not l_failed then
				l_failed := True
				retry
			end
		end

feature {NONE} -- Implementation

	client: CLAUDE_CODE_CLIENT

invariant
	name_is_handle: (create {PARTICIPANT_RULES}).is_valid_handle (name)

end
