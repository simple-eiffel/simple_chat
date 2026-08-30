note
	description: "[
		A scripted TOOL_PARTICIPANT for the assault suite: the template of
		TOOL_PARTICIPANT with an allowlist that refuses shell punctuation
		and an engine that answers with a fixed output at once.
	]"
	author: "Larry Rix"

class
	MOCK_TOOL_PARTICIPANT

inherit
	TOOL_PARTICIPANT

create
	make

feature {NONE} -- Initialization

	make (a_handle: READABLE_STRING_GENERAL; a_bot_user: CHAT_USER; a_scripted_output: READABLE_STRING_GENERAL)
		require
			handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (a_handle)
			bot: a_bot_user.is_bot
			bot_stored: a_bot_user.is_stored
			bot_active: a_bot_user.is_active
			bot_marked: a_bot_user.display_name.has_substring ({CHAT_EVENT_KINDS}.Bot_marker)
			scripted: not a_scripted_output.is_empty
		do
			initialize_tool (a_handle, a_bot_user, "a scripted tool for the assault suite", Default_max_characters, 30)
			create scripted_output.make_from_string_general (a_scripted_output)
		ensure
			handle_set: handle.same_string_general (a_handle)
		end

feature -- Access

	scripted_output: STRING_32

feature -- Status report

	is_safe_argument (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Printable ASCII, 1..`Argument_maximum', not an option, and none of | ; & < > ` $.
		local
			i: INTEGER
			c: NATURAL_32
		do
			Result := a_text.count >= 1 and a_text.count <= Argument_maximum and then a_text.code (1) /= 45
			from i := 1 until i > a_text.count or not Result loop
				c := a_text.code (i)
				Result := c >= 32 and c <= 126 and c /= 124 and c /= 59 and c /= 38 and c /= 60 and c /= 62 and c /= 96 and c /= 36
				i := i + 1
			end
		end

feature {NONE} -- Implementation

	run_arguments (a_arguments: ARRAYED_LIST [STRING_32]): STRING_32
		do
			record_run (0)
			Result := scripted_output.twin
		end

end
