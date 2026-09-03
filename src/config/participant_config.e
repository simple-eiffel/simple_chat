note
	description: "[
		One [[participants]] entry of the server configuration (addendum 09).
		Born complete for its kind (`is_complete_for_kind', M11): the one
		engine setting a kind needs - the executable, the database, the
		model or the working directory - is given at creation and every
		change keeps it, so an entry that cannot be built cannot exist. The
		limits are positive (a zero hourly limit cannot reach the limiter).
		`context_messages' - how many recent room messages come with a
		request, so the participant can follow a conversation - is the one
		setting allowed to be zero: zero is a participant with no memory of
		the turn before, which is exactly what some entries want.
		Aliases and `via' choices are sets, lowercase and shaped as
		PARTICIPANT_RULES demands. The bot's display name is given without
		the marker and read with it (`marked_display_name'): the member the
		answers post as always carries it.
	]"
	author: "Larry Rix"

class
	PARTICIPANT_CONFIG

create
	make

feature {NONE} -- Initialization

	make (a_handle: READABLE_STRING_GENERAL; a_kind: READABLE_STRING_8; a_bot_username: READABLE_STRING_8; a_bot_display_name: READABLE_STRING_GENERAL; a_engine: READABLE_STRING_GENERAL)
			-- An entry of `a_kind' for `a_handle'; `a_engine' is the one setting the
			-- kind needs (its executable, database, model or working directory), ignored for `Kind_none'.
		require
			handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (a_handle)
			known_kind: is_known_kind (a_kind)
			valid_bot_username: (create {CHAT_USER_RULES}).is_valid_username (a_bot_username)
			valid_display: (create {CHAT_USER_RULES}).is_valid_display_name (a_bot_display_name)
			display_fits_marker: a_bot_display_name.count + 2 <= {CHAT_USER}.Display_name_maximum
			engine_given_for_kind: not a_kind.same_string (Kind_none) implies not a_engine.is_empty
		do
			create handle.make_from_string_general (a_handle)
			kind := a_kind.to_string_8
			bot_username := a_bot_username.to_string_8
			create bot_display_name.make_from_string_general (a_bot_display_name)
			create aliases.make (2)
			aliases.compare_objects
			create allow_via.make (3)
			allow_via.compare_objects
			requests_per_hour := 5
			max_characters := 1200
			timeout_seconds := 120
			context_messages := {PARTICIPANT_RULES}.Default_context_messages
			create executable.make_empty
			create database.make_empty
			create model.make_empty
			create working_directory.make_empty
			if kind.same_string (Kind_bible_tool) then
				create executable.make_from_string_general (a_engine)
			elseif kind.same_string (Kind_shape_tool) then
				create database.make_from_string_general (a_engine)
			elseif kind.same_string (Kind_ollama) then
				create model.make_from_string_general (a_engine)
			elseif kind.same_string (Kind_claude_code) then
				create working_directory.make_from_string_general (a_engine)
			end
			query_shaper := Shaper_none.twin
			response_shaper := Shaper_none.twin
		ensure
			handle_set: handle.same_string_general (a_handle)
			kind_set: kind.same_string (a_kind)
			complete: is_complete_for_kind
			no_aliases: aliases_model.is_empty
			no_via: allow_via_model.is_empty
			marked: marked_display_name.starts_with ({CHAT_EVENT_KINDS}.Bot_marker)
		end

feature -- Model Queries (for MML postconditions)

	aliases_model: MML_SET [STRING_32]
			-- The aliases, lowercase.
		do
			create Result
			across aliases as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = aliases.count
		end

	allow_via_model: MML_SET [STRING_32]
			-- What `via' may select, lowercase.
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
			-- As configured, without the marker.
	requests_per_hour: INTEGER
	max_characters: INTEGER
	timeout_seconds: INTEGER
	context_messages: INTEGER
			-- Recent room messages given with a request; 0 for no memory.
	executable: STRING_32
	database: STRING_32
	model: STRING_32
	working_directory: STRING_32
	query_shaper: STRING_32
	response_shaper: STRING_32

	marked_display_name: STRING_32
			-- The display name the bot user gets: the marker, a space, `bot_display_name'.
		do
			Result := {CHAT_EVENT_KINDS}.Bot_marker + {STRING_32} " " + bot_display_name
		ensure
			marked: Result.starts_with ({CHAT_EVENT_KINDS}.Bot_marker)
			named: Result.ends_with (bot_display_name)
			valid: (create {CHAT_USER_RULES}).is_valid_display_name (Result)
		end

	alias_count: INTEGER
		do
			Result := aliases.count
		end

	allow_via_count: INTEGER
		do
			Result := allow_via.count
		end

	alias_list: ARRAYED_LIST [STRING_32]
			-- A copy of the aliases, lowercase, in the order added (Task 7:
			-- the dispatcher wires them into the registry; the model
			-- queries alone cannot be iterated).
		do
			create Result.make (aliases.count)
			across aliases as ic loop
				Result.extend (ic.twin)
			end
		ensure
			a_copy: Result /= aliases
			same_count: Result.count = alias_count
			all_known: across Result as a all has_alias (a) end
		end

	allow_via_list: ARRAYED_LIST [STRING_32]
			-- A copy of the `via' choices, lowercase, in the order added.
		do
			create Result.make (allow_via.count)
			across allow_via as ic loop
				Result.extend (ic.twin)
			end
		ensure
			a_copy: Result /= allow_via
			same_count: Result.count = allow_via_count
			all_allowed: across Result as c all allows_via (c) end
		end

