note
	description: "[
		The username, display-name and password-hash rules, in one place,
		usable from contracts before a CHAT_USER exists. CHAT_USER and
		CHAT_MEMBER delegate here (Single Choice).

		A display name is 1..40 code points, contains at least one visible
		character, and none of: C0/C1 controls, zero-width and format
		characters (U+200B-U+200F, U+2028-U+202E, U+2060-U+206F, U+FEFF).
		The last group is what a spoofer needs - an invisible name, or a
		reading-order override that makes "admin" out of "nimda".
	]"
	author: "Larry Rix"

class
	CHAT_USER_RULES

feature -- Validation

	is_valid_username (a_name: READABLE_STRING_8): BOOLEAN
			-- 1..32 characters of [a-z0-9_]?
		local
			i: INTEGER
			c: CHARACTER_8
		do
			Result := a_name.count >= 1 and a_name.count <= {CHAT_USER}.Username_maximum
			from
				i := 1
			until
				i > a_name.count or not Result
			loop
				c := a_name.item (i)
				Result := (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c = '_'
				i := i + 1
			end
		ensure
			bounded: Result implies (a_name.count >= 1 and a_name.count <= {CHAT_USER}.Username_maximum)
		end

	is_valid_display_name (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- 1..40 code points, at least one visible, no controls, no invisible or bidi-format characters?
		local
			i: INTEGER
			c: NATURAL_32
			l_visible: BOOLEAN
		do
			Result := a_name.count >= 1 and a_name.count <= {CHAT_USER}.Display_name_maximum
			from
				i := 1
			until
				i > a_name.count or not Result
			loop
				c := a_name.code (i)
				if is_forbidden_in_name (c) then
					Result := False
				elseif not is_space (c) then
					l_visible := True
				end
				i := i + 1
			end
			Result := Result and l_visible
		ensure
			bounded: Result implies (a_name.count >= 1 and a_name.count <= {CHAT_USER}.Display_name_maximum)
		end

	is_valid_human_display_name (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- A valid display name that nowhere contains the bot marker?
			-- (NEW-4: the badge that authenticates bots is reserved for them.)
		do
			Result := is_valid_display_name (a_name) and then
				not a_name.to_string_32.has_substring ({CHAT_EVENT_KINDS}.Bot_marker)
		ensure
			valid_when_true: Result implies is_valid_display_name (a_name)
			unmarked_when_true: Result implies not a_name.to_string_32.has_substring ({CHAT_EVENT_KINDS}.Bot_marker)
		end

	is_marked_display_name (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- A valid display name that begins with the bot marker?
		do
			Result := is_valid_display_name (a_name) and then
				a_name.to_string_32.starts_with ({CHAT_EVENT_KINDS}.Bot_marker)
		ensure
			valid_when_true: Result implies is_valid_display_name (a_name)
			marked_when_true: Result implies a_name.to_string_32.starts_with ({CHAT_EVENT_KINDS}.Bot_marker)
		end

	is_forbidden_in_name (a_code: NATURAL_32): BOOLEAN
			-- A control, a zero-width or format character, or a bidi override?
		do
			Result := a_code < 0x20 or (a_code >= 0x7F and a_code <= 0x9F)
				or (a_code >= 0x200B and a_code <= 0x200F)
				or (a_code >= 0x2028 and a_code <= 0x202E)
				or (a_code >= 0x2060 and a_code <= 0x206F)
				or a_code = 0xFEFF
		end

	is_space (a_code: NATURAL_32): BOOLEAN
		do
			Result := a_code = 32 or a_code = 9 or a_code = 10 or a_code = 13 or a_code = 0xA0 or a_code = 0x3000
		end

	is_pbkdf2 (a_hash: READABLE_STRING_8): BOOLEAN
			-- salt$iterations$digest: a 32-hex salt, an iteration count at the floor or above, a 64-hex digest?
		local
			l_parts: LIST [READABLE_STRING_8]
		do
			l_parts := a_hash.split ('$')
			Result := l_parts.count = 3 and then (l_parts [1].count = 32 and is_hex (l_parts [1])
				and l_parts [2].is_integer and then l_parts [2].to_integer >= {PASSWORD_HASHER}.Minimum_iterations
				and l_parts [3].count = 64 and is_hex (l_parts [3]))
		ensure
			shape: Result implies a_hash.occurrences ('$') = 2
		end

	is_hex (a_text: READABLE_STRING_8): BOOLEAN
			-- Lowercase hexadecimal, non-empty?
		do
			Result := not a_text.is_empty and then across a_text as ch all (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f') end
		end

end
