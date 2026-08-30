note
	description: "[
		A participant that runs a program or a query with the member's
		request as its argument. The safety rule of addendum 09 is a
		contract here: the request - shaped or raw - reaches the tool only
		as an argument list the tool's own allowlist accepted; never a
		shell string; never unbounded in size or time. The reply echoes
		what was actually run, so the room sees it.
	]"
	author: "Larry Rix"

deferred class
	TOOL_PARTICIPANT

inherit
	PARTICIPANT

feature -- Access

	query_shaper: SHAPER
			-- Turns a free-form request into the tool's form; `NULL_SHAPER' passes it through.

	response_shaper: SHAPER
			-- Turns the raw result into prose; `NULL_SHAPER' leaves it mechanical.

	timeout_seconds: INTEGER

	elapsed_seconds: INTEGER
			-- How long the last run took.

	executed_query: STRING_32
			-- What was last run, as shown to the room; empty before any run.

feature -- Status report

	is_safe_argument (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_text' match this tool's allowlist of argument shapes?
		deferred
		end

feature -- Element change

	set_query_shaper (a_shaper: SHAPER)
		do
			query_shaper := a_shaper
		ensure
			set: query_shaper = a_shaper
		end

	set_response_shaper (a_shaper: SHAPER)
		do
			response_shaper := a_shaper
		ensure
			set: response_shaper = a_shaper
		end

feature -- Basic operations

	answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
			-- Shape the query (if a shaper is set), validate it, run the
			-- tool with an argument list, shape the response, echo the query.
		do
			calls := calls + 1
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501))
			-- Implementation in Phase 4
		ensure then
			refused_when_unsafe: (not is_safe_argument (a_request.text) and query_shaper.cost_tier = {SHAPER}.Tier_none) implies not Result.is_success
			bounded_runtime: elapsed_seconds <= timeout_seconds
			reply_echoes_query: Result.is_success implies Result.text.has_substring (executed_query)
			phrasing_disclosed: (Result.is_success and response_shaper.cost_tier > {SHAPER}.Tier_none) implies Result.text.has_substring (Phrased_by_prefix)
		end

	run_tool (a_arguments: ARRAYED_LIST [STRING_32]): STRING_32
			-- The tool's raw output for `a_arguments', passed as an argument
			-- list - never joined into a command line.
		require
			all_safe: across a_arguments as a all is_safe_argument (a) end
		deferred
		ensure
			timed: elapsed_seconds >= 0 and elapsed_seconds <= timeout_seconds
		end

feature -- Constants

	Phrased_by_prefix: STRING_32 = "phrased by "
			-- The footer a shaped reply carries: "phrased by @qwen".

invariant
	timeout_positive: timeout_seconds > 0
	elapsed_bounded: elapsed_seconds >= 0 and elapsed_seconds <= timeout_seconds

end
