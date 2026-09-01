note
	description: "[
		`@tools-larry': runs bible.exe (simple_scholar's one-shot mode) with
		a verse reference or an allowlisted slash command. A friend types
		"@tools-larry Gen 1:1" and the room gets the verse. No AI unless a
		shaper is configured.

		The command set is CLOSED (Issue 38): `Allowed_commands' holds
		exactly the read-only query commands verified against bible.exe's
		dispatcher (bible_repl.e process_command) - never /reload, /cache,
		/default, /load, /quit, /exit, /repl, /research or anything else
		that writes, changes state, hangs interactive or reaches an AI.
		A request is a reference shape (with a digit) or "/<cmd>" with
		`<cmd>' in the set and at most one word after it.
	]"
	author: "Larry Rix"

class
	BIBLE_TOOL_PARTICIPANT

inherit
	TOOL_PARTICIPANT
		redefine
			accepts_request
		end

create
	make

feature {NONE} -- Initialization

	make (a_handle: READABLE_STRING_GENERAL; a_bot_user: CHAT_USER; a_executable: READABLE_STRING_GENERAL; a_max_characters, a_timeout_seconds: INTEGER)
		require
			handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (a_handle)
			bot: a_bot_user.is_bot
			bot_stored: a_bot_user.is_stored
			bot_active: a_bot_user.is_active
			bot_marked: a_bot_user.display_name.has_substring ({CHAT_EVENT_KINDS}.Bot_marker)
			executable_given: not a_executable.is_empty
			max_positive: a_max_characters > 0
			timeout_positive: a_timeout_seconds > 0
		do
			initialize_tool (a_handle, a_bot_user, Tool_description, a_max_characters, a_timeout_seconds)
			create executable.make_from_string_general (a_executable)
		ensure
			handle_set: handle.same_string_general (a_handle)
			executable_set: executable.same_string_general (a_executable)
			plain_by_default: query_shaper.cost_tier = {SHAPER}.Tier_none and response_shaper.cost_tier = {SHAPER}.Tier_none
		end

feature -- Access

	executable: STRING_32

	program_path: STRING_32
			-- <Precursor>: bible.exe.
		do
			Result := executable
		ensure then
			definition: Result = executable
		end

feature -- Status report

	accepts_word (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- A reference word - letters, digits and the punctuation of
			-- references (":", ".", ",", "-"), beginning with a letter or
			-- digit - or an allowed slash command.
		do
			Result := is_reference_word (a_text) or is_allowed_command_token (a_text)
		ensure then
			definition: Result = (is_reference_word (a_text) or is_allowed_command_token (a_text))
			closed_set: (Result and then a_text.code (1) = 47) implies is_allowed_command_token (a_text)
		end

	accepts_request (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- <Precursor>: a reference shape with a digit somewhere
			-- ("Gen 1:1", "1 John 3:16-18", "kjv Ps 23"), or "/<cmd>" with
			-- `<cmd>' in `Allowed_commands' and at most one word after it
			-- ("/define H1254").
		do
			Result := is_reference_shape (a_text) or is_allowed_command_shape (a_text)
		ensure then
			definition: Result = (is_reference_shape (a_text) or is_allowed_command_shape (a_text))
			closed_set: (Result and then not a_text.is_empty and then a_text.code (1) = 47) implies is_allowed_command_shape (a_text)
		end

	is_reference_word (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Letters, digits, ":", ".", "," and "-", beginning with a letter or digit?
		local
			i: INTEGER
			c: NATURAL_32
		do
			Result := a_text.count >= 1 and then is_letter_or_digit (a_text.code (1))
			from i := 1 until i > a_text.count or not Result loop
				c := a_text.code (i)
				Result := is_letter_or_digit (c) or c = 58 or c = 46 or c = 44 or c = 45
				i := i + 1
			end
		end

	is_reference_shape (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Letters, digits, spaces, ":", ".", "," and "-", beginning with a letter or digit, holding a digit?
		local
			i: INTEGER
			c: NATURAL_32
			l_digit: BOOLEAN
		do
			Result := a_text.count >= 1 and then is_letter_or_digit (a_text.code (1))
			from i := 1 until i > a_text.count or not Result loop
				c := a_text.code (i)
				Result := is_letter_or_digit (c) or c = 32 or c = 58 or c = 46 or c = 44 or c = 45
				l_digit := l_digit or (c >= 48 and c <= 57)
				i := i + 1
			end
			Result := Result and l_digit
		end

	is_command_shape (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- "/" then 1..16 lowercase letters, then optionally one space and one word of letters, digits, ":", ".", "," or "-" (1..32)?
		local
			i, l_letters, l_word: INTEGER
			c: NATURAL_32
		do
			if a_text.count >= 2 and then a_text.code (1) = 47 then
				from i := 2 until i > a_text.count or else not (a_text.code (i) >= 97 and a_text.code (i) <= 122) loop
					l_letters := l_letters + 1
					i := i + 1
				end
				Result := l_letters >= 1 and l_letters <= 16
				if Result and i <= a_text.count then
					Result := a_text.code (i) = 32 and i < a_text.count
					from i := i + 1 until i > a_text.count or not Result loop
						c := a_text.code (i)
						Result := is_letter_or_digit (c) or c = 58 or c = 46 or c = 44 or c = 45
						l_word := l_word + 1
						i := i + 1
					end
					Result := Result and l_word >= 1 and l_word <= 32
				end
			end
		end

	is_allowed_command_shape (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- A command shape whose command token is in `Allowed_commands'?
		do
			Result := is_command_shape (a_text) and then is_allowed_command_token (first_word_of (a_text))
		ensure
			shaped: Result implies is_command_shape (a_text)
			closed_set: Result implies is_allowed_command_token (first_word_of (a_text))
		end

	is_allowed_command_token (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Exactly "/" followed by one member of `Allowed_commands'?
		local
			l_lower: STRING_32
		do
			if a_text.count >= 2 and then a_text.code (1) = 47 then
				l_lower := a_text.to_string_32.as_lower
				across Allowed_commands as c loop
					Result := Result or l_lower.count = c.count + 1 and then l_lower.substring (2, l_lower.count).same_string (c)
				end
			end
		ensure
			member: Result implies across Allowed_commands as c some a_text.to_string_32.as_lower.substring (2, a_text.count).same_string (c) end
		end

	first_word_of (a_text: READABLE_STRING_GENERAL): STRING_32
			-- `a_text' up to its first blank.
		local
			l_space: INTEGER
		do
			create Result.make_from_string_general (a_text)
			l_space := Result.index_of (' ', 1)
			if l_space > 0 then
				Result := Result.substring (1, l_space - 1)
			end
		ensure
			no_blank: not Result.has (' ')
		end

feature {NONE} -- Implementation

	run_arguments (a_arguments: ARRAYED_LIST [STRING_32]): STRING_32
			-- <Precursor>: bible.exe as a child process. The one command
			-- string is `command_line_of (a_arguments)' - never any other
			-- joining - and `run_child_process' owns the bound (wait in
			-- slices, kill past `timeout_seconds', confirm dead) and the
			-- timing record.
		do
			Result := run_child_process (a_arguments)
		end

	is_letter_or_digit (a_code: NATURAL_32): BOOLEAN
		do
			Result := (a_code >= 65 and a_code <= 90) or (a_code >= 97 and a_code <= 122) or (a_code >= 48 and a_code <= 57)
		end

feature -- Constants

	Allowed_commands: ARRAY [STRING_32]
			-- Exactly bible.exe's read-only one-shot query commands, verified
			-- against its dispatcher (bible_repl.e process_command): each
			-- routes to a lookup or display routine that reads the databases
			-- and emits text. Never the state changers (/load, /default,
			-- /reload, /cache, /clear), never the process commands (/quit,
			-- /exit, /help, /repl, /more, /paths, /version), never the AI
			-- agent (/research), and no alias forms.
		once
			Result := <<{STRING_32} "define", {STRING_32} "search", {STRING_32} "entity", {STRING_32} "episode",
				{STRING_32} "scholar", {STRING_32} "assertions", {STRING_32} "ddd", {STRING_32} "overlap",
				{STRING_32} "ane", {STRING_32} "web", {STRING_32} "compare", {STRING_32} "etymology",
				{STRING_32} "xref", {STRING_32} "people", {STRING_32} "dss", {STRING_32} "pseudepigrapha",
				{STRING_32} "list", {STRING_32} "versions">>
		ensure
			closed: Result.count = 18
		end

	Tool_description: STRING_32 = "the Bible tool: a verse reference such as Gen 1:1 or 1 John 3:16-18, or an allowlisted slash command such as /define H1254"

invariant
	executable_given: not executable.is_empty

end
