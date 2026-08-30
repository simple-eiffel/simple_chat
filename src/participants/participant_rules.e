note
	description: "[
		The handle, alias and `via' rules, usable from contracts before a
		participant exists - what CHAT_USER_RULES is to CHAT_USER.

		A handle is "@" followed by 1..`Handle_maximum' characters of
		[a-z0-9_-]: lowercase only, so the parser folds case in one place
		and every key elsewhere is exact; ASCII only, so `limit_key' may
		narrow it to STRING_8 without a precondition failing (M1).

		An alias is a word ending in ":" ("Claude:", "ROBOT:") or an "@name"
		that is not itself a registered handle. A `via' choice is "plain"
		or a handle-shaped shaper name ("@qwen").
	]"
	author: "Larry Rix"

class
	PARTICIPANT_RULES

feature -- Validation

	is_valid_handle (a_handle: READABLE_STRING_GENERAL): BOOLEAN
			-- "@" then 1..`Handle_maximum' characters of [a-z0-9_-]?
		local
			i: INTEGER
		do
			Result := a_handle.count >= 2 and a_handle.count <= Handle_maximum + 1 and then a_handle.code (1) = 64
			from i := 2 until i > a_handle.count or not Result loop
				Result := is_handle_code (a_handle.code (i))
				i := i + 1
			end
		ensure
			at_sign: Result implies a_handle.code (1) = 64
			bounded: Result implies (a_handle.count >= 2 and a_handle.count <= Handle_maximum + 1)
			lowercase: Result implies a_handle.same_string (a_handle.as_lower)
			no_blank: Result implies not a_handle.has_substring (" ")
		end

	is_valid_alias (a_alias: READABLE_STRING_GENERAL): BOOLEAN
			-- At least two characters, ending in ":" or beginning with "@"?
		do
			Result := a_alias.count >= 2 and then (a_alias.code (a_alias.count) = 58 or a_alias.code (1) = 64)
		ensure
			definition: Result = (a_alias.count >= 2 and then (a_alias.code (a_alias.count) = 58 or a_alias.code (1) = 64))
		end

	is_via_choice (a_choice: READABLE_STRING_GENERAL): BOOLEAN
			-- "plain", or a handle-shaped shaper name such as "@qwen"?
		do
			Result := a_choice.same_string ({ADDRESS_PARSER}.Via_plain) or is_valid_handle (a_choice)
		ensure
			definition: Result = (a_choice.same_string ({ADDRESS_PARSER}.Via_plain) or is_valid_handle (a_choice))
			lowercase: Result implies a_choice.same_string (a_choice.as_lower)
		end

	is_handle_code (a_code: NATURAL_32): BOOLEAN
			-- One of [a-z0-9_-]?
		do
			Result := (a_code >= 97 and a_code <= 122) or (a_code >= 48 and a_code <= 57) or a_code = 95 or a_code = 45
		end

feature -- Constants

	Handle_maximum: INTEGER = 32
			-- Characters after the "@".

end
