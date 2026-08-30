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

	make (a_handle: READABLE_STRING_GENERAL; a_bot_user: CHAT_USER; a_executable: READABLE_STRING_GENERAL; a_timeout_seconds: INTEGER)
		require
			handle_shape: a_handle.count >= 2 and a_handle.starts_with ("@")
			bot: a_bot_user.is_bot
			executable_given: not a_executable.is_empty
			timeout_positive: a_timeout_seconds > 0
		do
			handle := a_handle.to_string_32
			bot_user := a_bot_user
			executable := a_executable.to_string_32
			timeout_seconds := a_timeout_seconds
			max_concurrent := 2
			create query_shaper.make
			create response_shaper.make
			create executed_query.make_empty
		ensure
			handle_set: handle.same_string_general (a_handle)
			executable_set: executable.same_string_general (a_executable)
			plain_by_default: query_shaper.cost_tier = {SHAPER}.Tier_none and response_shaper.cost_tier = {SHAPER}.Tier_none
		end

feature -- Access

	executable: STRING_32

feature -- Status report

	is_safe_argument (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- A verse reference with an optional version prefix, or an
			-- allowlisted slash command with one word - nothing else.
		do
			-- Implementation in Phase 4
		end

feature -- Basic operations

	run_tool (a_arguments: ARRAYED_LIST [STRING_32]): STRING_32
		do
			create Result.make_empty
			-- Implementation in Phase 4: SIMPLE_PROCESS with an argument list, bounded by timeout_seconds
		end

invariant
	executable_given: not executable.is_empty

end