feature -- Status report

	allows_via (a_choice: READABLE_STRING_GENERAL): BOOLEAN
			-- May a member choose `a_choice' (in any case) with `via'?
		do
			Result := allow_via.has (a_choice.to_string_32.as_lower)
		ensure
			definition: Result = allow_via_model.has (a_choice.to_string_32.as_lower)
		end

	has_alias (a_alias: READABLE_STRING_GENERAL): BOOLEAN
			-- Is `a_alias' (in any case) one of this entry's aliases?
		do
			Result := aliases.has (a_alias.to_string_32.as_lower)
		ensure
			definition: Result = aliases_model.has (a_alias.to_string_32.as_lower)
		end

	is_complete_for_kind: BOOLEAN
			-- Does this entry carry what its kind needs to be built?
		do
			Result := is_complete (kind, executable, database, model, working_directory)
		ensure
			definition: Result = is_complete (kind, executable, database, model, working_directory)
		end

feature -- Element change

	set_limits (a_requests_per_hour, a_max_characters, a_timeout_seconds: INTEGER)
		require
			positive: a_requests_per_hour > 0 and a_max_characters > 0 and a_timeout_seconds > 0
		do
			requests_per_hour := a_requests_per_hour
			max_characters := a_max_characters
			timeout_seconds := a_timeout_seconds
		ensure
			set: requests_per_hour = a_requests_per_hour and max_characters = a_max_characters and timeout_seconds = a_timeout_seconds
			lists_unchanged: aliases_model |=| old aliases_model and allow_via_model |=| old allow_via_model
			still_complete: is_complete_for_kind
		end

	set_engine (a_executable, a_database, a_model, a_working_directory: READABLE_STRING_GENERAL)
		require
			complete: is_complete (kind, a_executable, a_database, a_model, a_working_directory)
		do
			create executable.make_from_string_general (a_executable)
			create database.make_from_string_general (a_database)
			create model.make_from_string_general (a_model)
			create working_directory.make_from_string_general (a_working_directory)
		ensure
			set: executable.same_string_general (a_executable) and database.same_string_general (a_database)
				and model.same_string_general (a_model) and working_directory.same_string_general (a_working_directory)
			lists_unchanged: aliases_model |=| old aliases_model and allow_via_model |=| old allow_via_model
			still_complete: is_complete_for_kind
		end

	set_context_messages (a_count: INTEGER)
			-- How many recent room messages this participant is given with a
			-- request; 0 takes the window away.
		require
			in_range: a_count >= 0 and a_count <= {PARTICIPANT_RULES}.Context_maximum
		do
			context_messages := a_count
		ensure
			set: context_messages = a_count
			lists_unchanged: aliases_model |=| old aliases_model and allow_via_model |=| old allow_via_model
			still_complete: is_complete_for_kind
		end

	set_shapers (a_query_shaper, a_response_shaper: READABLE_STRING_GENERAL)
		require
			known: is_known_shaper_name (a_query_shaper) and is_known_shaper_name (a_response_shaper)
		do
			create query_shaper.make_from_string_general (a_query_shaper)
			create response_shaper.make_from_string_general (a_response_shaper)
		ensure
			set: query_shaper.same_string_general (a_query_shaper) and response_shaper.same_string_general (a_response_shaper)
			lists_unchanged: aliases_model |=| old aliases_model and allow_via_model |=| old allow_via_model
		end

	add_alias (a_alias: READABLE_STRING_GENERAL)
			-- Let `a_alias' (kept lowercase) address this participant too.
		require
			alias_shape: (create {PARTICIPANT_RULES}).is_valid_alias (a_alias)
			fresh: not has_alias (a_alias)
			alias_not_own_handle: not a_alias.to_string_32.as_lower.same_string (handle)
		do
			aliases.extend (a_alias.to_string_32.as_lower)
		ensure
			added: aliases_model |=| ((old aliases_model) & a_alias.to_string_32.as_lower)
			findable: has_alias (a_alias)
			via_unchanged: allow_via_model |=| old allow_via_model
		end

	add_allow_via (a_choice: READABLE_STRING_GENERAL)
			-- Let members choose `a_choice' (kept lowercase) with `via'.
		require
			choice_shape: (create {PARTICIPANT_RULES}).is_via_choice (a_choice.to_string_32.as_lower)
			fresh: not allows_via (a_choice)
		do
			allow_via.extend (a_choice.to_string_32.as_lower)
		ensure
			added: allow_via_model |=| ((old allow_via_model) & a_choice.to_string_32.as_lower)
			findable: allows_via (a_choice)
			aliases_unchanged: aliases_model |=| old aliases_model
		end

