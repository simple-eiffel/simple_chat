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
			handle_shape: a_handle.count >= 2 and a_handle.starts_with ("@")
			bot: a_bot_user.is_bot
			scripted: not a_scripted_text.is_empty
		do
			handle := a_handle.to_string_32
			bot_user := a_bot_user
			scripted_text := a_scripted_text.to_string_32
			max_concurrent := 1
		ensure
			handle_set: handle.same_string_general (a_handle)
		end

feature -- Access

	scripted_text: STRING_32
	should_fail: BOOLEAN

feature -- Element change

	set_should_fail (a_fail: BOOLEAN)
		do
			should_fail := a_fail
		ensure
			set: should_fail = a_fail
		end

feature -- Basic operations

	answer (a_request: PARTICIPANT_REQUEST): PARTICIPANT_ANSWER
		do
			calls := calls + 1
			if should_fail then
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, "scripted failure", 503))
			else
				create Result.make_success (scripted_text.head (a_request.max_characters), Void)
			end
		end

end
