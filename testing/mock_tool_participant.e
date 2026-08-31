note
	description: "[
		A scripted TOOL_PARTICIPANT for the assault suite: the template of
		TOOL_PARTICIPANT with the base metacharacter law as its whole
		allowlist (`accepts_word' is True, so what the base law refuses is
		exactly what this tool refuses - NEW-2 under test) and an engine
		that answers with a fixed output at once.
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

	program_path: STRING_32
			-- <Precursor>: a fixed name for the command-line law under test.
		do
			Result := {STRING_32} "mock.exe"
		end

feature -- Status report

	accepts_word (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Everything the base law admits: this mock's allowlist IS the
			-- base law, so its refusals are exactly `obeys_base_law''s.
		do
			Result := True
		end

feature {NONE} -- Implementation

	run_arguments (a_arguments: ARRAYED_LIST [STRING_32]): STRING_32
		do
			record_run (0)
			Result := scripted_output.twin
		end

end
