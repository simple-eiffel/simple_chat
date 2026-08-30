note
	description: "[
		What the address parser found at the start of a message: a handle,
		the request text, and an optional `via' choice. The handle is a
		valid, lowercase PARTICIPANT_RULES handle and the choice is one the
		tool layer can honour - "plain" or a shaper's handle-shaped name -
		so nothing downstream re-checks shapes (M2).
	]"
	author: "Larry Rix"

class
	ADDRESSED_REQUEST

create
	make

feature {NONE} -- Initialization

	make (a_handle, a_text: READABLE_STRING_GENERAL; a_via: detachable READABLE_STRING_GENERAL)
		require
			handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (a_handle)
			text_given: not a_text.is_empty
			via_given_if_attached: attached a_via as v implies not v.is_empty
			via_shape: attached a_via as v implies (create {PARTICIPANT_RULES}).is_via_choice (v)
		do
			create handle.make_from_string_general (a_handle)
			create text.make_from_string_general (a_text)
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
			-- The request, trimmed, with any trailing "via ..." removed.

	via: detachable STRING_32
			-- "plain", "@qwen", "@claude" when the member chose a shaper.

invariant
	handle_valid: (create {PARTICIPANT_RULES}).is_valid_handle (handle)
	handle_lowercase: handle.same_string (handle.as_lower)
	handle_no_blank: not handle.has_substring (" ")
	text_given: not text.is_empty
	via_given_if_attached: attached via as v implies not v.is_empty
	via_shape: attached via as v implies (v.same_string ({ADDRESS_PARSER}.Via_plain) or v.starts_with ("@"))
	via_choice: attached via as v implies (create {PARTICIPANT_RULES}).is_via_choice (v)

end
