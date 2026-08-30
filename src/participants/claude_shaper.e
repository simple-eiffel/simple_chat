note
	description: "A shaper on Claude through CLAUDE_CODE_CLIENT: chosen with `via @claude', costs subscription quota (Tier_subscription)."
	author: "Larry Rix"

class
	CLAUDE_SHAPER

inherit
	SHAPER

create
	make

feature {NONE} -- Initialization

	make (a_name: READABLE_STRING_GENERAL; a_client: CLAUDE_CODE_CLIENT)
		require
			name_given: not a_name.is_empty
		do
			name := a_name.to_string_32
			client := a_client
		ensure
			name_set: name.same_string_general (a_name)
		end

feature -- Access

	name: STRING_32

	cost_tier: INTEGER
		do
			Result := Tier_subscription
		end

feature -- Basic operations

	shape (a_text: READABLE_STRING_GENERAL; a_brief: SHAPING_BRIEF): SHAPED_TEXT
		do
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501))
			-- Implementation in Phase 4
		end

feature {NONE} -- Implementation

	client: CLAUDE_CODE_CLIENT

end
