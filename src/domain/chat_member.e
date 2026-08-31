note
	description: "[
		The public view of a user: what the roster, the JSON API and the
		client hold. No password hash ever lives here (CHAT_USER keeps
		that on the server), so a client can build one from the wire
		without inventing a hash to satisfy CHAT_USER's invariant.

		Value semantics (Issue 23 / M-D3): `make' copies its incoming text,
		`is_equal' compares by value, `duplicate' builds an independent copy.
		The attributes stay STRING_8/STRING_32; moving them to
		READABLE_/IMMUTABLE_ types is a Phase 4 task.
	]"
	author: "Larry Rix"

class
	CHAT_MEMBER

inherit
	ANY
		redefine
			is_equal
		end

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
			create username.make_from_string (a_username)
			create display_name.make_from_string_general (a_display_name)
			is_admin := a_is_admin
			is_bot := a_is_bot
		ensure
			set: id = a_id and username.same_string (a_username) and display_name.same_string_general (a_display_name)
			owns_text: username /= a_username and display_name /= a_display_name
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

feature -- Comparison

	is_equal (a_other: like Current): BOOLEAN
			-- Do `Current' and `a_other' carry the same values, text compared by content?
		do
			Result := id = a_other.id
				and username.same_string (a_other.username)
				and display_name.same_string (a_other.display_name)
				and is_admin = a_other.is_admin
				and is_bot = a_other.is_bot
		ensure then
			definition: Result = (id = a_other.id
				and username.same_string (a_other.username)
				and display_name.same_string (a_other.display_name)
				and is_admin = a_other.is_admin
				and is_bot = a_other.is_bot)
		end

feature -- Duplication

	duplicate: like Current
			-- An independent copy with fresh strings, equal to `Current' by value.
		do
			create Result.make (id, username, display_name, is_admin, is_bot)
		ensure
			equal_value: Result ~ Current
			distinct: Result /= Current
			own_text: Result.username /= username and Result.display_name /= display_name
		end

invariant
	positive_id: id > 0
	valid_username: (create {CHAT_USER_RULES}).is_valid_username (username)
	valid_display_name: (create {CHAT_USER_RULES}).is_valid_display_name (display_name)

end
