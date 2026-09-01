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

		The metacharacter law (NEW-2): simple_process launches one command
		STRING (CreateProcess), not an argv array, so "argv, never a shell
		string" holds by construction of the arguments instead. Every
		element passes the base law before any tool's own rule: printable
		ASCII, no blank, none of `Forbidden_argument_characters' (quote,
		apostrophe, percent, caret, ampersand, pipe, redirection, semicolon,
		parentheses, bang, dollar, star, question mark, backquote,
		backslash), never an option, bounded. `command_line_of' is the only
		sanctioned joining: the program's path, then the elements separated
		by single spaces - a line whose shape safe words fully determine.

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
		redefine
			permits_via
		end

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

	last_raw_had_footer: BOOLEAN
			-- Did the last run's raw output itself contain the footer text
			-- ("%Nphrased by ")? Kept so `no_false_disclosure' stays
			-- satisfiable when a tool's own output quotes the phrase (NEW-8).

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

	permits_via (a_choice: READABLE_STRING_GENERAL): BOOLEAN
			-- <Precursor>: a tool takes exactly its configured shaper choices.
		do
			Result := allows_via (a_choice)
		ensure then
			definition: Result = allows_via (a_choice)
		end

	is_safe_argument (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Is `a_text' one safe argv element: the base law of every tool
			-- (`obeys_base_law', NEW-2) - checked first - and then this
			-- tool's own `accepts_word'?
		do
			Result := obeys_base_law (a_text) and then accepts_word (a_text)
		ensure
			definition: Result = (obeys_base_law (a_text) and then accepts_word (a_text))
			never_empty: Result implies not a_text.is_empty
			bounded: Result implies a_text.count <= Argument_maximum
			printable: Result implies is_printable_ascii (a_text)
			no_option: Result implies a_text.code (1) /= 45
			no_blank: Result implies not a_text.has (' ')
			no_shell_metacharacters: Result implies not has_any_of (a_text, Forbidden_argument_characters)
		end

	obeys_base_law (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- The metacharacter law every tool obeys before its own rule
			-- (NEW-2): 1..`Argument_maximum' characters, each in 33..126 (no
			-- control character, no blank), none of
			-- `Forbidden_argument_characters', and not beginning with "-"
			-- (a leading "/" is admitted: it is bible.exe's own command
			-- prefix, not a Windows option).
		local
			i: INTEGER
		do
			Result := not a_text.is_empty and a_text.count <= Argument_maximum and then a_text.code (1) /= 45
			from i := 1 until i > a_text.count or not Result loop
				Result := a_text.code (i) >= 33 and a_text.code (i) <= 126
					and not Forbidden_argument_characters.has_code (a_text.code (i))
				i := i + 1
			end
		ensure
			never_empty: Result implies not a_text.is_empty
			bounded: Result implies a_text.count <= Argument_maximum
			no_blank: Result implies not a_text.has (' ')
			no_metacharacters: Result implies not has_any_of (a_text, Forbidden_argument_characters)
		end

	accepts_word (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_text' - one blank-free word past the base law - match
			-- this tool's own allowlist?
		deferred
		end

	accepts_request (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- This tool's rule over the whole trimmed request, on top of the
			-- per-word law: True here; descendants narrow it (a Bible
			-- request needs a digit or an allowed command; a shape request
			-- is one slug).
		do
			Result := True
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

	has_any_of (a_text: READABLE_STRING_GENERAL; a_set: READABLE_STRING_8): BOOLEAN
			-- Does `a_text' contain any character of `a_set'?
		local
			i: INTEGER
		do
			from i := 1 until i > a_text.count or Result loop
				Result := a_set.has_code (a_text.code (i))
				i := i + 1
			end
		end

feature -- Conversion (contract support)

	arguments_of (a_text: READABLE_STRING_GENERAL): ARRAYED_LIST [STRING_32]
			-- The argument list `a_text' becomes: its blank-separated words,
			-- when the tool's whole-request rule holds (`accepts_request')
			-- and every word passes `is_safe_argument'; empty otherwise.
			-- The one gate both paths pass through; `command_line_of' joins
			-- the elements with single spaces, so the command line's shape
			-- is fully determined here (NEW-2).
		do
			if accepts (a_text) then
				Result := words_of (trimmed (a_text))
			else
				create Result.make (0)
			end
		ensure
			all_safe: across Result as a all is_safe_argument (a) end
			gated: Result.is_empty = not accepts (a_text)
			whole_request: not Result.is_empty implies Result.count = words_of (trimmed (a_text)).count
		end

	accepts (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Does the one gate pass `a_text': some words, the whole-request
			-- rule, and every word safe? (`arguments_of' is empty exactly
			-- when this is False.)
		local
			l_words: ARRAYED_LIST [STRING_32]
		do
			l_words := words_of (trimmed (a_text))
			Result := not l_words.is_empty and then accepts_request (trimmed (a_text))
			across l_words as w loop
				Result := Result and then is_safe_argument (w)
			end
		ensure
			some_words: Result implies not words_of (trimmed (a_text)).is_empty
			request_accepted: Result implies accepts_request (trimmed (a_text))
			words_safe: Result implies across words_of (trimmed (a_text)) as w all is_safe_argument (w) end
		end

	words_of (a_text: READABLE_STRING_GENERAL): ARRAYED_LIST [STRING_32]
			-- The blank-separated words of `a_text', in order.
		local
			i: INTEGER
			l_word: STRING_32
		do
			create Result.make (4)
			create l_word.make_empty
			from i := 1 until i > a_text.count loop
				if a_text.code (i) = 32 or a_text.code (i) = 9 or a_text.code (i) = 10 or a_text.code (i) = 13 then
					if not l_word.is_empty then
						Result.extend (l_word)
						create l_word.make_empty
					end
				else
					l_word.append_code (a_text.code (i))
				end
				i := i + 1
			end
			if not l_word.is_empty then
				Result.extend (l_word)
			end
		ensure
			no_empty_words: across Result as w all not w.is_empty end
		end

	command_line_of (a_arguments: LIST [STRING_32]): STRING_8
			-- The one command string a Phase 4 body may hand simple_process
			-- (NEW-2): `program_path', one space, and the arguments joined
			-- by single spaces - nothing else. With every element past
			-- `is_safe_argument', no quoting, redirection, expansion or
			-- option can occur on the joined line.
		require
			some_arguments: not a_arguments.is_empty
			all_safe: across a_arguments as a all is_safe_argument (a) end
			program_ascii: program_path.is_valid_as_string_8
		do
			Result := program_path.to_string_8
			Result.append_character (' ')
			Result.append (echo_of (a_arguments).to_string_8)
		ensure
			shape: Result.same_string (program_path.to_string_8 + " " + echo_of (a_arguments).to_string_8)
		end

	program_path: STRING_32
			-- The path of what this tool runs or opens: the first token of
			-- `command_line_of'.
		deferred
		ensure
			given: not Result.is_empty
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
			last_raw_had_footer := False
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
					last_raw_had_footer := l_output.has_substring (Footer_break + Phrased_by_prefix)
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
			no_false_disclosure: (Result.is_success and not last_response_shaped and not last_raw_had_footer) implies not Result.text.has_substring (Footer_break + Phrased_by_prefix)
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
			-- The engine: a Phase 4 body that starts a child process builds
			-- its one command string with `command_line_of' (never any other
			-- joining) and enforces `timeout_seconds' with
			-- SIMPLE_ASYNC_PROCESS.wait_seconds and kill (Issue 26: the
			-- bound is enforceable for children); a query engine runs the
			-- parameterized query. Either way it records the timing
			-- (`record_run'); an empty result means the tool said nothing.
			-- Deferred: the template cannot own the child, so the bound
			-- lives in each engine body, under TIMED_ENGINE's contracts.
		require
			all_safe: across a_arguments as a all is_safe_argument (a) end
		deferred
		ensure
			timed: elapsed_seconds >= 0
		end

	run_child_process (a_arguments: ARRAYED_LIST [STRING_32]): STRING_32
			-- The one child-process engine (NEW-2, Issue 26): start
			-- `command_line_of (a_arguments)' - never any other joining -
			-- through SIMPLE_ASYNC_PROCESS in `child_working_directory',
			-- pumping output every `Wait_slice_ms' so a chatty child never
			-- blocks on a full pipe, bounded by `timeout_seconds'. A child
			-- alive past the bound is killed and confirmed dead (polled up
			-- to `Kill_confirm_ms'); the run is then recorded as timed out:
			-- whole-second timestamps round a real overrun down, so the
			-- recorded time is raised to at least `timeout_seconds' + 1 -
			-- the overrun is a fact observed, never clamped into the bound,
			-- and the output is dropped. A child that cannot start, and an
			-- engine that raises, is an empty output with the elapsed time
			-- recorded: `answer' turns both into an honest error.
		require
			some_arguments: not a_arguments.is_empty
			all_safe: across a_arguments as a all is_safe_argument (a) end
		local
			l_process: detachable SIMPLE_ASYNC_PROCESS
			l_started, l_now: SIMPLE_DATE_TIME
			l_elapsed, l_waited_ms, l_confirm_ms: INTEGER
			l_ran, l_finished, l_failed: BOOLEAN
		do
			create l_started.make_now
			create Result.make_empty
			if not l_failed then
				create l_process.make
				l_process.start_in_directory (command_line_of (a_arguments), child_working_directory)
				if l_process.is_started then
					l_ran := l_process.was_started_successfully
					if l_ran then
						from
						until
							l_finished or l_waited_ms >= timeout_seconds * 1000
						loop
							l_finished := l_process.wait (Wait_slice_ms) = 1
							if attached l_process.read_available_output then
								-- Pumped into `accumulated_output'.
							end
							if not l_finished then
								l_waited_ms := l_waited_ms + Wait_slice_ms
							end
						end
						if not l_finished then
								-- One last poll: a child that finished exactly at
								-- the boundary is finished, not killed.
							l_finished := l_process.wait (0) = 1
						end
						if not l_finished and then l_process.is_running then
							if l_process.kill then
								-- Kill requested; confirmation follows.
							end
							from
							until
								not l_process.is_running or l_confirm_ms >= Kill_confirm_ms
							loop
								if l_process.wait (Wait_slice_ms) = 1 then
									-- Dead.
								end
								l_confirm_ms := l_confirm_ms + Wait_slice_ms
							end
							check child_confirmed_dead: not l_process.is_running end
						end
					end
					l_process.close
					Result := l_process.accumulated_output.twin
				end
			end
			create l_now.make_now
			l_elapsed := (l_now.to_timestamp - l_started.to_timestamp).to_integer_32.max (0)
			if l_ran and not l_finished then
				l_elapsed := l_elapsed.max (timeout_seconds + 1)
				create Result.make_empty
			end
			record_run (l_elapsed)
		ensure
			timed: elapsed_seconds >= 0
		rescue
				-- One retry only: the retried body skips the child and
				-- answers an empty output with the time recorded; a second
				-- exception propagates instead of looping the rescue.
			if not l_failed then
				l_failed := True
				retry
			end
		end

	child_working_directory: detachable STRING_32
			-- Where the child runs: the directory of `program_path' when it
			-- names one (bible.exe reads its databases beside itself), Void
			-- otherwise - the server's own working directory. Never taken
			-- from the member's text, never a vault.
		local
			l_path: PATH
			l_parent: PATH
		do
			if program_path.has ('\') or program_path.has ('/') then
				create l_path.make_from_string (program_path)
				l_parent := l_path.parent
				if not l_parent.name.is_empty then
					create Result.make_from_string (l_parent.name)
				end
			end
		ensure
			within_program: attached Result as r implies program_path.as_lower.starts_with (r.as_lower)
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

	Forbidden_argument_characters: STRING_8 = "%"'%%^&|<>;()!$*?`\"
			-- The cmd.exe and CreateProcess metacharacters no argument may
			-- carry (NEW-2): quote, apostrophe, percent, caret, ampersand,
			-- pipe, redirection, semicolon, parentheses, bang, dollar, star,
			-- question mark, backquote, backslash. Blanks and control
			-- characters are refused separately by `obeys_base_law'.

	Output_maximum: INTEGER = 65536
			-- Raw tool output is cut here.

	Wait_slice_ms: INTEGER = 200
			-- The child engine waits and pumps output in slices of this many
			-- milliseconds, so a full pipe never deadlocks the child.

	Kill_confirm_ms: INTEGER = 5000
			-- How long a kill is polled before the engine gives up
			-- confirming (the check then reports the zombie honestly).

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