feature -- Validation (contract support)

	is_known_kind (a_kind: READABLE_STRING_8): BOOLEAN
		do
			Result := a_kind.same_string (Kind_claude_code) or a_kind.same_string (Kind_ollama)
				or a_kind.same_string (Kind_bible_tool) or a_kind.same_string (Kind_shape_tool) or a_kind.same_string (Kind_none)
		end

	is_known_shaper_name (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- "none", "plain", or a shaper's handle-shaped name?
		do
			Result := a_name.same_string (Shaper_none) or (create {PARTICIPANT_RULES}).is_via_choice (a_name)
		ensure
			definition: Result = (a_name.same_string (Shaper_none) or (create {PARTICIPANT_RULES}).is_via_choice (a_name))
		end

	is_complete (a_kind: READABLE_STRING_8; a_executable, a_database, a_model, a_working_directory: READABLE_STRING_GENERAL): BOOLEAN
			-- Would an entry of `a_kind' with these engine settings carry what it needs?
		do
			if a_kind.same_string (Kind_none) then
				Result := True
			elseif a_kind.same_string (Kind_bible_tool) then
				Result := not a_executable.is_empty
			elseif a_kind.same_string (Kind_shape_tool) then
				Result := not a_database.is_empty
			elseif a_kind.same_string (Kind_ollama) then
				Result := not a_model.is_empty
			elseif a_kind.same_string (Kind_claude_code) then
				Result := not a_working_directory.is_empty
			end
		ensure
			none_needs_nothing: a_kind.same_string (Kind_none) implies Result
			unknown_never: not is_known_kind (a_kind) implies not Result
		end

feature -- Constants

	Kind_claude_code: STRING_8 = "claude_code"
	Kind_ollama: STRING_8 = "ollama"
	Kind_bible_tool: STRING_8 = "bible_tool"
	Kind_shape_tool: STRING_8 = "shape_tool"
	Kind_none: STRING_8 = "none"
	Shaper_none: STRING_32 = "none"

feature {NONE} -- Implementation

	aliases: ARRAYED_LIST [STRING_32]
			-- Lowercase, no duplicates.

	allow_via: ARRAYED_LIST [STRING_32]
			-- Lowercase, no duplicates.

invariant
	handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (handle)
	known_kind: is_known_kind (kind)
	complete: is_complete_for_kind
	limits_positive: requests_per_hour > 0 and max_characters > 0 and timeout_seconds > 0
	context_in_range: context_messages >= 0 and context_messages <= {PARTICIPANT_RULES}.Context_maximum
	shapers_known: is_known_shaper_name (query_shaper) and is_known_shaper_name (response_shaper)
	aliases_shaped: across aliases as ic all (create {PARTICIPANT_RULES}).is_valid_alias (ic) and ic.same_string (ic.as_lower) and not ic.same_string (handle) end
	via_shaped: across allow_via as ic all (create {PARTICIPANT_RULES}).is_via_choice (ic) end
	models_consistent: aliases_model.count = aliases.count and allow_via_model.count = allow_via.count

end
