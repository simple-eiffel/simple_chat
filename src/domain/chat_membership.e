note
	description: "[
		A user's standing in a room.

		Value semantics (Issue 23 / M-D3): `make' copies its incoming text,
		`is_equal' compares by value, `duplicate' builds an independent copy.
		The `role' attribute stays STRING_8; moving it to
		READABLE_/IMMUTABLE_ types is a Phase 4 task.
	]"
	author: "Larry Rix"

class
	CHAT_MEMBERSHIP

inherit
	ANY
		redefine
			is_equal
		end

create
	make

feature {NONE} -- Initialization

	make (a_room_id, a_user_id: INTEGER_64; a_role: READABLE_STRING_8; a_joined_at: SIMPLE_DATE_TIME)
		require
			room_stored: a_room_id > 0
			user_stored: a_user_id > 0
			known_role: is_known_role (a_role)
		do
			room_id := a_room_id
			user_id := a_user_id
			create role.make_from_string (a_role)
			joined_at := a_joined_at
		ensure
			set: room_id = a_room_id and user_id = a_user_id and role.same_string (a_role)
			owns_text: role /= a_role
		end

feature -- Access

	room_id, user_id: INTEGER_64
	role: STRING_8
	joined_at: SIMPLE_DATE_TIME

feature -- Status report

	is_room_admin: BOOLEAN
		do
			Result := role.same_string (Role_admin)
		end

feature -- Comparison

	is_equal (a_other: like Current): BOOLEAN
			-- Do `Current' and `a_other' carry the same values, text compared by content?
		do
			Result := room_id = a_other.room_id
				and user_id = a_other.user_id
				and role.same_string (a_other.role)
				and joined_at ~ a_other.joined_at
		ensure then
			definition: Result = (room_id = a_other.room_id
				and user_id = a_other.user_id
				and role.same_string (a_other.role)
				and joined_at ~ a_other.joined_at)
		end

feature -- Duplication

	duplicate: like Current
			-- An independent copy with fresh strings, equal to `Current' by value.
		do
			create Result.make (room_id, user_id, role, joined_at)
		ensure
			equal_value: Result ~ Current
			distinct: Result /= Current
			own_text: Result.role /= role
		end

feature -- Validation (contract support)

	is_known_role (a_role: READABLE_STRING_8): BOOLEAN
		do
			Result := a_role.same_string (Role_member) or a_role.same_string (Role_admin)
		end

feature -- Constants

	Role_member: STRING_8 = "member"
	Role_admin: STRING_8 = "admin"

invariant
	room_stored: room_id > 0
	user_stored: user_id > 0
	known_role: is_known_role (role)

end
