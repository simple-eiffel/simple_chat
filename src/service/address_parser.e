note
	description: "[
		Recognizes an addressed message: "@handle request", or a configured
		alias such as "Claude:" / "ROBOT:", case-insensitive, at the very
		start; with an optional trailing "via <choice>" (addendum 09).
		Only handles present in the registry are addresses; anything else
		is ordinary text.
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

feature -- Basic operations

	parse (a_body: READABLE_STRING_GENERAL): detachable ADDRESSED_REQUEST
			-- The address at the start of `a_body', or Void when it is not addressed.
		do
			-- Implementation in Phase 4
		ensure
			known_handle: attached Result as r implies registry.has (r.handle)
			text_present: attached Result as r implies not r.text.is_empty
			consistent: (Result /= Void) = is_addressed (a_body)
		end

	is_addressed (a_body: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_body' begin with a registered handle or alias?
		do
			-- Implementation in Phase 4
		end

feature -- Constants

	Via_keyword: STRING_32 = "via"
	Via_plain: STRING_32 = "plain"

end
