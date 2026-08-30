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

feature -- Status report

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
