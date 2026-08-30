note
	description: "[
		A shaper on a local model through simple_ai_client's OLLAMA_CLIENT:
		the cheap default for phrasing (Tier_local). Bounded in time like
		every engine (TIMED_ENGINE, Issue 26). Its name is handle-shaped -
		"@qwen" - because that is how `via' refers to it.
	]"
	author: "Larry Rix"

class
	OLLAMA_SHAPER

inherit
	SHAPER

	TIMED_ENGINE

create
	make

feature {NONE} -- Initialization

	make (a_name: READABLE_STRING_GENERAL; a_client: OLLAMA_CLIENT; a_model: READABLE_STRING_GENERAL; a_timeout_seconds: INTEGER)
		require
			name_is_handle: (create {PARTICIPANT_RULES}).is_valid_handle (a_name)
			model_given: not a_model.is_empty
			timeout_positive: a_timeout_seconds > 0
		do
			create name.make_from_string_general (a_name)
			client := a_client
			create model.make_from_string_general (a_model)
			timeout_seconds := a_timeout_seconds
		ensure
			name_set: name.same_string_general (a_name)
			model_set: model.same_string_general (a_model)
			timeout_set: timeout_seconds = a_timeout_seconds
		end

feature -- Access

	name: STRING_32
	model: STRING_32

	cost_tier: INTEGER
		do
			Result := Tier_local
		end

feature -- Basic operations

	shape (a_text: READABLE_STRING_GENERAL; a_brief: SHAPING_BRIEF): SHAPED_TEXT
		do
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501))
			-- Implementation in Phase 4: client.set_model (model); ask_with_system (brief prompt, a_text); record_run; cut to limit
		ensure then
			bounded_runtime: not last_timed_out implies elapsed_seconds <= timeout_seconds
			timeout_is_error: last_timed_out implies not Result.is_success
		end

feature {NONE} -- Implementation

	client: OLLAMA_CLIENT

invariant
	name_is_handle: (create {PARTICIPANT_RULES}).is_valid_handle (name)
	model_given: not model.is_empty

end
