note
	description: "A named conversation with members and an ordered event log. v1 has one; the model has many."
	author: "Larry Rix"

class
	CHAT_ROOM

create
	make

feature {NONE} -- Initialization

	make (a_id: INTEGER_64; a_name: READABLE_STRING_GENERAL; a_created_at: SIMPLE_DATE_TIME)
		require
			id_non_negative: a_id >= 0
			valid_name: is_valid_name (a_name)
		do
			id := a_id
			name := a_name.to_string_32
			created_at := a_created_at
		ensure
			id_set: id = a_id
			name_set: name.same_string_general (a_name)
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
