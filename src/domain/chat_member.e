note
	description: "[
		The public view of a user: what the roster, the JSON API and the
		client hold. No password hash ever lives here (CHAT_USER keeps
		that on the server), so a client can build one from the wire
		without inventing a hash to satisfy CHAT_USER's invariant.
	]"
	author: "Larry Rix"

class
	CHAT_MEMBER

create
	make

feature {NONE} -- Initialization

	make (a_id: INTEGER_64; a_username: READABLE_STRING_8; a_display_name: READABLE_STRING_GENERAL; a_is_admin, a_is_bot: BOOLEAN)
		require
			positive_id: a_id > 0
			valid_username: (create {CHAT_USER_RULES}).is_valid_username (a_username)
			valid_display_name: (create {CHAT_USER_RULES}).is_valid_display_name (a_display_name)
		do
			id := a_id
			username := a_username.to_string_8
			display_name := a_display_name.to_string_32
			is_admin := a_is_admin
			is_bot := a_is_bot
		ensure
			set: id = a_id and username.same_string (a_username) and display_name.same_string_general (a_display_name)
			flags_set: is_admin = a_is_admin and is_bot = a_is_bot
		end

feature -- Access

	id: INTEGER_64
	username: STRING_8
	display_name: STRING_32

	mention: STRING_32
			-- "@" + username, as typed in a message.
		do
			create Result.make_from_string_general ("@" + username)
		ensure
			addressed: Result.starts_with ({STRING_32} "@")
		end

feature -- Status report

	is_admin: BOOLEAN
	is_bot: BOOLEAN

invariant
	positive_id: id > 0
	valid_username: (create {CHAT_USER_RULES}).is_valid_username (username)
	valid_display_name: (create {CHAT_USER_RULES}).is_valid_display_name (display_name)

end
