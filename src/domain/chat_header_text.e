note
	description: "[
		The one rule for carrying a file name or a caption on an HTTP
		header line. A header value may hold printable ASCII and nothing
		else - SIMPLE_WINHTTP refuses a request whose header table is not
		wire-clean before a byte leaves the machine, and a raw UTF-8 byte
		on a header line is header injection's neighbour anyway - so the
		client writes the text as UTF-8 and percent-encodes every byte
		outside RFC 3986's unreserved set, and the request handler reads
		it back with `decoded'. Both sides ask this class, so there is one
		rule and not two (Single Choice).

		`decoded' is tolerant on purpose and cannot raise: a value with no
		percent sign comes back as plain UTF-8, unchanged, so a hand-made
		request carrying an ASCII name still works; a percent that is not
		followed by two hex digits stays a percent; bytes that are not
		valid UTF-8 are whatever {UTF_CONVERTER} makes of them, never an
		exception. Stateless - every query is a function of its argument.
	]"
	author: "Larry Rix"

class
	CHAT_HEADER_TEXT

feature -- Encoding

	encoded (a_text: READABLE_STRING_GENERAL): STRING_8
			-- `a_text' as UTF-8 bytes, every byte outside the unreserved set
			-- written as a percent sign and two upper-case hex digits.
		local
			l_utf8: STRING_8
			l_code: NATURAL_32
			i: INTEGER
		do
			l_utf8 := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text.to_string_32)
			create Result.make (l_utf8.count + 8)
			from
				i := 1
			until
				i > l_utf8.count
			loop
				l_code := l_utf8.code (i)
				if is_unreserved (l_code) then
					Result.extend (l_utf8.item (i))
				else
					Result.extend ('%%')
					Result.extend (hex_digit ((l_code // 16).to_integer_32))
					Result.extend (hex_digit ((l_code \\ 16).to_integer_32))
				end
				i := i + 1
			variant
				l_utf8.count - i + 1
			end
		ensure
			wire_clean: is_wire_clean (Result)
			empty_for_empty: a_text.is_empty implies Result.is_empty
			given_for_given: not a_text.is_empty implies not Result.is_empty
		end

	decoded (a_value: READABLE_STRING_8): STRING_32
			-- The text `encoded' made `a_value' of: every percent sign with two
			-- hex digits back to its byte, then the bytes read as UTF-8. Never raises.
		local
			l_bytes: STRING_8
			i: INTEGER
		do
			create l_bytes.make (a_value.count)
			from
				i := 1
			until
				i > a_value.count
			loop
				if a_value [i] = '%%' and then i + 2 <= a_value.count
					and then is_hex_digit (a_value [i + 1]) and then is_hex_digit (a_value [i + 2])
				then
					l_bytes.extend ((hex_value (a_value [i + 1]) * 16 + hex_value (a_value [i + 2])).to_character_8)
					i := i + 3
				else
					l_bytes.extend (a_value [i])
					i := i + 1
				end
			variant
				a_value.count - i + 1
			end
			Result := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (l_bytes)
		ensure
			empty_for_empty: a_value.is_empty implies Result.is_empty
		end

feature -- Validation (contract support)

	is_wire_clean (a_value: READABLE_STRING_8): BOOLEAN
			-- Printable ASCII with no blanks - what a header line carries
			-- verbatim, and what SIMPLE_WINHTTP's `is_clean_header_value'
			-- admits (it allows blanks too; `encoded' writes none).
		do
			Result := True
			across
				a_value as c
			loop
				Result := Result and c.code >= 33 and c.code <= 126
			end
		end

	is_unreserved (a_code: NATURAL_32): BOOLEAN
			-- RFC 3986's unreserved set: a letter, a digit, "-", ".", "_" or "~".
		do
			Result := (a_code >= 65 and a_code <= 90) or (a_code >= 97 and a_code <= 122)
				or (a_code >= 48 and a_code <= 57)
				or a_code = 45 or a_code = 46 or a_code = 95 or a_code = 126
		end

	is_hex_digit (a_character: CHARACTER_8): BOOLEAN
			-- 0-9, a-f or A-F?
		do
			Result := (a_character >= '0' and a_character <= '9')
				or (a_character >= 'a' and a_character <= 'f')
				or (a_character >= 'A' and a_character <= 'F')
		end

feature {NONE} -- Implementation

	hex_digit (a_value: INTEGER): CHARACTER_8
			-- The upper-case hex digit for `a_value' (0..15).
		require
			in_range: a_value >= 0 and a_value <= 15
		do
			if a_value < 10 then
				Result := (48 + a_value).to_character_8
			else
				Result := (55 + a_value).to_character_8
			end
		ensure
			hex: is_hex_digit (Result)
		end

	hex_value (a_character: CHARACTER_8): INTEGER
			-- The value of the hex digit `a_character' (0..15).
		require
			hex: is_hex_digit (a_character)
		do
			if a_character <= '9' then
				Result := a_character.code - 48
			elseif a_character <= 'F' then
				Result := a_character.code - 55
			else
				Result := a_character.code - 87
			end
		ensure
			in_range: Result >= 0 and Result <= 15
		end

end
