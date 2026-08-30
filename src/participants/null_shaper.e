note
	description: "The shaper that does nothing but honour the size limit: `via plain'."
	author: "Larry Rix"

class
	NULL_SHAPER

inherit
	SHAPER

create
	make

feature {NONE} -- Initialization

	make
		do
		end

feature -- Access

	name: STRING_32
		do
			Result := {ADDRESS_PARSER}.Via_plain
		end

	cost_tier: INTEGER
		do
			Result := Tier_none
		end

feature -- Basic operations

	shape (a_text: READABLE_STRING_GENERAL; a_brief: SHAPING_BRIEF): SHAPED_TEXT
			-- `a_text' unchanged, cut to the brief's limit.
		do
			create Result.make_success (a_text.to_string_32.head (a_brief.max_characters))
		ensure then
			unchanged_prefix: a_text.to_string_32.starts_with (Result.text)
		end

end
