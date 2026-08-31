note
	description: "[
		A participant known to the server - a person or a bot. People have
		a password hash in PBKDF2 form (salt$iterations$hash, checked by
		CHAT_USER_RULES.is_pbkdf2); bots have none and authenticate with
		tokens. `id' is 0 until the store has assigned one. The rules live
		in CHAT_USER_RULES; this class only delegates to them.

		Value semantics (Issue 23 / M-D3): `make' copies its incoming text
		into fresh strings (EiffelBase `to_string_8'/`to_string_32' return
		the argument itself when it already has the target type, so plain
		assignment would alias), `is_equal' compares field by field by value,
		and `duplicate' builds an independent copy - so a store can keep and
		return copies no caller can reach. The attributes stay
		STRING_8/STRING_32; moving them to READABLE_/IMMUTABLE_ types is a
		Phase 4 task.

		The bot marker is reserved (NEW-4): a person's display name may not
		contain it anywhere; a bot's must begin with it.
	]"
	author: "Larry Rix"

class
	CHAT_USER

inherit
	ANY
		redefine
			is_equal
		end

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
			humans_unmarked: not a_is_bot implies rules.is_valid_human_display_name (a_display_name)
			bots_marked: a_is_bot implies rules.is_marked_display_name (a_display_name)
			people_have_hashes: not a_is_bot implies rules.is_pbkdf2 (a_password_hash)
			bots_have_none: a_is_bot implies a_password_hash.is_empty
		do
			id := a_id
			create username.make_from_string (a_username)
			create display_name.make_from_string_general (a_display_name)
			create password_hash.make_from_string (a_password_hash)
			is_admin := a_is_admin
			is_bot := a_is_bot
			created_at := a_created_at
			is_active := True
		ensure
			id_set: id = a_id
			username_set: username.same_string (a_username)
			display_set: display_name.same_string_general (a_display_name)
			hash_set: password_hash.same_string (a_password_hash)
			owns_text: username /= a_username and display_name /= a_display_name and password_hash /= a_password_hash
			flags_set: is_admin = a_is_admin and is_bot = a_is_bot
			created_set: created_at = a_created_at
			active: is_active
		end

feature -- Access

	id: INTEGER_64
			-- Store identifier; 0 until stored.

	username: STRING_8
			-- Login name: lowercase ASCII letters, digits, underscore; 1..32. Immutable.

	display_name: STRING_32
			-- What the room shows; 1..40, visible, no controls or format characters.

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
			rest_unchanged: id = old id and username = old username and display_name = old display_name and password_hash = old password_hash
		end

	set_password_hash (a_hash: READABLE_STRING_8)
			-- Replace the hash (reset or change of password).
		require
			person: not is_bot
			pbkdf2_form: rules.is_pbkdf2 (a_hash)
		do
			create password_hash.make_from_string (a_hash)
		ensure
			set: password_hash.same_string (a_hash)
			owns_text: password_hash /= a_hash
			rest_unchanged: id = old id and username = old username and display_name = old display_name and is_active = old is_active
		end

	set_display_name (a_name: READABLE_STRING_GENERAL)
		require
			valid: is_valid_display_name (a_name)
			humans_unmarked: not is_bot implies rules.is_valid_human_display_name (a_name)
			bots_marked: is_bot implies rules.is_marked_display_name (a_name)
		do
			create display_name.make_from_string_general (a_name)
		ensure
			set: display_name.same_string_general (a_name)
			owns_text: display_name /= a_name
			rest_unchanged: id = old id and username = old username and password_hash = old password_hash and is_active = old is_active
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
			rest_unchanged: username = old username and display_name = old display_name and password_hash = old password_hash and is_active = old is_active
		end

feature -- Comparison

	is_equal (a_other: like Current): BOOLEAN
			-- Do `Current' and `a_other' carry the same values, field by
			-- field, text compared by content (D5: copies compare equal)?
		do
			Result := id = a_other.id
				and username.same_string (a_other.username)
				and display_name.same_string (a_other.display_name)
				and password_hash.same_string (a_other.password_hash)
				and is_admin = a_other.is_admin
				and is_bot = a_other.is_bot
				and is_active = a_other.is_active
				and created_at ~ a_other.created_at
		ensure then
			definition: Result = (id = a_other.id
				and username.same_string (a_other.username)
				and display_name.same_string (a_other.display_name)
				and password_hash.same_string (a_other.password_hash)
				and is_admin = a_other.is_admin
				and is_bot = a_other.is_bot
				and is_active = a_other.is_active
				and created_at ~ a_other.created_at)
		end

feature -- Duplication

	duplicate: like Current
			-- An independent copy with fresh strings, equal to `Current' by value.
		do
			create Result.make (id, username, display_name, password_hash, is_admin, is_bot, created_at)
			Result.set_active (is_active)
		ensure
			equal_value: Result ~ Current
			distinct: Result /= Current
			own_text: Result.username /= username and Result.display_name /= display_name and Result.password_hash /= password_hash
		end

feature -- Validation (contract support)

	is_valid_username (a_name: READABLE_STRING_8): BOOLEAN
		do
			Result := rules.is_valid_username (a_name)
		end

	is_valid_display_name (a_name: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := rules.is_valid_display_name (a_name)
		end

	rules: CHAT_USER_RULES
		once
			create Result
		end

feature -- Constants

	Username_maximum: INTEGER = 32
	Display_name_maximum: INTEGER = 40

invariant
	id_non_negative: id >= 0
	username_shape: is_valid_username (username)
	display_shape: is_valid_display_name (display_name)
	humans_unmarked: not is_bot implies rules.is_valid_human_display_name (display_name)
	bots_marked: is_bot implies rules.is_marked_display_name (display_name)
	people_have_hashes: not is_bot implies rules.is_pbkdf2 (password_hash)
	bots_have_none: is_bot implies password_hash.is_empty

end
