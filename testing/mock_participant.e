note
	description: "A scripted PARTICIPANT for the assault suite: answers with a fixed text, or fails on request."
	author: "Larry Rix"

class
	MOCK_PARTICIPANT

inherit
	PARTICIPANT

create
	make

feature {NONE} -- Initialization

	make (a_handle: READABLE_STRING_GENERAL; a_bot_user: CHAT_USER; a_scripted_text: READABLE_STRING_GENERAL)
		require
			handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (a_handle)
			bot: a_bot_user.is_bot
			bot_stored: a_bot_user.is_stored
			bot_active: a_bot_user.is_active
			bot_marked: a_bot_user.display_name.has_substring ({CHAT_EVENT_KINDS}.Bot_marker)
			scripted: not a_scripted_text.is_empty
		do
			create handle.make_from_string_general (a_handle)
			bot_user := a_bot_user
			create scripted_text.make_from_string_general (a_scripted_text)
			max_concurrent := 1
			max_characters := Default_max_characters
		ensure
			handle_set: handle.same_string_general (a_handle)
		end

feature -- Access

	scripted_text: STRING_32
	should_fail: BOOLEAN
	should_raise: BOOLEAN
			-- Raise inside `answer' (an engine that breaks its "never raises"
			-- promise), for the dispatcher's rescue path (NEW-7).

feature -- Element change

	set_should_fail (a_fail: BOOLEAN)
		do
			should_fail := a_fail
		ensure
			set: should_fail = a_fail
		end

	set_should_raise (a_raise: BOOLEAN)
		do
			should_raise := a_raise
		ensure
			set: should_raise = a_raise
		end

feature -- Basic operations

	answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
		local
			l_boom: DEVELOPER_EXCEPTION
		do
			if should_raise then
				create l_boom
				l_boom.raise
			end
			calls := calls + 1
			if should_fail then
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, "scripted failure", 503))
			else
				create Result.make_success (scripted_text.head (a_request.max_characters), Void)
			end
		end

end
