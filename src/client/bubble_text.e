note
	description: "[
		What a chat bubble can actually draw.

		SW_CHAT_THREAD wraps a bubble by splitting on the SPACE character
		alone, so a newline is never a break: it stays inside a "word" and
		is drawn as a glyph - the empty box Larry reported. His own
		messages are single lines and looked right; the assistant's are
		not, and every line break in them became a box. Nothing to do with
		emoji (the Noto artwork resolves correctly) and nothing to do with
		CRLF on the wire (the store holds exactly what was sent).

		`one_line' is the workaround: every line break becomes a space and
		runs of blanks collapse. THE STRUCTURE IS THE COST - a numbered
		list arrives as one flowing paragraph.

		RETIRE THIS CLASS WHEN simple_widgets' branch
		`feature/thread-lines-keys-selection' lands. That branch makes the
		thread break on newlines and lay out the lines it is given, at
		which point `one_line' is not merely unnecessary but harmful: it
		would flatten structure the thread could draw.
	]"
	author: "Larry Rix"

class
	BUBBLE_TEXT

feature -- Access

	one_line (a_text: READABLE_STRING_GENERAL): STRING_32
			-- `a_text' with every line break and tab turned into a space, and
			-- runs of blanks collapsed to one; no leading or trailing blank.
		local
			l_source: STRING_32
			i: INTEGER
			c: NATURAL_32
			l_blank, l_last_blank: BOOLEAN
		do
			l_source := a_text.to_string_32
			create Result.make (l_source.count)
			from i := 1 until i > l_source.count loop
				c := l_source.code (i)
				l_blank := c = 10 or c = 13 or c = 9 or c = 32
				if l_blank then
					if not l_last_blank and not Result.is_empty then
						Result.append_character (' ')
					end
				else
					Result.append_code (c)
				end
				l_last_blank := l_blank
				i := i + 1
			end
			if not Result.is_empty and then Result.item (Result.count) = ' ' then
				Result.remove_tail (1)
			end
		ensure
			no_line_breaks: not Result.has ('%N') and not Result.has ('%R')
			no_tabs: not Result.has ('%T')
			no_leading_blank: not Result.is_empty implies Result.item (1) /= ' '
			no_trailing_blank: not Result.is_empty implies Result.item (Result.count) /= ' '
			empty_stays_empty: a_text.is_empty implies Result.is_empty
		end

end
