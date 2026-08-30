note
	description: "A shaper on a local model through simple_ai_client's OLLAMA_CLIENT: the cheap default for phrasing (Tier_local)."
	author: "Larry Rix"

class
	OLLAMA_SHAPER

inherit
	SHAPER

create
	make

feature {NONE} -- Initialization

	make (a_name: READABLE_STRING_GENERAL; a_client: OLLAMA_CLIENT; a_model: READABLE_STRING_GENERAL)
		require
			name_given: not a_name.is_empty
			model_given: not a_model.is_empty
		do
			name := a_name.to_string_32
			client := a_client
			model := a_model.to_string_32
		ensure
			name_set: name.same_string_general (a_name)
			model_set: model.same_string_general (a_model)
		end

feature -- Access

	name: STRING_32
	model: STRING_32

	cost_tier: INTEGER
		do
			Result := Tier_local
		end

feature -- Basic operations

	shape (a_text: READABLE_STRING_GENERAL; a_brief: SHAPING_BRIEF): SHAPED_TEXT
		do
			create Result.make_error (create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_not_implemented, "Not implemented (Phase 1 skeleton)", 501))
			-- Implementation in Phase 4: client.set_model (model); ask_with_system (brief prompt, a_text); cut to limit
		end

feature {NONE} -- Implementation

	client: OLLAMA_CLIENT

invariant
	model_given: not model.is_empty

end
