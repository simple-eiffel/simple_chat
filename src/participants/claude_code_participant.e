note
	description: "[
		`@claude' (aliases "Claude:" / "ROBOT:"): answers through
		CLAUDE_CODE_CLIENT - claude -p on Larry's subscription - with the
		vault as working directory so its skills and memory load, a persona
		that keeps the chat register and never fabricates specifics about
		people, and a hard timeout (intent-v2 Q7).
	]"
	author: "Larry Rix"

class
	CLAUDE_CODE_PARTICIPANT

inherit
	PARTICIPANT

create
	make

feature {NONE} -- Initialization

	make (a_handle: READABLE_STRING_GENERAL; a_bot_user: CHAT_USER; a_client: CLAUDE_CODE_CLIENT;
			a_working_directory: READABLE_STRING_GENERAL; a_max_characters, a_timeout_seconds: INTEGER)
		require
			handle_shape: a_handle.count >= 2 and a_handle.starts_with ("@")
			bot: a_bot_user.is_bot
			directory_given: not a_working_directory.is_empty
			max_positive: a_max_characters > 0
			timeout_positive: a_timeout_seconds > 0
		do
			handle := a_handle.to_string_32
			bot_user := a_bot_user
			client := a_client
			working_directory := a_working_directory.to_string_32
			max_characters := a_max_characters
			timeout_seconds := a_timeout_seconds
			max_concurrent := 1
		ensure
			handle_set: handle.same_string_general (a_handle)
			one_at_a_time: max_concurrent = 1
		end

feature -- Access

	working_directory: STRING_32
	max_characters: INTEGER
	timeout_seconds: INTEGER

	last_session_id: detachable STRING_32
			-- For continuity later (I-006).

feature -- Basic operations

	answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
		do
			calls := calls + 1
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501))
			-- Implementation in Phase 4: persona system prompt; client in working_directory; --json-schema {text, image_path}; kill at timeout
		end

feature {NONE} -- Implementation

	client: CLAUDE_CODE_CLIENT

invariant
	max_positive: max_characters > 0
	timeout_positive: timeout_seconds > 0
	one_at_a_time: max_concurrent = 1

end
