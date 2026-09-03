note
	description: "[
		Recognizes an addressed message: "@handle request", or a registered
		alias such as "Claude:" / "ROBOT:" / "@robot", case-insensitive, at
		the very start; with an optional trailing "via <choice>" (addendum
		09). Only handles present in the registry - directly or through its
		aliases - are addresses; anything else is ordinary text.

		The boundary rule (M2): the leading token is the whole run of handle
		characters after "@", so "@claudette" never addresses "@claude" and
		"@Claude," addresses "@claude"; the token must end the text or be
		followed by a blank, a line break, "," or ":". A handle with nothing
		after it is addressed but asks nothing: `parse' gives Void. A
		trailing "via" is honoured only when its choice is one a tool could
		honour ("plain" or "@name"); "via train" stays in the text.

		MENTION ANYWHERE (Phase 4). `mentioned_handles' widens M2 from the
		start of the text to the whole of it, and states the boundary as one
		rule: a message mentions a participant when, anywhere in its text, an
		"@" stands that is NOT itself preceded by a handle character
		([a-z0-9_-], case folded), the unbroken run of handle characters after
		it equals that participant's handle or one of its "@"-shaped aliases,
		and that run ends the text or is followed by a character that is not a
		handle character. So "@Claude", "@claude:", "... @claude ...",
		"@claude?" and "(@claude)" all mention "@claude"; "@claudette" and
		"@claude_bot" do not (their run is longer - "_" is a handle
		character); "bob@claude" does not (the "@" follows a handle
		character); case never matters. Colon aliases ("Claude:") keep the
		older start-of-text rule - they are ordinary words anywhere else -
		and `address_of' / `is_addressed' / `parse' are untouched, so every
		message that was addressed before is addressed exactly as before.
		`addressed_body' rewrites a middle mention into the leading form, so
		one addressed-request path serves both.
	]"
	author: "Larry Rix"

class
	ADDRESS_PARSER

create
	make

feature {NONE} -- Initialization

	make (a_registry: PARTICIPANT_REGISTRY)
		do
			registry := a_registry
		ensure
			registry_set: registry = a_registry
		end

feature -- Access

	registry: PARTICIPANT_REGISTRY

	leading_handle (a_body: READABLE_STRING_GENERAL): STRING_32
			-- The handle-shaped token `a_body' begins with, lowercased -
			-- "@Claude, hi" gives "@claude" - or empty: no "@" first, no
			-- handle characters after it, no boundary after them, or too long.
		local
			i: INTEGER
			l_lower: STRING_32
		do
			create Result.make_empty
			if a_body.count >= 2 and then a_body.code (1) = 64 then
				l_lower := a_body.to_string_32.as_lower
				from i := 2 until i > l_lower.count or else not rules.is_handle_code (l_lower.code (i)) loop
					i := i + 1
				end
				if i > 2 and then i - 1 <= {PARTICIPANT_RULES}.Handle_maximum + 1 and then (i > l_lower.count or else is_boundary_code (l_lower.code (i))) then
					Result := l_lower.substring (1, i - 1)
				end
			end
		ensure
			shape: Result.is_empty or else rules.is_valid_handle (Result)
			at_start: not Result.is_empty implies a_body.to_string_32.as_lower.starts_with (Result)
			whole_token: not Result.is_empty implies (a_body.count = Result.count or else not rules.is_handle_code (a_body.to_string_32.as_lower.code (Result.count + 1)))
		end

	address_token (a_body: READABLE_STRING_GENERAL): STRING_32
			-- The text at the start of `a_body' that names a participant, lowercased:
			-- the leading handle when it is registered or an alias, else the colon
			-- alias ("claude:") `a_body' begins with; empty when none.
		local
			l_handle, l_lower: STRING_32
		do
			create Result.make_empty
			l_handle := leading_handle (a_body)
			if not l_handle.is_empty then
				if registry.has (l_handle) or registry.has_alias (l_handle) then
					Result := l_handle
				end
			else
				l_lower := a_body.to_string_32.as_lower
				across registry.alias_names as a loop
					if Result.is_empty and then a.code (a.count) = 58 and then l_lower.starts_with (a) then
						Result := a
					end
				end
			end
		ensure
			at_start: not Result.is_empty implies a_body.to_string_32.as_lower.starts_with (Result)
			names_someone: not Result.is_empty implies (registry.has (Result) or registry.has_alias (Result))
		end

	address_of (a_body: READABLE_STRING_GENERAL): STRING_32
			-- The registered handle `a_body' addresses - directly, or through an alias - or empty.
		local
			l_token: STRING_32
		do
			l_token := address_token (a_body)
			if l_token.is_empty then
				create Result.make_empty
			elseif registry.has (l_token) then
				Result := l_token
			else
				Result := registry.handle_of_alias (l_token)
			end
		ensure
			registered: Result.is_empty or else registry.has (Result)
			direct: (not leading_handle (a_body).is_empty and then registry.has (leading_handle (a_body))) implies Result.same_string (leading_handle (a_body))
			empty_when_unnamed: address_token (a_body).is_empty = Result.is_empty
		end

feature -- Basic operations

	parse (a_body: READABLE_STRING_GENERAL): detachable ADDRESSED_REQUEST
			-- The request at the start of `a_body', or Void when it is not
			-- addressed or nothing is asked (a bare handle, or only a "via").
		local
			l_handle, l_token, l_rest: STRING_32
			l_via: detachable STRING_32
		do
			l_handle := address_of (a_body)
			if not l_handle.is_empty then
				l_token := address_token (a_body)
				l_rest := a_body.to_string_32.substring (l_token.count + 1, a_body.count)
				if not l_rest.is_empty and then (l_rest.code (1) = 44 or l_rest.code (1) = 58) then
					l_rest := l_rest.substring (2, l_rest.count)
				end
				l_via := via_of (l_rest)
				if l_via /= Void then
					l_rest := without_via (l_rest)
				end
				l_rest.left_adjust
				l_rest.right_adjust
				if not l_rest.is_empty then
					create Result.make (l_handle, l_rest, l_via)
				end
			end
		ensure
			known_handle: attached Result as r implies registry.has (r.handle)
			from_body: attached Result as r implies r.handle.same_string (address_of (a_body))
			consistent: Result /= Void implies is_addressed (a_body)
			text_in_body: attached Result as r implies a_body.to_string_32.has_substring (r.text)
			text_not_blank: attached Result as r implies (not r.text.is_empty and then r.text.code (1) /= 32 and then r.text.code (r.text.count) /= 32)
			via_in_body: (attached Result as r and then attached r.via as v) implies a_body.to_string_32.as_lower.has_substring (v)
			boundary: (attached Result as r and then a_body.to_string_32.as_lower.starts_with (r.handle)) implies (a_body.count = r.handle.count or else not rules.is_handle_code (a_body.to_string_32.as_lower.code (r.handle.count + 1)))
		end

	is_addressed (a_body: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_body' begin with a registered handle or alias?
		do
			Result := not address_of (a_body).is_empty
		ensure
			definition: Result = not address_of (a_body).is_empty
			empty_is_plain: a_body.is_empty implies not Result
		end

feature -- Access (mentions anywhere in the text)

	mention_tokens: ARRAYED_LIST [STRING_32]
			-- Every "@"-shaped token that names a participant: the registered
			-- handles and the "@"-shaped aliases, lowercase, handles first.
			-- A colon alias ("claude:") is not one: it is an ordinary word
			-- anywhere but the start, and only `address_token' reads it.
		local
			l_alias: STRING_32
		do
			create Result.make (registry.count + registry.alias_count)
			Result.compare_objects
			across registry.participants as p loop
				Result.extend (p.handle.as_lower)
			end
			across registry.alias_names as a loop
				if a.code (1) = 64 then
					l_alias := a.as_lower
					if not Result.has (l_alias) then
						Result.extend (l_alias)
					end
				end
			end
		ensure
			at_shaped: across Result as t all t.count >= 2 and then t.code (1) = 64 end
			all_known: across Result as t all registry.has (t) or registry.has_alias (t) end
		end

	handle_behind (a_token: READABLE_STRING_GENERAL): STRING_32
			-- The registered handle `a_token' names, itself or as an alias.
		require
			names_someone: registry.has (a_token) or registry.has_alias (a_token)
		do
			if registry.has (a_token) then
				Result := a_token.to_string_32.as_lower
			else
				Result := registry.handle_of_alias (a_token)
			end
		ensure
			registered: registry.has (Result)
		end

	mentioned_handles (a_body: READABLE_STRING_GENERAL): ARRAYED_LIST [STRING_32]
			-- The registered handles `a_body' mentions anywhere - in the order
			-- of first mention, each once, whatever the case, wherever in the
			-- text they stand (the rule is in this class's note).
		local
			i: INTEGER
			l_handle: STRING_32
		do
			create Result.make (2)
			Result.compare_objects
			from i := 1 until i > a_body.count loop
				across mention_tokens as t loop
					if is_mention_at (a_body, t, i) then
						l_handle := handle_behind (t)
						if not Result.has (l_handle) then
							Result.extend (l_handle)
						end
					end
				end
				i := i + 1
			end
		ensure
			all_registered: across Result as h all registry.has (h) end
			each_once: across Result as h all Result.occurrences (h) = 1 end
			empty_when_blank: a_body.is_empty implies Result.is_empty
		end

	mention_token_at (a_body, a_handle: READABLE_STRING_GENERAL; a_index: INTEGER): detachable STRING_32
			-- The token of `a_handle' - its own handle or one of its
			-- "@"-shaped aliases - standing as a whole mention at `a_index'
			-- of `a_body'; Void when none does.
		require
			registered: registry.has (a_handle)
			in_range: a_index >= 1 and a_index <= a_body.count
		do
			across mention_tokens as t loop
				if Result = Void and then handle_behind (t).same_string_general (a_handle.to_string_32.as_lower)
					and then is_mention_at (a_body, t, a_index)
				then
					Result := t
				end
			end
		ensure
			stands_there: attached Result as t implies is_mention_at (a_body, t, a_index)
			owned: attached Result as t implies handle_behind (t).same_string_general (a_handle.to_string_32.as_lower)
		end

	body_without_mentions_of (a_body, a_handle: READABLE_STRING_GENERAL): STRING_32
			-- `a_body' with every mention of `a_handle' taken out, together
			-- with the ":" or "," that followed it and the blanks around it,
			-- and the words on either side closed up: "hello @Claude what is
			-- 2+2" gives "hello what is 2+2", "so what @claude?" gives "so
			-- what?".
		require
			registered: registry.has (a_handle)
		local
			i: INTEGER
		do
			create Result.make (a_body.count)
			from i := 1 until i > a_body.count loop
				if attached mention_token_at (a_body, a_handle, i) as t then
					i := i + t.count
					if i <= a_body.count and then (a_body.code (i) = 58 or a_body.code (i) = 44) then
						i := i + 1
					end
					from until i > a_body.count or else not is_blank_code (a_body.code (i)) loop
						i := i + 1
					end
					Result.right_adjust
					if not Result.is_empty and then (i <= a_body.count and then not is_closing_code (a_body.code (i))) then
						Result.append_character (' ')
					end
				else
					Result.append_code (a_body.code (i))
					i := i + 1
				end
			end
			Result.left_adjust
			Result.right_adjust
		ensure
			no_longer: Result.count <= a_body.count
			trimmed: Result.is_empty or else (not is_blank_code (Result.code (1)) and not is_blank_code (Result.code (Result.count)))
		end

	addressed_body (a_body, a_handle: READABLE_STRING_GENERAL): STRING_32
			-- `a_body' rewritten so `a_handle' leads it: the handle, then the
			-- text with that participant's mentions taken out. A message that
			-- names the bot in the middle therefore reaches the very same
			-- addressed-request path - `parse', `via', the character cap - as
			-- one that starts with it, and nothing downstream learns a second
			-- addressing rule.
		require
			registered: registry.has (a_handle)
		local
			l_rest: STRING_32
		do
			Result := a_handle.to_string_32.as_lower
			l_rest := body_without_mentions_of (a_body, a_handle)
			if not l_rest.is_empty then
				Result.append_character (' ')
				Result.append (l_rest)
			end
		ensure
			leads: Result.starts_with (a_handle.to_string_32.as_lower)
			addressed_here: address_of (Result).same_string (a_handle.to_string_32.as_lower)
		end

feature -- Status report

	mentions (a_body, a_token: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_token' stand as a whole mention anywhere in `a_body'?
		require
			at_shaped: a_token.count >= 2 and then a_token.code (1) = 64
		local
			i: INTEGER
		do
			from i := 1 until i > a_body.count or Result loop
				Result := is_mention_at (a_body, a_token, i)
				i := i + 1
			end
		ensure
			blank_never: a_body.is_empty implies not Result
		end

	mentions_handle (a_body, a_handle: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_body' mention `a_handle' anywhere, by its handle or by
			-- one of its "@"-shaped aliases?
		require
			registered: registry.has (a_handle)
		do
			Result := mentioned_handles (a_body).has (a_handle.to_string_32.as_lower)
		ensure
			definition: Result = mentioned_handles (a_body).has (a_handle.to_string_32.as_lower)
		end

	is_mention_at (a_body, a_token: READABLE_STRING_GENERAL; a_index: INTEGER): BOOLEAN
			-- Does `a_token' stand at `a_index' of `a_body' as a whole
			-- mention? The "@" must not itself follow a handle character (so
			-- "bob@claude" mentions nobody), the run of handle characters
			-- after it must be exactly the token's (so "@claudette" and
			-- "@claude_bot" are not "@claude"), and the run must end the text
			-- or be followed by a character that is not a handle character
			-- (so "@claude,", "@claude:" and "@claude?" all count). Case is
			-- folded on both sides.
		require
			at_shaped: a_token.count >= 2 and then a_token.code (1) = 64
			in_range: a_index >= 1 and a_index <= a_body.count
		local
			l_lower, l_token: STRING_32
			j: INTEGER
		do
			l_lower := a_body.to_string_32.as_lower
			l_token := a_token.to_string_32.as_lower
			if a_index + l_token.count - 1 <= l_lower.count
				and then l_lower.substring (a_index, a_index + l_token.count - 1).same_string (l_token)
				and then (a_index = 1 or else not rules.is_handle_code (l_lower.code (a_index - 1)))
			then
				j := a_index + l_token.count
				Result := j > l_lower.count or else not rules.is_handle_code (l_lower.code (j))
			end
		ensure
			token_there: Result implies a_body.to_string_32.as_lower.substring (a_index, a_index + a_token.count - 1).same_string (a_token.to_string_32.as_lower)
			whole_word: Result implies (a_index + a_token.count > a_body.count or else not rules.is_handle_code (a_body.to_string_32.as_lower.code (a_index + a_token.count)))
			never_after_a_handle_character: Result implies (a_index = 1 or else not rules.is_handle_code (a_body.to_string_32.as_lower.code (a_index - 1)))
		end

	is_closing_code (a_code: NATURAL_32): BOOLEAN
			-- A closing mark - "." "," ";" ":" "!" "?" ")" "]" "}" - one that
			-- must stay against the word before it when a mention between
			-- them is taken out?
		do
			Result := a_code = 46 or a_code = 44 or a_code = 59 or a_code = 58 or a_code = 33
				or a_code = 63 or a_code = 41 or a_code = 93 or a_code = 125
		end

	is_boundary_code (a_code: NATURAL_32): BOOLEAN
			-- A blank, a line break, "," or ":"?
		do
			Result := is_blank_code (a_code) or a_code = 44 or a_code = 58
		end

	is_blank_code (a_code: NATURAL_32): BOOLEAN
			-- A space, a tab or a line break?
		do
			Result := a_code = 32 or a_code = 9 or a_code = 10 or a_code = 13
		end

	via_of (a_text: READABLE_STRING_GENERAL): detachable STRING_32
			-- The choice a trailing "via <choice>" makes, lowercased, when the
			-- choice is one a tool could honour; Void otherwise.
		local
			l_words: LIST [STRING_32]
			l_last: STRING_32
		do
			l_words := words_of (a_text)
			if l_words.count >= 2 then
				l_last := l_words [l_words.count].as_lower
				if l_words [l_words.count - 1].as_lower.same_string (Via_keyword) and then rules.is_via_choice (l_last) then
					Result := l_last
				end
			end
		ensure
			choice_shaped: attached Result as v implies rules.is_via_choice (v)
			in_text: attached Result as v implies a_text.to_string_32.as_lower.has_substring (v)
		end

	without_via (a_text: READABLE_STRING_GENERAL): STRING_32
			-- `a_text' without its trailing "via <choice>" and the blanks before it.
		require
			has_via: via_of (a_text) /= Void
		local
			i: INTEGER
		do
			create Result.make_from_string_general (a_text)
			Result.right_adjust
			i := Result.count
			from until i < 1 or else is_blank_code (Result.code (i)) loop
				i := i - 1
			end
			from until i < 1 or else not is_blank_code (Result.code (i)) loop
				i := i - 1
			end
			from until i < 1 or else is_blank_code (Result.code (i)) loop
				i := i - 1
			end
			if i >= 1 then
				Result := Result.substring (1, i)
			else
				create Result.make_empty
			end
			Result.right_adjust
		ensure
			shorter: Result.count < a_text.count
			prefix_of_text: a_text.to_string_32.starts_with (Result)
		end

	words_of (a_text: READABLE_STRING_GENERAL): ARRAYED_LIST [STRING_32]
			-- The blank-separated words of `a_text', in order.
		local
			i: INTEGER
			l_word: STRING_32
		do
			create Result.make (8)
			create l_word.make_empty
			from i := 1 until i > a_text.count loop
				if is_blank_code (a_text.code (i)) then
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
			no_empty_words: across Result as w all not w.is_empty end
		end

feature -- Constants

	Via_keyword: STRING_32 = "via"
	Via_plain: STRING_32 = "plain"

feature {NONE} -- Implementation

	rules: PARTICIPANT_RULES
		once
			create Result
		end

end
