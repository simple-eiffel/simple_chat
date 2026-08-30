note
	description: "[
		Mints session and bot tokens: 32 bytes from the operating system's
		CSPRNG, given to the client as 64 hex characters; the store keeps
		only the SHA-256 of the token (DR-006).
	]"
	author: "Larry Rix"

class
	SESSION_ISSUER

create
	make

feature {NONE} -- Initialization

	make
		do
			create crypto.make
		end

feature -- Basic operations

	issue (a_user: CHAT_USER; a_lifetime_seconds: INTEGER_64; a_is_bot_token: BOOLEAN): TUPLE [token: STRING_8; session: CHAT_SESSION]
			-- A fresh token for `a_user' and the session row to store for it.
		require
			active: a_user.is_active
			stored: a_user.is_stored
			lifetime_positive: a_lifetime_seconds > 0
			bots_get_bot_tokens: a_is_bot_token = a_user.is_bot
		local
			l_token: STRING_8
			l_now: SIMPLE_DATE_TIME
			l_session: CHAT_SESSION
		do
			l_token := crypto.random_hex (32)
			create l_now.make_now
			create l_session.make (0, a_user.id, hash_of (l_token), l_now, l_now.plus_seconds (a_lifetime_seconds), a_is_bot_token)
			Result := [l_token, l_session]
		ensure
			token_entropy: Result.token.count = 64
			only_hash_stored: Result.session.token_hash.same_string (hash_of (Result.token))
			not_the_token: not Result.session.token_hash.same_string (Result.token)
			expiry_ahead: Result.session.created_at < Result.session.expires_at
			right_user: Result.session.user_id = a_user.id
			right_kind: Result.session.is_bot_token = a_is_bot_token
		end

feature -- Access (contract support)

	hash_of (a_token: READABLE_STRING_8): STRING_8
			-- SHA-256 of `a_token', hex.
		require
			token_given: not a_token.is_empty
		do
			Result := crypto.sha256 (a_token.to_string_8)
		ensure
			hash_shape: Result.count = 64
		end

feature {NONE} -- Implementation

	crypto: SIMPLE_ENCRYPTION

end
