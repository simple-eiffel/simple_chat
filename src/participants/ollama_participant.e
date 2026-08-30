note
	description: "[
		`@qwen' and friends: a local model through OLLAMA_CLIENT as a room
		member - the cheapest AI in the room. Bounded in time like every
		engine (TIMED_ENGINE, Issue 26): the configured `timeout_seconds'
		reaches it, an overrun is an error, and `elapsed_seconds' is never
		clamped.
	]"
	author: "Larry Rix"

class
	OLLAMA_PARTICIPANT

inherit
	PARTICIPANT

	TIMED_ENGINE

create
	make

feature {NONE} -- Initialization

	make (a_handle: READABLE_STRING_GENERAL; a_bot_user: CHAT_USER; a_client: OLLAMA_CLIENT; a_model: READABLE_STRING_GENERAL; a_max_characters, a_timeout_seconds: INTEGER)
		require
			handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (a_handle)
			bot: a_bot_user.is_bot
			bot_stored: a_bot_user.is_stored
			bot_active: a_bot_user.is_active
			bot_marked: a_bot_user.display_name.has_substring ({CHAT_EVENT_KINDS}.Bot_marker)
			model_given: not a_model.is_empty
			max_positive: a_max_characters > 0
			timeout_positive: a_timeout_seconds > 0
		do
			create handle.make_from_string_general (a_handle)
			bot_user := a_bot_user
			client := a_client
			create model.make_from_string_general (a_model)
			max_characters := a_max_characters
			timeout_seconds := a_timeout_seconds
			max_concurrent := 1
		ensure
			handle_set: handle.same_string_general (a_handle)
			model_set: model.same_string_general (a_model)
			timeout_set: timeout_seconds = a_timeout_seconds
			one_at_a_time: max_concurrent = 1
		end

feature -- Access

	model: STRING_32

feature -- Basic operations

	answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
		do
			calls := calls + 1
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501))
			-- Implementation in Phase 4: client.set_model (model); ask with the persona; record_run; cut to max_characters
		ensure then
			bounded_runtime: not last_timed_out implies elapsed_seconds <= timeout_seconds
			timeout_is_error: last_timed_out implies not Result.is_success
		end

feature {NONE} -- Implementation

	client: OLLAMA_CLIENT

invariant
	model_given: not model.is_empty
	one_at_a_time: max_concurrent = 1

end
