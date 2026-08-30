note
	description: "A scripted SHAPER for the assault suite: a local-tier shaper that answers with a fixed text - which may be unsafe for a tool - or fails on request."
	author: "Larry Rix"

class
	MOCK_SHAPER

inherit
	SHAPER

create
	make

feature {NONE} -- Initialization

	make (a_name, a_scripted_text: READABLE_STRING_GENERAL)
		require
			name_is_handle: (create {PARTICIPANT_RULES}).is_valid_handle (a_name)
			scripted: not a_scripted_text.is_empty
		do
			create name.make_from_string_general (a_name)
			create scripted_text.make_from_string_general (a_scripted_text)
		ensure
			name_set: name.same_string_general (a_name)
		end

feature -- Access

	name: STRING_32
	scripted_text: STRING_32
	should_fail: BOOLEAN

	cost_tier: INTEGER
		do
			Result := Tier_local
		end

feature -- Element change

	set_should_fail (a_fail: BOOLEAN)
		do
			should_fail := a_fail
		ensure
			set: should_fail = a_fail
		end

feature -- Basic operations

	shape (a_text: READABLE_STRING_GENERAL; a_brief: SHAPING_BRIEF): SHAPED_TEXT
		do
			if should_fail then
				create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, "scripted shaper failure", 503))
			else
				create Result.make_success (scripted_text.head (a_brief.max_characters))
			end
		ensure then
			scripted: (Result.is_success and not should_fail) implies scripted_text.starts_with (Result.text)
			fails_on_request: should_fail implies not Result.is_success
		end

end
