note
	description: "A participant that never answers: for tests, and for a handle configured off."
	author: "Larry Rix"

class
	NULL_PARTICIPANT

inherit
	PARTICIPANT

create
	make

feature {NONE} -- Initialization

	make (a_handle: READABLE_STRING_GENERAL; a_bot_user: CHAT_USER)
		require
			handle_shape: a_handle.count >= 2 and a_handle.starts_with ("@")
			bot: a_bot_user.is_bot
		do
			handle := a_handle.to_string_32
			bot_user := a_bot_user
			max_concurrent := 1
		ensure
			handle_set: handle.same_string_general (a_handle)
		end

feature -- Basic operations

	answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
		do
			calls := calls + 1
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, "This participant is switched off.", 503))
		ensure then
			never_succeeds: not Result.is_success
		end

end
