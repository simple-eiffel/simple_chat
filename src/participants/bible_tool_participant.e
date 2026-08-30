note
	description: "[
		`@tools-larry': runs bible.exe (simple_scholar's one-shot mode) with
		a verse reference or an allowlisted slash command. A friend types
		"@tools-larry Gen 1:1" and the room gets the verse. No AI unless a
		shaper is configured.
	]"
	author: "Larry Rix"

class
	BIBLE_TOOL_PARTICIPANT

inherit
	TOOL_PARTICIPANT

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

feature -- Status report

	is_safe_argument (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- A verse reference - a leading letter or digit, then letters, digits,
			-- spaces and the punctuation of references (":", ".", ",", "-"), with a
			-- digit somewhere: "Gen 1:1", "1 John 3:16-18", "kjv Ps 23" - or a
			-- slash command with at most one word: "/lex H7225". Phase 4 narrows
			-- the command allowlist to what bible.exe's one-shot mode accepts.
		do
			Result := a_text.count >= 1 and a_text.count <= Argument_maximum
				and then (is_reference_shape (a_text) or is_command_shape (a_text))
		ensure then
			definition: Result = (a_text.count >= 1 and a_text.count <= Argument_maximum and then (is_reference_shape (a_text) or is_command_shape (a_text)))
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

feature {NONE} -- Implementation

	run_arguments (a_arguments: ARRAYED_LIST [STRING_32]): STRING_32
		do
			create Result.make_empty
			record_run (0)
			-- Implementation in Phase 4: SIMPLE_PROCESS with `executable' and the argument list, bounded by `timeout_seconds'
		end

	is_letter_or_digit (a_code: NATURAL_32): BOOLEAN
		do
			Result := (a_code >= 65 and a_code <= 90) or (a_code >= 97 and a_code <= 122) or (a_code >= 48 and a_code <= 57)
		end

feature -- Constants

	Tool_description: STRING_32 = "the Bible tool: a verse reference such as Gen 1:1 or 1 John 3:16-18, or a slash command"

invariant
	executable_given: not executable.is_empty

end
