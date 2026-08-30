note
	description: "[
		What a shaper is told: whether it is shaping a query or a response,
		the tool's description and accepted forms (with examples), the
		audience, and the size limit. The examples are read through their
		model (`examples_model', `example (i)'): the list itself is not
		exported, so a shaper cannot change the brief it was handed.
	]"
	author: "Larry Rix"

class
	SHAPING_BRIEF

create
	make

feature {NONE} -- Initialization

	make (a_purpose: READABLE_STRING_8; a_description: READABLE_STRING_GENERAL; a_max_characters: INTEGER)
		require
			known_purpose: a_purpose.same_string (Purpose_query) or a_purpose.same_string (Purpose_response)
			described: not a_description.is_empty
			max_positive: a_max_characters > 0
		do
			purpose := a_purpose.to_string_8
			description := a_description.to_string_32
			max_characters := a_max_characters
			create examples.make (4)
		ensure
			set: purpose.same_string (a_purpose) and max_characters = a_max_characters
			described: description.same_string_general (a_description)
			no_examples: examples_model.is_empty
		end

feature -- Model Queries (for MML postconditions)

	examples_model: MML_SEQUENCE [STRING_32]
			-- The examples, in the order given.
		do
			create Result
			across examples as ic loop
				Result := Result & ic
			end
		ensure
			same_count: Result.count = examples.count
		end

feature -- Access

	purpose: STRING_8
	description: STRING_32
	max_characters: INTEGER

	example_count: INTEGER
		do
			Result := examples.count
		ensure
			definition: Result = examples_model.count
		end

	example (i: INTEGER): STRING_32
			-- The `i'-th accepted form.
		require
			in_range: i >= 1 and i <= example_count
		do
			Result := examples [i]
		ensure
			from_model: Result.same_string (examples_model [i])
		end

feature -- Element change

	add_example (a_example: READABLE_STRING_GENERAL)
		require
			given: not a_example.is_empty
		do
			examples.extend (a_example.to_string_32)
		ensure
			appended: examples_model |=| ((old examples_model) & a_example.to_string_32)
			one_more: example_count = old example_count + 1
			at_end: example (example_count).same_string_general (a_example)
			rest_unchanged: purpose.same_string (old purpose) and description.same_string (old description) and max_characters = old max_characters
		end

feature -- Constants

	Purpose_query: STRING_8 = "query"
	Purpose_response: STRING_8 = "response"

feature {NONE} -- Implementation

	examples: ARRAYED_LIST [STRING_32]
			-- Accepted forms, for query shaping.

invariant
	known_purpose: purpose.same_string (Purpose_query) or purpose.same_string (Purpose_response)
	described: not description.is_empty
	max_positive: max_characters > 0
	model_consistent: examples_model.count = examples.count

end
