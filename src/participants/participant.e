note
	description: "[
		Something in the room that answers when addressed by its handle:
		an AI, a tool with no AI, or a tool whose output a model phrases.
		Every participant is an ordinary member with a bot identity whose
		display name carries the marker, and its own rate limit
		(addendum 09).
	]"
	author: "Larry Rix"

deferred class
	PARTICIPANT

feature -- Access

	handle: STRING_32
			-- "@tools-larry"; lowercase; what a message starts with to address this.

	bot_user: CHAT_USER
			-- The member the answers are posted as.

	calls: INTEGER
			-- Answers attempted so far.

	max_concurrent: INTEGER
			-- How many requests may be in flight at once (1 for Claude).

	limit_key (a_asker_id: INTEGER_64): STRING_8
			-- The rate-limit key for `a_asker_id' asking this participant.
		require
			positive: a_asker_id > 0
		do
			Result := "p:" + handle.to_string_8 + ":" + a_asker_id.out
		ensure
			prefixed: Result.starts_with ("p:")
		end

feature -- Basic operations

	answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
			-- The reply to `a_request', or why there is none. Never raises.
		deferred
		ensure
			counted: calls = old calls + 1
			outcome: Result.is_success xor (Result.error /= Void)
			bounded: Result.is_success implies Result.text.count <= a_request.max_characters
		end

invariant
	handle_shape: handle.count >= 2 and handle.starts_with ("@")
	bot_is_bot: bot_user.is_bot
	calls_non_negative: calls >= 0
	concurrency_positive: max_concurrent >= 1

end
