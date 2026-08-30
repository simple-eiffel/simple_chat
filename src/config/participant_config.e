note
	description: "One [[participants]] entry of the server configuration (addendum 09). Its two lists are modeled so every setter states what it left alone."
	author: "Larry Rix"

class
	PARTICIPANT_CONFIG

create
	make

feature {NONE} -- Initialization

	make (a_handle: READABLE_STRING_GENERAL; a_kind: READABLE_STRING_8; a_bot_username: READABLE_STRING_8; a_bot_display_name: READABLE_STRING_GENERAL)
		require
			handle_shape: a_handle.count >= 2 and a_handle.starts_with ("@")
			known_kind: is_known_kind (a_kind)
			valid_bot_username: (create {CHAT_USER_RULES}).is_valid_username (a_bot_username)
			valid_display: (create {CHAT_USER_RULES}).is_valid_display_name (a_bot_display_name)
		do
			handle := a_handle.to_string_32.as_lower
			kind := a_kind.to_string_8
			bot_username := a_bot_username.to_string_8
			bot_display_name := a_bot_display_name.to_string_32
			create aliases.make (2)
			create allow_via.make (3)
			requests_per_hour := 5
			max_characters := 1200
			timeout_seconds := 120
			create executable.make_empty
			create database.make_empty
			create model.make_empty
			create working_directory.make_empty
			query_shaper := Shaper_none
			response_shaper := Shaper_none
		ensure
			handle_set: handle.same_string (a_handle.to_string_32.as_lower)
			kind_set: kind.same_string (a_kind)
			no_aliases: aliases_model.is_empty
			no_via: allow_via_model.is_empty
		end

feature -- Model Queries (for MML postconditions)

	aliases_model: MML_SEQUENCE [STRING_32]
			-- The aliases, in configuration order.
		do
			create Result
			across aliases as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = aliases.count
		end

	allow_via_model: MML_SEQUENCE [STRING_32]
			-- What `via' may select, in configuration order.
		do
			create Result
			across allow_via as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = allow_via.count
		end

feature -- Access

	handle: STRING_32
	kind: STRING_8
	bot_username: STRING_8
	bot_display_name: STRING_32
	aliases: ARRAYED_LIST [STRING_32]
	allow_via: ARRAYED_LIST [STRING_32]
	requests_per_hour: INTEGER
	max_characters: INTEGER
	timeout_seconds: INTEGER
	executable: STRING_32
	database: STRING_32
	model: STRING_32
	working_directory: STRING_32
	query_shaper: STRING_32
	response_shaper: STRING_32

feature -- Status report

	allows_via (a_choice: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := allow_via_model.has (a_choice.to_string_32)
		end

	has_alias (a_alias: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := aliases_model.has (a_alias.to_string_32)
		end

feature -- Element change

	set_limits (a_requests_per_hour, a_max_characters, a_timeout_seconds: INTEGER)
		require
			non_negative: a_requests_per_hour >= 0
			positive: a_max_characters > 0 and a_timeout_seconds > 0
		do
			requests_per_hour := a_requests_per_hour
			max_characters := a_max_characters
			timeout_seconds := a_timeout_seconds
		ensure
			set: requests_per_hour = a_requests_per_hour and max_characters = a_max_characters and timeout_seconds = a_timeout_seconds
			lists_unchanged: aliases_model |=| old aliases_model and allow_via_model |=| old allow_via_model
		end

	set_engine (a_executable, a_database, a_model, a_working_directory: READABLE_STRING_GENERAL)
		do
			executable := a_executable.to_string_32
			database := a_database.to_string_32
			model := a_model.to_string_32
			working_directory := a_working_directory.to_string_32
		ensure
			set: executable.same_string_general (a_executable) and database.same_string_general (a_database)
				and model.same_string_general (a_model) and working_directory.same_string_general (a_working_directory)
			lists_unchanged: aliases_model |=| old aliases_model and allow_via_model |=| old allow_via_model
		end

	set_shapers (a_query_shaper, a_response_shaper: READABLE_STRING_GENERAL)
		require
			given: not a_query_shaper.is_empty and not a_response_shaper.is_empty
		do
			query_shaper := a_query_shaper.to_string_32
			response_shaper := a_response_shaper.to_string_32
		ensure
			set: query_shaper.same_string_general (a_query_shaper) and response_shaper.same_string_general (a_response_shaper)
			lists_unchanged: aliases_model |=| old aliases_model and allow_via_model |=| old allow_via_model
		end

	add_alias (a_alias: READABLE_STRING_GENERAL)
		require
			given: not a_alias.is_empty
			fresh: not has_alias (a_alias)
		do
			aliases.extend (a_alias.to_string_32)
		ensure
			appended: aliases_model |=| ((old aliases_model) & a_alias.to_string_32)
			via_unchanged: allow_via_model |=| old allow_via_model
		end

	add_allow_via (a_choice: READABLE_STRING_GENERAL)
		require
			given: not a_choice.is_empty
			fresh: not allows_via (a_choice)
		do
			allow_via.extend (a_choice.to_string_32)
		ensure
			appended: allow_via_model |=| ((old allow_via_model) & a_choice.to_string_32)
			aliases_unchanged: aliases_model |=| old aliases_model
		end

feature -- Validation (contract support)

	is_known_kind (a_kind: READABLE_STRING_8): BOOLEAN
		do
			Result := a_kind.same_string (Kind_claude_code) or a_kind.same_string (Kind_ollama)
				or a_kind.same_string (Kind_bible_tool) or a_kind.same_string (Kind_shape_tool) or a_kind.same_string (Kind_none)
		end

feature -- Constants

	Kind_claude_code: STRING_8 = "claude_code"
	Kind_ollama: STRING_8 = "ollama"
	Kind_bible_tool: STRING_8 = "bible_tool"
	Kind_shape_tool: STRING_8 = "shape_tool"
	Kind_none: STRING_8 = "none"
	Shaper_none: STRING_32 = "none"

invariant
	handle_shape: handle.count >= 2 and handle.starts_with ("@")
	known_kind: is_known_kind (kind)
	limits_sane: requests_per_hour >= 0 and max_characters > 0 and timeout_seconds > 0
	shapers_given: not query_shaper.is_empty and not response_shaper.is_empty
	models_consistent: aliases_model.count = aliases.count and allow_via_model.count = allow_via.count

end
