note
	description: "A participant's reply: text and optionally an image the dispatcher should post; or the reason there is none."
	author: "Larry Rix"

class
	PARTICIPANT_ANSWER

create
	make_success,
	make_error

feature {NONE} -- Initialization

	make_success (a_text: READABLE_STRING_GENERAL; a_image_path: detachable READABLE_STRING_GENERAL)
		require
			text_given: not a_text.is_empty
			path_given_if_attached: attached a_image_path as p implies not p.is_empty
		do
			text := a_text.to_string_32
			if attached a_image_path as p then
				image_path := p.to_string_32
			end
			is_success := True
		ensure
			success: is_success
			text_set: text.same_string_general (a_text)
			image_set: (image_path = Void) = (a_image_path = Void)
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
	image_path: detachable STRING_32
	error: detachable CHAT_ERROR

invariant
	success_xor_error: is_success xor (error /= Void)
	success_has_text: is_success implies not text.is_empty

end
