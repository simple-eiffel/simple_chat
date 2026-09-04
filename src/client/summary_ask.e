note
	description: "[
		Whether a line the member typed is asking for a SUMMARY rather than
		asking the room's assistant a question - and, when it names one, how
		many minutes it wants summarised.

		This is a CLIENT-SIDE rule, and it has to be, because the answer
		never becomes a room event: a summary is drawn in the asker's own
		window and nowhere else (events are never per-person). So the client
		must know, before it posts anything, that this line is not a post.

		The rule is deliberately small and deliberately conservative. A line
		counts only when, once every @mention is taken out of it, what is
		left OPENS with one of `Verbs' - "sum", "summary", "summarise",
		"summarize", "recap", "catch up", "catch me up". Anything else,
		including a question that merely contains the word "summary"
		somewhere in the middle, is an ordinary message and is posted as one.
		The cost of guessing wrong is silence where the room expected a
		question, so the rule would rather miss than over-reach.
	]"
	author: "Larry Rix"

class
	SUMMARY_ASK

feature -- Status report

	is_summary_ask (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_text', with its mentions removed, OPEN with a summary verb?
		local
			l_rest: STRING_32
		do
			l_rest := without_mentions (a_text)
			Result := across Verbs as v some opens_with_word (l_rest, v) end
		ensure
			never_empty_handed: Result implies not without_mentions (a_text).is_empty
		end

	opens_with_word (a_text: READABLE_STRING_32; a_word: READABLE_STRING_32): BOOLEAN
			-- Does `a_text' begin with `a_word' as a whole word (end of line,
			-- or a non-letter after it)? "summarise" must not match "sum".
		local
			c: NATURAL_32
		do
			if a_text.count >= a_word.count and then a_text.substring (1, a_word.count).as_lower.same_string (a_word) then
				if a_text.count = a_word.count then
					Result := True
				else
					c := a_text.code (a_word.count + 1)
					Result := not is_letter (c)
				end
			end
		end

feature -- Access

	minutes_of (a_text: READABLE_STRING_GENERAL): INTEGER
			-- The window `a_text' names - "last 10 minutes", "30 min" - or 0
			-- when it names none. Bounded by `Minutes_maximum': a member who
			-- types a year does not get a year's transcript into an engine.
		local
			l_words: ARRAYED_LIST [STRING_32]
			i, l_number: INTEGER
		do
			l_words := words_of (without_mentions (a_text))
			from i := 1 until i > l_words.count or Result > 0 loop
				if l_words [i].is_integer then
					l_number := l_words [i].to_integer
					if l_number > 0 and i < l_words.count and then is_minute_word (l_words [i + 1]) then
						Result := l_number.min (Minutes_maximum)
					end
				end
				i := i + 1
			end
		ensure
			non_negative: Result >= 0
			bounded: Result <= Minutes_maximum
		end

	without_mentions (a_text: READABLE_STRING_GENERAL): STRING_32
			-- `a_text' with every "@word" removed and the remains trimmed.
		do
			create Result.make (a_text.count)
			across words_of (a_text.to_string_32) as w loop
				if w.count < 1 or else w.code (1) /= 64 then
					if not Result.is_empty then
						Result.append_character (' ')
					end
					Result.append (w)
				end
			end
		ensure
			no_mentions: not Result.has ('@')
		end

	words_of (a_text: READABLE_STRING_32): ARRAYED_LIST [STRING_32]
			-- `a_text' split on blanks, empties dropped.
		local
			i: INTEGER
			l_word: STRING_32
		do
			create Result.make (8)
			create l_word.make_empty
			from i := 1 until i > a_text.count loop
				if is_blank (a_text.code (i)) then
					if not l_word.is_empty then
						Result.extend (l_word)
						create l_word.make_empty
					end
				else
					l_word.append_code (a_text.code (i))
				end
				i := i + 1
			end
			if not l_word.is_empty then
				Result.extend (l_word)
			end
		ensure
			none_empty: across Result as w all not w.is_empty end
		end

feature {NONE} -- Implementation

	is_minute_word (a_word: READABLE_STRING_32): BOOLEAN
			-- "min", "mins", "minute", "minutes", with or without a trailing stop?
		local
			l_bare: STRING_32
		do
			l_bare := a_word.as_lower
			from until l_bare.is_empty or else is_letter (l_bare.code (l_bare.count)) loop
				l_bare.remove_tail (1)
			end
			Result := l_bare.same_string ({STRING_32} "min") or l_bare.same_string ({STRING_32} "mins")
				or l_bare.same_string ({STRING_32} "minute") or l_bare.same_string ({STRING_32} "minutes")
		end

	is_letter (a_code: NATURAL_32): BOOLEAN
		do
			Result := (a_code >= 65 and a_code <= 90) or (a_code >= 97 and a_code <= 122)
		end

	is_blank (a_code: NATURAL_32): BOOLEAN
		do
			Result := a_code = 32 or a_code = 9 or a_code = 10 or a_code = 13
		end

feature -- Constants

	Verbs: ARRAYED_LIST [STRING_32]
			-- Every opening that means "summarise", lowercase. "catch" covers
			-- "catch up" and "catch me up" alike, because the word opens nothing
			-- else a member would type at an assistant.
		once
			create Result.make (6)
			Result.extend ({STRING_32} "summarise")
			Result.extend ({STRING_32} "summarize")
			Result.extend ({STRING_32} "summary")
			Result.extend ({STRING_32} "sum")
			Result.extend ({STRING_32} "recap")
			Result.extend ({STRING_32} "catch")
		ensure
			not_empty: not Result.is_empty
		end

	Minutes_maximum: INTEGER = 1440
			-- A day. Past it the window is the day, not the number typed.

end
