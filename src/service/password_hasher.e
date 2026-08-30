note
	description: "[
		Password storage policy in one place: PBKDF2-HMAC-SHA256 through
		simple_encryption 2.0.0, with the OWASP floor of 600,000 iterations
		pinned as a contract (DR-005). The stored form is
		salt$iterations$hash, all hex.
	]"
	author: "Larry Rix"

class
	PASSWORD_HASHER

create
	make

feature {NONE} -- Initialization

	make
		do
			create crypto.make
			crypto.set_pbkdf2_iterations (Minimum_iterations.max (crypto.pbkdf2_iterations))
		ensure
			floor_applied: crypto.pbkdf2_iterations >= Minimum_iterations
		end

feature -- Basic operations

	hash (a_password: READABLE_STRING_GENERAL): STRING_8
			-- A fresh salted PBKDF2 hash of `a_password' (UTF-8 bytes).
		require
			long_enough: a_password.count >= Minimum_characters
		do
			Result := crypto.hash_password (utf8 (a_password))
		ensure
			format: (create {CHAT_USER_RULES}).is_pbkdf2 (Result)
			floor: iterations_of (Result) >= Minimum_iterations
			salted: salt_of (Result).count = 32
			never_plaintext: not Result.has_substring (utf8 (a_password))
				-- probabilistic: a password of >= 8 characters appearing by chance in 96 random hex digits is a 1-in-2^32 event
		end

	verify (a_password: READABLE_STRING_GENERAL; a_stored: READABLE_STRING_8): BOOLEAN
			-- Does `a_password' produce `a_stored'? Constant-time comparison inside.
		require
			not_empty: not a_password.is_empty
			stored_given: not a_stored.is_empty
		do
			Result := crypto.verify_password (utf8 (a_password), a_stored.to_string_8)
		end

feature -- Access (contract support)

	iterations_of (a_stored: READABLE_STRING_8): INTEGER
			-- The middle field of salt$iterations$hash; 0 when malformed.
		local
			l_parts: LIST [STRING_8]
		do
			l_parts := a_stored.to_string_8.split ('$')
			if l_parts.count = 3 and then l_parts.i_th (2).is_integer then
				Result := l_parts.i_th (2).to_integer
			end
		ensure
			non_negative: Result >= 0
		end

	salt_of (a_stored: READABLE_STRING_8): STRING_8
			-- The first field; empty when malformed.
		local
			l_parts: LIST [STRING_8]
		do
			l_parts := a_stored.to_string_8.split ('$')
			if l_parts.count = 3 then
				Result := l_parts.i_th (1)
			else
				create Result.make_empty
			end
		end

feature -- Constants

	Minimum_iterations: INTEGER = 600000

	Minimum_characters: INTEGER = 8
			-- The shortest password this hasher accepts (SERVER_CONFIG.password_minimum is never lower).
			-- OWASP: PBKDF2-HMAC-SHA256 at 600,000 iterations or more.

feature {NONE} -- Implementation

	crypto: SIMPLE_ENCRYPTION

	utf8 (a_text: READABLE_STRING_GENERAL): STRING_8
			-- `a_text' as UTF-8 bytes, so non-ASCII passwords hash consistently.
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text)
		end

invariant
	floor_is_owasp: Minimum_iterations = 600000
	crypto_at_floor: crypto.pbkdf2_iterations >= Minimum_iterations

end
