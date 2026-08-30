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
		do
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501))
			-- Implementation in Phase 4: record_run around the call
		ensure then
			bounded_runtime: not last_timed_out implies elapsed_seconds <= timeout_seconds
			timeout_is_error: last_timed_out implies not Result.is_success
		end

feature {NONE} -- Implementation

	client: CLAUDE_CODE_CLIENT

invariant
	name_is_handle: (create {PARTICIPANT_RULES}).is_valid_handle (name)

end
