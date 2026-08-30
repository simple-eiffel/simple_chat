note
	description: "What the address parser found at the start of a message: a handle, the request text, and an optional `via' choice."
	author: "Larry Rix"

class
	ADDRESSED_REQUEST

create
	make

feature {NONE} -- Initialization

	make (a_handle, a_text: READABLE_STRING_GENERAL; a_via: detachable READABLE_STRING_GENERAL)
		require
			handle_shape: a_handle.count >= 2 and a_handle.starts_with ("@")
			text_given: not a_text.is_empty
			via_given_if_attached: attached a_via as v implies not v.is_empty
		do
			handle := a_handle.to_string_32
			text := a_text.to_string_32
			if attached a_via as v then
				via := v.to_string_32
			end
		ensure
			handle_set: handle.same_string_general (a_handle)
			text_set: text.same_string_general (a_text)
			via_set: (via = Void) = (a_via = Void)
		end

feature -- Access

	handle: STRING_32
			-- "@tools-larry", lowercased.

	text: STRING_32
			-- The request, trimmed, with any trailing "via …" removed.

	via: detachable STRING_32
			-- "plain", "@qwen", "@claude" when the member chose a shaper.

invariant
	handle_shape: handle.count >= 2 and handle.starts_with ("@")
	text_given: not text.is_empty
	via_given_if_attached: attached via as v implies not v.is_empty

end
