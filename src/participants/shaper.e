note
	description: "[
		Reshapes text at a tool's two edges: a free-form question into the
		tool's strict form (query shaping), or a mechanical result into
		readable prose (response shaping). A shaper never runs anything;
		its output is text that the tool's allowlist will judge like any
		other (addendum 09).
	]"
	author: "Larry Rix"

deferred class
	SHAPER

feature -- Access

	name: STRING_32
			-- How `via' refers to it: "plain", "@qwen", "@claude".
		deferred
		ensure
			given: not Result.is_empty
		end

	cost_tier: INTEGER
			-- `Tier_none', `Tier_local' or `Tier_subscription'.
		deferred
		ensure
			known: Result >= Tier_none and Result <= Tier_subscription
		end

feature -- Basic operations

	shape (a_text: READABLE_STRING_GENERAL; a_brief: SHAPING_BRIEF): SHAPED_TEXT
		require
			text_given: not a_text.is_empty
		deferred
		ensure
			outcome: Result.is_success xor (Result.error /= Void)
			bounded: Result.is_success implies Result.text.count <= a_brief.max_characters
		end

feature {NONE} -- Implementation

	instruction_of (a_brief: SHAPING_BRIEF): STRING_32
			-- The system prompt a brief becomes: the purpose, the tool's
			-- description, the accepted forms, and the hard size limit.
		local
			i: INTEGER
		do
			create Result.make (256)
			if a_brief.purpose.same_string ({SHAPING_BRIEF}.Purpose_query) then
				Result.append ({STRING_32} "Rewrite the user's request as exactly one line in the accepted form of this tool: ")
			else
				Result.append ({STRING_32} "Rephrase this tool output for a chat room, faithful to it, adding nothing: ")
			end
			Result.append (a_brief.description)
			Result.append ({STRING_32} ".")
			from i := 1 until i > a_brief.example_count loop
				if i = 1 then
					Result.append ({STRING_32} " Examples:")
				end
				Result.append ({STRING_32} " ")
				Result.append (a_brief.example (i))
				i := i + 1
			end
			Result.append ({STRING_32} " Reply with the result only, no commentary, at most ")
			Result.append_string_general (a_brief.max_characters.out)
			Result.append ({STRING_32} " characters.")
		ensure
			never_empty: not Result.is_empty
			described: Result.has_substring (a_brief.description)
			bounded_stated: Result.has_substring (a_brief.max_characters.out)
		end

feature -- Constants

	Tier_none: INTEGER = 0
	Tier_local: INTEGER = 1
	Tier_subscription: INTEGER = 2

end
