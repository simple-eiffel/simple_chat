note
	description: "[
		Why an operation did not succeed: a stable code for programs, a
		message safe to show a person, and the HTTP status the web layer
		should answer with. Immutable.
	]"
	author: "Larry Rix"

class
	CHAT_ERROR

create
	make

feature {NONE} -- Initialization

	make (a_code: READABLE_STRING_8; a_message: READABLE_STRING_GENERAL; a_http_status: INTEGER)
			-- Error `a_code' with `a_message' answered as `a_http_status'.
		require
			code_given: not a_code.is_empty
			known: is_known_code (a_code)
			message_given: not a_message.is_empty
			is_error_status: a_http_status >= 400 and a_http_status <= 599
		do
			code := a_code.to_string_8
			message := a_message.to_string_32
			http_status := a_http_status
		ensure
			code_set: code.same_string (a_code)
			message_set: message.same_string_general (a_message)
			status_set: http_status = a_http_status
		end

feature -- Access

	code: STRING_8
			-- Stable identifier: "not_member", "too_long", "rate_limited",
			-- "bad_credentials", "locked_out", "exists", "too_large",
			-- "bad_type", "unavailable", "not_implemented".

	message: STRING_32
			-- Safe to show a person.

	http_status: INTEGER
			-- What the web layer answers.

feature -- Validation (contract support)

	is_known_code (a_code: READABLE_STRING_8): BOOLEAN
			-- One of the Code_* constants?
		do
			Result := a_code.same_string (Code_not_member) or a_code.same_string (Code_too_long) or a_code.same_string (Code_rate_limited)
				or a_code.same_string (Code_bad_credentials) or a_code.same_string (Code_locked_out) or a_code.same_string (Code_exists)
				or a_code.same_string (Code_too_large) or a_code.same_string (Code_bad_type) or a_code.same_string (Code_unavailable)
				or a_code.same_string (Code_not_implemented) or a_code.same_string (Code_refused)
		end

feature -- Constants

	Code_not_member: STRING_8 = "not_member"
	Code_too_long: STRING_8 = "too_long"
	Code_rate_limited: STRING_8 = "rate_limited"
	Code_bad_credentials: STRING_8 = "bad_credentials"
	Code_locked_out: STRING_8 = "locked_out"
	Code_exists: STRING_8 = "exists"
	Code_too_large: STRING_8 = "too_large"
	Code_bad_type: STRING_8 = "bad_type"
	Code_unavailable: STRING_8 = "unavailable"
	Code_not_implemented: STRING_8 = "not_implemented"
	Code_refused: STRING_8 = "refused"

invariant
	known_code: is_known_code (code)
	code_given: not code.is_empty
	message_given: not message.is_empty
	status_is_error: http_status >= 400 and http_status <= 599

end
