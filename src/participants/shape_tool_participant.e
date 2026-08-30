note
	description: "[
		`@shape-larry': answers a shape slug from shape.db, read-only, in
		Eiffel over simple_sql - the FITS / PARTIAL / FAILS / NO_DATA counts
		and the top instances. Numbers by default; prose when a response
		shaper is configured or chosen with `via'.
	]"
	author: "Larry Rix"

class
	SHAPE_TOOL_PARTICIPANT

inherit
	TOOL_PARTICIPANT

create
	make

feature {NONE} -- Initialization

	make (a_handle: READABLE_STRING_GENERAL; a_bot_user: CHAT_USER; a_database_path: READABLE_STRING_GENERAL; a_timeout_seconds: INTEGER)
		require
			handle_shape: a_handle.count >= 2 and a_handle.starts_with ("@")
			bot: a_bot_user.is_bot
			database_given: not a_database_path.is_empty
			timeout_positive: a_timeout_seconds > 0
		do
			handle := a_handle.to_string_32
			bot_user := a_bot_user
			database_path := a_database_path.to_string_32
			timeout_seconds := a_timeout_seconds
			max_concurrent := 2
			create query_shaper.make
			create response_shaper.make
			create executed_query.make_empty
		ensure
			handle_set: handle.same_string_general (a_handle)
			database_set: database_path.same_string_general (a_database_path)
		end

feature -- Access

	database_path: STRING_32

feature -- Status report

	is_safe_argument (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- A shape slug: [a-z0-9_]{1,64}.
		do
			-- Implementation in Phase 4
		end

feature -- Basic operations

	run_tool (a_arguments: ARRAYED_LIST [STRING_32]): STRING_32
		do
			create Result.make_empty
			-- Implementation in Phase 4: parameterized SELECTs on shape_instance, read-only connection
		end

invariant
	database_given: not database_path.is_empty

end
