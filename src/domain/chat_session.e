note
	description: "[
		A logged-in client, or a bot's long-lived token. The client holds
		the token; the server holds only its SHA-256 (DR-006), so a copy of
		the database yields no usable credential.
	]"
	author: "Larry Rix"

class
	CHAT_SESSION

create
	make

feature {NONE} -- Initialization

	make (a_id, a_user_id: INTEGER_64; a_token_hash: READABLE_STRING_8;
			a_created_at, a_expires_at: SIMPLE_DATE_TIME; a_is_bot_token: BOOLEAN)
		require
			id_non_negative: a_id >= 0
			user_stored: a_user_id > 0
			hash_shape: a_token_hash.count = 64
			lifetime: a_created_at < a_expires_at
		do
			id := a_id
			user_id := a_user_id
			token_hash := a_token_hash.to_string_8
			created_at := a_created_at
			last_seen_at := a_created_at
			expires_at := a_expires_at
			is_bot_token := a_is_bot_token
		ensure
			set: id = a_id and user_id = a_user_id and is_bot_token = a_is_bot_token
			hash_set: token_hash.same_string (a_token_hash)
			seen_at_creation: last_seen_at = a_created_at
		end

feature -- Access

	id, user_id: INTEGER_64
	token_hash: STRING_8
	created_at, last_seen_at, expires_at: SIMPLE_DATE_TIME
	is_bot_token: BOOLEAN

feature -- Status report

	is_expired_at (a_now: SIMPLE_DATE_TIME): BOOLEAN
		do
			Result := not (a_now < expires_at)
		ensure
			definition: Result = not (a_now < expires_at)
		end

feature -- Element change

	touch (a_now: SIMPLE_DATE_TIME)
			-- Record use.
		require
			not_before_creation: not (a_now < created_at)
		do
			last_seen_at := a_now
		ensure
			seen: last_seen_at = a_now
		end

	set_id (a_id: INTEGER_64)
		require
			not_yet_stored: id = 0
			positive: a_id > 0
		do
			id := a_id
		ensure
			set: id = a_id
		end

invariant
	id_non_negative: id >= 0
	user_stored: user_id > 0
	hash_shape: token_hash.count = 64
	lifetime: created_at < expires_at
	seen_after_creation: not (last_seen_at < created_at)

end
