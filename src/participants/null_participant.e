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
			handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (a_handle)
			bot: a_bot_user.is_bot
			bot_stored: a_bot_user.is_stored
			bot_active: a_bot_user.is_active
			bot_marked: a_bot_user.display_name.has_substring ({CHAT_EVENT_KINDS}.Bot_marker)
		do
			create handle.make_from_string_general (a_handle)
			bot_user := a_bot_user
			max_concurrent := 1
			max_characters := Default_max_characters
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
