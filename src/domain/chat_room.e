note
	description: "[
		A named conversation with members and an ordered event log. v1 has
		one; the model has many.

		Value semantics (Issue 23 / M-D3): `make' copies its incoming text,
		`is_equal' compares by value, `duplicate' builds an independent copy.
		The attributes stay STRING_32; moving them to READABLE_/IMMUTABLE_
		types is a Phase 4 task.
	]"
	author: "Larry Rix"

class
	CHAT_ROOM

inherit
	ANY
		redefine
			is_equal
		end

create
	make

feature {NONE} -- Initialization

	make (a_id: INTEGER_64; a_name: READABLE_STRING_GENERAL; a_created_at: SIMPLE_DATE_TIME)
		require
			id_non_negative: a_id >= 0
			valid_name: is_valid_name (a_name)
		do
			id := a_id
			create name.make_from_string_general (a_name)
			created_at := a_created_at
		ensure
			id_set: id = a_id
			name_set: name.same_string_general (a_name)
			owns_text: name /= a_name
		end

feature -- Access

	id: INTEGER_64
			-- 0 until stored.

	name: STRING_32
			-- 1..64 characters.

	created_at: SIMPLE_DATE_TIME

feature -- Status report

	is_stored: BOOLEAN
		do
			Result := id > 0
		ensure
			definition: Result = (id > 0)
		end

feature -- Element change

	set_id (a_id: INTEGER_64)
		require
			not_yet_stored: id = 0
			positive: a_id > 0
		do
			id := a_id
		ensure
			set: id = a_id
		end

feature -- Comparison

	is_equal (a_other: like Current): BOOLEAN
			-- Do `Current' and `a_other' carry the same values, text compared by content?
		do
			Result := id = a_other.id
				and name.same_string (a_other.name)
				and created_at ~ a_other.created_at
		ensure then
			definition: Result = (id = a_other.id
				and name.same_string (a_other.name)
				and created_at ~ a_other.created_at)
		end

feature -- Duplication

	duplicate: like Current
			-- An independent copy with fresh strings, equal to `Current' by value.
		do
			create Result.make (id, name, created_at)
		ensure
			equal_value: Result ~ Current
			distinct: Result /= Current
			own_text: Result.name /= name
		end

feature -- Validation (contract support)

	is_valid_name (a_name: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := a_name.count >= 1 and a_name.count <= Name_maximum
		end

feature -- Constants

	Name_maximum: INTEGER = 64

invariant
	id_non_negative: id >= 0
	name_shape: is_valid_name (name)

end
