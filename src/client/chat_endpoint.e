note
	description: "[
		Where a client talks to: a base URL that passed CHAT_URL_RULES,
		so it is https or this machine's loopback and nothing else -
		which is why `is_secure' holds for every endpoint that exists
		and CHAT_CLIENT can promise never to send a token in clear.
		`is_local' is derived from the URL, never asserted by a caller.
		Built by SERVICE_LOCATOR; every request URL comes from
		`url_for', so no other class concatenates paths onto the base.
	]"
	author: "Larry Rix"

class
	CHAT_ENDPOINT

inherit
	CHAT_URL_RULES

create
	make

feature {NONE} -- Initialization

	make (a_base_url: READABLE_STRING_8)
		require
			acceptable: is_acceptable_url (a_base_url)
		do
			base_url := a_base_url.to_string_8
			is_local := is_loopback_url (a_base_url)
		ensure
			set: base_url.same_string (a_base_url)
			local_derived: is_local = is_loopback_url (a_base_url)
		end

feature -- Access

	base_url: STRING_8

	is_local: BOOLEAN
			-- The service on this machine (a loopback URL)?

	url_for (a_path: READABLE_STRING_8): STRING_8
			-- `base_url' + `a_path'.
		require
			rooted: a_path.starts_with ("/")
		do
			Result := base_url + a_path
		ensure
			exact: Result.same_string (base_url + a_path)
			prefixed: Result.starts_with (base_url)
			suffixed: Result.ends_with (a_path)
		end

feature -- Status report

	is_secure: BOOLEAN
			-- https, or loopback (which needs no TLS)? Derived from the URL alone.
		do
			Result := base_url.starts_with (Https_scheme) or is_local
		ensure
			definition: Result = (base_url.starts_with (Https_scheme) or is_local)
		end

invariant
	acceptable: is_acceptable_url (base_url)
	web_url: is_web_url (base_url)
	no_trailing_slash: not base_url.ends_with ("/")
	local_is_loopback: is_local = is_loopback_url (base_url)
	secure_by_construction: is_secure

end
