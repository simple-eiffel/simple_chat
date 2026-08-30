note
	description: "[
		A participant that runs a program or a query with the member's
		request as its argument. The safety rule of addendum 09 is a
		contract here: the request - shaped or raw - reaches the tool only
		as an argument list the tool's own allowlist accepted; never a
		shell string; never unbounded in size or time. `run_tool' records
		what ran (`executed_arguments'), so `answer' can promise that
		nothing unsafe ran on the raw path and on the shaped path alike
		(Issues 31, 38): what ran is exactly what `arguments_of' - the one
		gate - made of the request text or of the query shaper's output.

		`via' chooses the shaper for one request at both edges
		(`effective_query_shaper', `effective_response_shaper'; the choices
		are `shapers_model', "plain" always among them); the reply echoes
		what ran, names the shaper that phrased it, and never claims a
		phrasing that did not happen (Issue 32). A shaper that fails fails
		the answer. The limits are the tool's: an argument is at most
		`Argument_maximum' printable ASCII characters and never an option;
		output is cut at `Output_maximum'; a reply limit under
		`Minimum_reply_characters' is refused rather than lied about.

		`answer' is the template; descendants supply `is_safe_argument'
		(the allowlist) and `run_arguments' (Phase 4: the child process or
		the query, recording its own timing).
	]"
	author: "Larry Rix"

deferred class
	TOOL_PARTICIPANT

inherit
	PARTICIPANT

	TIMED_ENGINE

feature {NONE} -- Initialization

	initialize_tool (a_handle: READABLE_STRING_GENERAL; a_bot_user: CHAT_USER; a_description: READABLE_STRING_GENERAL; a_max_characters, a_timeout_seconds: INTEGER)
			-- The part of every tool's creation that is the same: identity, the plain shapers, empty records.
		require
			handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (a_handle)
			bot: a_bot_user.is_bot
			bot_stored: a_bot_user.is_stored
			bot_active: a_bot_user.is_active
			bot_marked: a_bot_user.display_name.has_substring ({CHAT_EVENT_KINDS}.Bot_marker)
			described: not a_description.is_empty
			max_positive: a_max_characters > 0
			timeout_positive: a_timeout_seconds > 0
		local
			l_plain: NULL_SHAPER
		do
			create handle.make_from_string_general (a_handle)
			bot_user := a_bot_user
			create description.make_from_string_general (a_description)
			max_characters := a_max_characters
			timeout_seconds := a_timeout_seconds
			max_concurrent := 2
			create l_plain.make
			query_shaper := l_plain
			response_shaper := l_plain
			create shapers.make (3)
			shapers.compare_objects
			shapers.put (l_plain, l_plain.name.as_lower)
			create executed_query.make_empty
			create executed_arguments.make (0)
			create last_shaped_query.make_empty
		ensure
			handle_set: handle.same_string_general (a_handle)
			described: description.same_string_general (a_description)
			max_set: max_characters = a_max_characters
			timeout_set: timeout_seconds = a_timeout_seconds
			plain_by_default: query_shaper.cost_tier = {SHAPER}.Tier_none and response_shaper.cost_tier = {SHAPER}.Tier_none
			plain_allowed: allows_via ({ADDRESS_PARSER}.Via_plain)
			nothing_ran: executed_model.is_empty and runs = 0
		end

feature -- Model Queries (for MML postconditions)

	executed_model: MML_SEQUENCE [STRING_32]
			-- The argument list of the last run, in order; empty before any run.
		do
			Result := sequence_of (executed_arguments)
		ensure
			same_count: Result.count = executed_arguments.count
		end

	shapers_model: MML_MAP [STRING_32, SHAPER]
			-- Lowercase name -> shaper, for every choice `via' may make.
		do
			create Result
			across shapers as ic loop
				Result := Result.updated (@ic.key, ic)
			end
		ensure
			same_count: Result.count = shapers.count
		end

	sequence_of (a_arguments: LIST [STRING_32]): MML_SEQUENCE [STRING_32]
			-- `a_arguments' as a sequence (contract support).
		do
			create Result
			across a_arguments as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = a_arguments.count
		end

	arguments_model_of (a_text: READABLE_STRING_GENERAL): MML_SEQUENCE [STRING_32]
			-- What `arguments_of (a_text)' gives, as a sequence (contract support).
		do
			Result := sequence_of (arguments_of (a_text))
		ensure
			same_count: Result.count = arguments_of (a_text).count
		end

feature -- Access

	description: STRING_32
			-- What this tool does, as a shaper is briefed.

	query_shaper: SHAPER
			-- Turns a free-form request into the tool's form; `NULL_SHAPER' passes it through.

	response_shaper: SHAPER
			-- Turns the raw result into prose; `NULL_SHAPER' leaves it mechanical.

	executed_query: STRING_32
			-- What last ran, as the room sees it: `echo_of (executed_arguments)'; empty before any run.

	executed_arguments: ARRAYED_LIST [STRING_32]
			-- The argument list of the last run, exactly as handed to the tool; empty before any run.

	runs: INTEGER
			-- Runs of the tool so far.

	last_shaped_query: STRING_32
			-- What the query shaper made of the last request; empty when no shaper ran or it failed.

	last_response_shaped: BOOLEAN
			-- Was the last reply phrased by a shaper (a tier above `Tier_none')?

	last_shaper_error: detachable CHAT_ERROR
			-- Why a shaper failed during the last `answer', or Void.

	shaper_for (a_choice: READABLE_STRING_GENERAL): SHAPER
			-- The shaper `via a_choice' selects.
		require
			allowed: allows_via (a_choice)
		do
			check allowed_means_present: attached shapers.item (a_choice.to_string_32.as_lower) as s then
				Result := s
			end
		ensure
			from_model: Result = shapers_model [a_choice.to_string_32.as_lower]
		end

	effective_query_shaper (a_request: PARTICIPANT_REQUEST): SHAPER
			-- The shaper `a_request' chose with `via', else the configured one.
		do
			if attached a_request.via as v and then allows_via (v) then
				Result := shaper_for (v)
			else
				Result := query_shaper
			end
		ensure
			chosen_when_allowed: (attached a_request.via as v and then allows_via (v)) implies Result = shaper_for (v)
			configured_otherwise: not (attached a_request.via as v and then allows_via (v)) implies Result = query_shaper
		end

	effective_response_shaper (a_request: PARTICIPANT_REQUEST): SHAPER
			-- The shaper `a_request' chose with `via', else the configured one.
		do
			if attached a_request.via as v and then allows_via (v) then
				Result := shaper_for (v)
			else
				Result := response_shaper
			end
		ensure
			chosen_when_allowed: (attached a_request.via as v and then allows_via (v)) implies Result = shaper_for (v)
			configured_otherwise: not (attached a_request.via as v and then allows_via (v)) implies Result = response_shaper
		end

feature -- Status report

	allows_via (a_choice: READABLE_STRING_GENERAL): BOOLEAN
			-- May a member choose `a_choice' with `via'?
		do
			Result := shapers.has (a_choice.to_string_32.as_lower)
		ensure
			definition: Result = shapers_model.domain.has (a_choice.to_string_32.as_lower)
		end

	is_safe_argument (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_text' match this tool's allowlist of argument shapes?
			-- The allowlist is the tool's; these are the laws every allowlist obeys.
		deferred
		ensure
			never_empty: Result implies not a_text.is_empty
			bounded: Result implies a_text.count <= Argument_maximum
			printable: Result implies is_printable_ascii (a_text)
			no_option: Result implies a_text.code (1) /= 45
		end

	is_printable_ascii (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Every character in 32..126?
		local
			i: INTEGER
		do
			Result := True
			from i := 1 until i > a_text.count or not Result loop
				Result := a_text.code (i) >= 32 and a_text.code (i) <= 126
				i := i + 1
			end
		end

feature -- Conversion (contract support)

	arguments_of (a_text: READABLE_STRING_GENERAL): ARRAYED_LIST [STRING_32]
			-- The argument list `a_text' becomes: one element - the text without
			-- surrounding blanks - when the allowlist accepts it; empty otherwise.
			-- The one gate both paths pass through.
		local
			l_trimmed: STRING_32
		do
			l_trimmed := trimmed (a_text)
			create Result.make (1)
			if is_safe_argument (l_trimmed) then
				Result.extend (l_trimmed)
			end
		ensure
			all_safe: across Result as a all is_safe_argument (a) end
			gated: Result.is_empty = not is_safe_argument (trimmed (a_text))
			one_at_most: Result.count <= 1
		end

	trimmed (a_text: READABLE_STRING_GENERAL): STRING_32
			-- A copy of `a_text' without leading and trailing blanks.
		do
			create Result.make_from_string_general (a_text)
			Result.left_adjust
			Result.right_adjust
		ensure
			within: not Result.is_empty implies a_text.has_substring (Result)
		end

	echo_of (a_arguments: LIST [STRING_32]): STRING_32
			-- `a_arguments' joined by single spaces: the echo line of a reply.
		do
			create Result.make_empty
			across a_arguments as ic loop
				if not Result.is_empty then
					Result.append_character (' ')
				end
				Result.append (ic)
			end
		ensure
			empty_when_none: a_arguments.is_empty implies Result.is_empty
		end

feature -- Element change

	set_query_shaper (a_shaper: SHAPER)
		require
			named_as_choice: (create {PARTICIPANT_RULES}).is_via_choice (a_shaper.name.as_lower)
		do
			query_shaper := a_shaper
		ensure
			set: query_shaper = a_shaper
			response_unchanged: response_shaper = old response_shaper
			choices_unchanged: shapers_model |=| old shapers_model
			nothing_ran: executed_model |=| old executed_model and runs = old runs
		end

	set_response_shaper (a_shaper: SHAPER)
		require
			named_as_choice: (create {PARTICIPANT_RULES}).is_via_choice (a_shaper.name.as_lower)
		do
			response_shaper := a_shaper
		ensure
			set: response_shaper = a_shaper
			query_unchanged: query_shaper = old query_shaper
			choices_unchanged: shapers_model |=| old shapers_model
			nothing_ran: executed_model |=| old executed_model and runs = old runs
		end

	add_shaper (a_shaper: SHAPER)
			-- Make `a_shaper' selectable with "via <its name>".
		require
			fresh: not allows_via (a_shaper.name)
			choice_shaped: (create {PARTICIPANT_RULES}).is_via_choice (a_shaper.name.as_lower)
		do
			shapers.put (a_shaper, a_shaper.name.as_lower)
		ensure
			added: shapers_model |=| (old shapers_model).updated (a_shaper.name.as_lower, a_shaper)
			allowed: allows_via (a_shaper.name)
			defaults_unchanged: query_shaper = old query_shaper and response_shaper = old response_shaper
		end

feature -- Basic operations

	answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
			-- Refuse what cannot be honoured; shape the query when a shaper
			-- applies; gate it; run; shape the response; compose the reply
			-- with its echo line and, when phrased, its footer.
		local
			l_query, l_output, l_text: STRING_32
			l_args: ARRAYED_LIST [STRING_32]
			l_shaped: SHAPED_TEXT
			l_error: detachable CHAT_ERROR
			l_query_shaper, l_response_shaper: SHAPER
		do
			calls := calls + 1
			last_shaper_error := Void
			last_response_shaped := False
			create last_shaped_query.make_empty
			create l_query.make_empty
			create l_text.make_empty
			l_query_shaper := effective_query_shaper (a_request)
			l_response_shaper := effective_response_shaper (a_request)
			if a_request.max_characters < Minimum_reply_characters then
				l_error := refusal ("the reply limit is too small for a tool answer")
			elseif attached a_request.via as v and then not allows_via (v) then
				l_error := refusal ({STRING_32} "unknown via: " + v)
			elseif l_query_shaper.cost_tier = {SHAPER}.Tier_none then
				l_query := a_request.text
			else
				l_shaped := l_query_shaper.shape (a_request.text, query_brief)
				if l_shaped.is_success then
					l_query := l_shaped.text
					last_shaped_query := l_shaped.text.twin
				else
					last_shaper_error := l_shaped.error
					l_error := l_shaped.error
				end
			end
			if l_error = Void then
				l_args := arguments_of (l_query)
				if l_args.is_empty then
					l_error := refusal ("not an accepted form for this tool")
				elseif echo_of (l_args).count + Reply_overhead > a_request.max_characters then
					l_error := refusal ("the request is too long to echo within the reply limit")
				else
					l_output := run_tool (l_args)
					if last_timed_out then
						l_error := unavailable ("the tool did not finish within " + timeout_seconds.out + " seconds")
					elseif l_output.is_empty then
						l_error := unavailable ("the tool produced no output")
					elseif l_response_shaper.cost_tier = {SHAPER}.Tier_none then
						l_text := l_output
					else
						l_shaped := l_response_shaper.shape (l_output, response_brief (a_request))
						if l_shaped.is_success then
							l_text := l_shaped.text
							last_response_shaped := True
						else
							last_shaper_error := l_shaped.error
							l_error := l_shaped.error
						end
					end
				end
			end
			if attached l_error as e then
				create Result.make_error (e)
			else
				create Result.make_success (composed (l_text, a_request.max_characters, l_response_shaper), Void)
			end
		ensure then
			only_safe_ran: across executed_arguments as a all is_safe_argument (a) end
			raw_gate: (effective_query_shaper (a_request).cost_tier = {SHAPER}.Tier_none and Result.is_success) implies executed_model |=| arguments_model_of (a_request.text)
			refused_when_unsafe: (effective_query_shaper (a_request).cost_tier = {SHAPER}.Tier_none and arguments_of (a_request.text).is_empty) implies not Result.is_success
			shaped_gate: (effective_query_shaper (a_request).cost_tier > {SHAPER}.Tier_none and Result.is_success) implies executed_model |=| arguments_model_of (last_shaped_query)
			shaped_refused: (effective_query_shaper (a_request).cost_tier > {SHAPER}.Tier_none and arguments_of (last_shaped_query).is_empty) implies not Result.is_success
			ran_when_success: Result.is_success implies runs = old runs + 1
			nothing_ran_when_gated: (arguments_of (a_request.text).is_empty and arguments_of (last_shaped_query).is_empty) implies runs = old runs
			unknown_via_refused: (attached a_request.via as v and then not allows_via (v)) implies not Result.is_success
			too_small_refused: a_request.max_characters < Minimum_reply_characters implies not Result.is_success
			echo_fits: Result.is_success implies executed_query.count + Reply_overhead <= a_request.max_characters
			bounded_runtime: not last_timed_out implies elapsed_seconds <= timeout_seconds
			timeout_is_error: last_timed_out implies not Result.is_success
			reply_echoes_query: Result.is_success implies Result.text.has_substring (executed_query)
			disclosure_consistent: Result.is_success implies last_response_shaped = (effective_response_shaper (a_request).cost_tier > {SHAPER}.Tier_none)
			phrasing_disclosed: (Result.is_success and last_response_shaped) implies Result.text.has_substring (Phrased_by_prefix + effective_response_shaper (a_request).name)
			no_false_disclosure: (Result.is_success and not last_response_shaped) implies not Result.text.has_substring (Footer_break + Phrased_by_prefix)
			shaper_failure_is_error: attached last_shaper_error as e implies (not Result.is_success and Result.error = e)
		end

	run_tool (a_arguments: ARRAYED_LIST [STRING_32]): STRING_32
			-- The tool's raw output for `a_arguments', passed as an argument
			-- list - never joined into a command line; recorded before it runs,
			-- bounded after.
		require
			some_arguments: not a_arguments.is_empty
			all_safe: across a_arguments as a all is_safe_argument (a) end
		local
			l_copy: ARRAYED_LIST [STRING_32]
		do
			create l_copy.make (a_arguments.count)
			across a_arguments as ic loop
				l_copy.extend (ic.twin)
			end
			executed_arguments := l_copy
			executed_query := echo_of (l_copy)
			runs := runs + 1
			Result := run_arguments (l_copy)
			if Result.count > Output_maximum then
				Result := Result.head (Output_maximum)
			end
		ensure
			recorded: executed_model |=| sequence_of (a_arguments)
			echoed: executed_query.same_string (echo_of (a_arguments))
			counted: runs = old runs + 1
			output_bounded: Result.count <= Output_maximum
			timed: elapsed_seconds >= 0
		end

feature {NONE} -- Implementation

	run_arguments (a_arguments: ARRAYED_LIST [STRING_32]): STRING_32
			-- The engine: Phase 4 starts the child process or runs the query
			-- with `a_arguments' as its argument list and records the timing
			-- (`record_run'); an empty result means the tool said nothing.
		require
			all_safe: across a_arguments as a all is_safe_argument (a) end
		deferred
		ensure
			timed: elapsed_seconds >= 0
		end

	query_brief: SHAPING_BRIEF
			-- How a query shaper is briefed: the tool, its forms, `Argument_maximum'.
		do
			create Result.make ({SHAPING_BRIEF}.Purpose_query, description, Argument_maximum)
		end

	response_brief (a_request: PARTICIPANT_REQUEST): SHAPING_BRIEF
			-- How a response shaper is briefed: the tool and the room's limit.
		do
			create Result.make ({SHAPING_BRIEF}.Purpose_response, description, a_request.max_characters)
		end

	composed (a_body: STRING_32; a_max_characters: INTEGER; a_shaper: SHAPER): STRING_32
			-- The reply: the echo line, `a_body' cut to fit, and the footer when phrased.
		require
			max_positive: a_max_characters > 0
			fits: executed_query.count + Reply_overhead <= a_max_characters
		local
			l_footer: STRING_32
		do
			create l_footer.make_empty
			if last_response_shaped then
				l_footer := Footer_break + Phrased_by_prefix + a_shaper.name
			end
			Result := Echo_prefix + executed_query + Footer_break
			Result.append (a_body.head ((a_max_characters - Result.count - l_footer.count).max (0)))
			Result.append (l_footer)
		ensure
			bounded: Result.count <= a_max_characters
			echoes: Result.has_substring (executed_query)
			disclosed: last_response_shaped implies Result.has_substring (Phrased_by_prefix + a_shaper.name)
		end

	refusal (a_message: READABLE_STRING_GENERAL): CHAT_ERROR
		require
			explained: not a_message.is_empty
		do
			create Result.make ({CHAT_ERROR}.Code_refused, a_message, 400)
		end

	unavailable (a_message: READABLE_STRING_GENERAL): CHAT_ERROR
		require
			explained: not a_message.is_empty
		do
			create Result.make ({CHAT_ERROR}.Code_unavailable, a_message, 503)
		end

	shapers: HASH_TABLE [SHAPER, STRING_32]
			-- The choices `via' may make, by lowercase name.

feature -- Constants

	Phrased_by_prefix: STRING_32 = "phrased by "
			-- The footer a shaped reply carries: "phrased by @qwen".

	Echo_prefix: STRING_32 = "> "
			-- The echo line begins with it.

	Footer_break: STRING_32 = "%N"

	Argument_maximum: INTEGER = 512
			-- The longest argument any tool accepts.

	Output_maximum: INTEGER = 65536
			-- Raw tool output is cut here.

	Minimum_reply_characters: INTEGER = 200
			-- Below this a tool cannot echo, answer and disclose: it refuses.

	Reply_overhead: INTEGER = 64
			-- Room kept beside the echo for the prefix, the break and the footer.

invariant
	described: not description.is_empty
	echo_recorded: executed_query.same_string (echo_of (executed_arguments))
	only_safe_recorded: across executed_arguments as a all is_safe_argument (a) end
	runs_non_negative: runs >= 0
	plain_allowed: allows_via ({ADDRESS_PARSER}.Via_plain)
	shapers_consistent: shapers_model.count = shapers.count

end
