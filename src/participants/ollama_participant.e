note
	description: "`@qwen' and friends: a local model through OLLAMA_CLIENT as a room member - the cheapest AI in the room."
	author: "Larry Rix"

class
	OLLAMA_PARTICIPANT

inherit
	PARTICIPANT

create
	make

feature {NONE} -- Initialization

	make (a_handle: READABLE_STRING_GENERAL; a_bot_user: CHAT_USER; a_client: OLLAMA_CLIENT; a_model: READABLE_STRING_GENERAL; a_max_characters: INTEGER)
		require
			handle_shape: a_handle.count >= 2 and a_handle.starts_with ("@")
			bot: a_bot_user.is_bot
			model_given: not a_model.is_empty
			max_positive: a_max_characters > 0
		do
			handle := a_handle.to_string_32
			bot_user := a_bot_user
			client := a_client
			model := a_model.to_string_32
			max_characters := a_max_characters
			max_concurrent := 1
		ensure
			handle_set: handle.same_string_general (a_handle)
			model_set: model.same_string_general (a_model)
		end

feature -- Access

	model: STRING_32
	max_characters: INTEGER

feature -- Basic operations

	answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
		do
			calls := calls + 1
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501))
			-- Implementation in Phase 4
		end

feature {NONE} -- Implementation

	client: OLLAMA_CLIENT

invariant
	model_given: not model.is_empty
	max_positive: max_characters > 0

end
