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

feature -- Constants

	Tier_none: INTEGER = 0
	Tier_local: INTEGER = 1
	Tier_subscription: INTEGER = 2

end
