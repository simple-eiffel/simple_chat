note
	description: "The username and display-name rules, usable from contracts before a CHAT_USER exists."
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
			from i := 1 until i > a_name.count or not Result loop
				c := a_name.item (i)
				Result := (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c = '_'
				i := i + 1
			end
		end

	is_valid_display_name (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- 1..40 characters, not blank, no bidi control characters?
		local
			i: INTEGER
			c: NATURAL_32
			l_blank: BOOLEAN
		do
			Result := a_name.count >= 1 and a_name.count <= {CHAT_USER}.Display_name_maximum
			l_blank := True
			from i := 1 until i > a_name.count or not Result loop
				c := a_name.code (i)
				if (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069) then
					Result := False
				end
				if not (c = 32 or c = 9 or c = 10 or c = 13) then
					l_blank := False
				end
				i := i + 1
			end
			Result := Result and not l_blank
		end

end
