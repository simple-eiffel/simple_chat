note
	description: "A user's standing in a room."
	author: "Larry Rix"

class
	CHAT_MEMBERSHIP

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
			role := a_role.to_string_8
			joined_at := a_joined_at
		ensure
			set: room_id = a_room_id and user_id = a_user_id and role.same_string (a_role)
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
