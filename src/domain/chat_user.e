note
	description: "[
		A participant known to the server - a person or a bot. People have
		a password hash in PBKDF2 form (salt$iterations$hash); bots have
		none and authenticate with tokens. `id' is 0 until the store has
		assigned one.
	]"
	author: "Larry Rix"

class
	CHAT_USER

create
	make

feature {NONE} -- Initialization

	make (a_id: INTEGER_64; a_username: READABLE_STRING_8; a_display_name: READABLE_STRING_GENERAL;
			a_password_hash: READABLE_STRING_8; a_is_admin, a_is_bot: BOOLEAN; a_created_at: SIMPLE_DATE_TIME)
			-- A user; `a_id' is 0 when not yet stored.
		require
			id_non_negative: a_id >= 0
			valid_username: is_valid_username (a_username)
			valid_display_name: is_valid_display_name (a_display_name)
			people_have_hashes: not a_is_bot implies a_password_hash.occurrences ('$') = 2
			bots_have_none: a_is_bot implies a_password_hash.is_empty
		do
			id := a_id
			username := a_username.to_string_8
			display_name := a_display_name.to_string_32
			password_hash := a_password_hash.to_string_8
			is_admin := a_is_admin
			is_bot := a_is_bot
			created_at := a_created_at
			is_active := True
		ensure
			id_set: id = a_id
			username_set: username.same_string (a_username)
			display_set: display_name.same_string_general (a_display_name)
			hash_set: password_hash.same_string (a_password_hash)
			flags_set: is_admin = a_is_admin and is_bot = a_is_bot
			active: is_active
		end

feature -- Access

	id: INTEGER_64
			-- Store identifier; 0 until stored.

	username: STRING_8
			-- Login name: lowercase ASCII letters, digits, underscore; 1..32.

	display_name: STRING_32
			-- What the room shows; 1..40, no bidi control characters.

	password_hash: STRING_8
			-- PBKDF2 `salt$iterations$hash' for people; empty for bots.

	created_at: SIMPLE_DATE_TIME

feature -- Status report

	is_admin: BOOLEAN
	is_bot: BOOLEAN
	is_active: BOOLEAN
			-- May this user log in and post?

	is_stored: BOOLEAN
			-- Has the store assigned an id?
		do
			Result := id > 0
		ensure
			definition: Result = (id > 0)
		end

feature -- Element change

	set_active (a_active: BOOLEAN)
		do
			is_active := a_active
		ensure
			set: is_active = a_active
		end

	set_password_hash (a_hash: READABLE_STRING_8)
			-- Replace the hash (reset or change of password).
		require
			person: not is_bot
			pbkdf2_form: a_hash.occurrences ('$') = 2
		do
			password_hash := a_hash.to_string_8
		ensure
			set: password_hash.same_string (a_hash)
		end

	set_display_name (a_name: READABLE_STRING_GENERAL)
		require
			valid: is_valid_display_name (a_name)
		do
			display_name := a_name.to_string_32
		ensure
			set: display_name.same_string_general (a_name)
		end

	set_id (a_id: INTEGER_64)
			-- The store assigns the id exactly once.
		require
			not_yet_stored: id = 0
			positive: a_id > 0
		do
			id := a_id
		ensure
			set: id = a_id
		end

feature -- Validation (contract support)

	is_valid_username (a_name: READABLE_STRING_8): BOOLEAN
			-- 1..32 characters of [a-z0-9_]?
		local
			i: INTEGER
			c: CHARACTER_8
		do
			Result := a_name.count >= 1 and a_name.count <= Username_maximum
			from i := 1 until i > a_name.count or not Result loop
				c := a_name.item (i)
				Result := (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c = '_'
				i := i + 1
			end
		end

	is_valid_display_name (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- 1..40 characters, not only whitespace, no bidi control characters?
		do
			Result := a_name.count >= 1 and a_name.count <= Display_name_maximum
				and not has_bidi_controls (a_name) and not is_blank (a_name)
		end

	has_bidi_controls (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Does `a_text' contain U+202A..U+202E or U+2066..U+2069 (reading-order overrides)?
		local
			i: INTEGER
			c: NATURAL_32
		do
			from i := 1 until i > a_text.count or Result loop
				c := a_text.code (i)
				Result := (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069)
				i := i + 1
			end
		end

	is_blank (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Only spaces, tabs and line breaks?
		local
			i: INTEGER
			c: NATURAL_32
		do
			Result := True
			from i := 1 until i > a_text.count or not Result loop
				c := a_text.code (i)
				Result := c = 32 or c = 9 or c = 10 or c = 13
				i := i + 1
			end
		end

feature -- Constants

	Username_maximum: INTEGER = 32
	Display_name_maximum: INTEGER = 40

invariant
	id_non_negative: id >= 0
	username_shape: is_valid_username (username)
	display_shape: is_valid_display_name (display_name)
	people_have_hashes: not is_bot implies password_hash.occurrences ('$') = 2
	bots_have_none: is_bot implies password_hash.is_empty

end
