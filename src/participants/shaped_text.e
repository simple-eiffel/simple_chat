note
	description: "A shaper's outcome: the reshaped text, or why it could not."
	author: "Larry Rix"

class
	SHAPED_TEXT

create
	make_success,
	make_error

feature {NONE} -- Initialization

	make_success (a_text: READABLE_STRING_GENERAL)
		require
			text_given: not a_text.is_empty
		do
			text := a_text.to_string_32
			is_success := True
		ensure
			success: is_success
			text_set: text.same_string_general (a_text)
		end

	make_error (a_error: CHAT_ERROR)
		do
			error := a_error
			create text.make_empty
		ensure
			failure: not is_success
			error_set: error = a_error
		end

feature -- Access

	is_success: BOOLEAN
	text: STRING_32
	error: detachable CHAT_ERROR

invariant
	success_xor_error: is_success xor (error /= Void)
	success_has_text: is_success implies not text.is_empty

end
