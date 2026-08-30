note
	description: "[
		`@shape-larry': answers a shape slug from shape.db, read-only, in
		Eiffel over simple_sql - the FITS / PARTIAL / FAILS / NO_DATA counts
		and the top instances. Numbers by default; prose when a response
		shaper is configured or chosen with `via'. The only argument shape
		is a slug: [a-z0-9_]{1,64} (`is_slug', Issue 38).
	]"
	author: "Larry Rix"

class
	SHAPE_TOOL_PARTICIPANT

inherit
	TOOL_PARTICIPANT

create
	make

feature {NONE} -- Initialization

	make (a_handle: READABLE_STRING_GENERAL; a_bot_user: CHAT_USER; a_database_path: READABLE_STRING_GENERAL; a_max_characters, a_timeout_seconds: INTEGER)
		require
			handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (a_handle)
			bot: a_bot_user.is_bot
			bot_stored: a_bot_user.is_stored
			bot_active: a_bot_user.is_active
			bot_marked: a_bot_user.display_name.has_substring ({CHAT_EVENT_KINDS}.Bot_marker)
			database_given: not a_database_path.is_empty
			max_positive: a_max_characters > 0
			timeout_positive: a_timeout_seconds > 0
		do
			initialize_tool (a_handle, a_bot_user, Tool_description, a_max_characters, a_timeout_seconds)
			create database_path.make_from_string_general (a_database_path)
		ensure
			handle_set: handle.same_string_general (a_handle)
			database_set: database_path.same_string_general (a_database_path)
			plain_by_default: query_shaper.cost_tier = {SHAPER}.Tier_none and response_shaper.cost_tier = {SHAPER}.Tier_none
		end

feature -- Access

	database_path: STRING_32

feature -- Status report

	is_safe_argument (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- A shape slug and nothing else.
		do
			Result := is_slug (a_text)
		ensure then
			definition: Result = is_slug (a_text)
		end

	is_slug (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- 1..`Slug_maximum' characters of [a-z0-9_]?
		local
			i: INTEGER
			c: NATURAL_32
		do
			Result := a_text.count >= 1 and a_text.count <= Slug_maximum
			from i := 1 until i > a_text.count or not Result loop
				c := a_text.code (i)
				Result := (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c = 95
				i := i + 1
			end
		end

feature {NONE} -- Implementation

	run_arguments (a_arguments: ARRAYED_LIST [STRING_32]): STRING_32
		do
			create Result.make_empty
			record_run (0)
			-- Implementation in Phase 4: parameterized SELECTs on shape_instance, read-only connection
		end

feature -- Constants

	Slug_maximum: INTEGER = 64

	Tool_description: STRING_32 = "the shape tool: one shape slug such as beachhead_that_moves"

invariant
	database_given: not database_path.is_empty

end
